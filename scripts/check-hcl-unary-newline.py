#!/usr/bin/env python3
"""Fail on the HCL shape checkov's parser rejects but terraform accepts.

checkov (3.3.19-3.3.22 pin bc-python-hcl2 0.4.3) cannot parse an expression where a
unary `!x` / `-x` operand ends a line and the next code line starts with a binary
operator (`&&`, `||`, `==`, `!=`, `<`, `>`, `<=`, `>=`, `+`, `-`, `*`, `/`, `%`, `?`), or
continues the operand with `.attr` / `[index]`:

    condition = (
      var.enabled
      && !contains(var.names, "x")    # unary operand ends the line
      && var.other                    # leading `&&` -> lark UnexpectedToken
    )

hcl2.lark gives a unary operation no trailing-newline slot. checkov then lists the file
under `parsing_errors` and scans the rest of the directory as if the file did not exist,
so every check that reads a var default from it can false-pass.

Rewrites that parse: `contains(...) == false`, wrap the operand `(!contains(...))`, put
the operator at the end of the line instead of the start of the next, or one line.

Usage: check-hcl-unary-newline.py [PATH...]   (default: components/terraform)
A directory is searched for *.tf; a file argument is checked whatever its extension.
Exit 0 when clean, 1 on a hit, 2 on a missing or unreadable path. Pure stdlib (runs in the
CI image).
"""

import os
import re
import sys

DEFAULT_PATHS = ("components/terraform",)
SKIP_DIRS = {".terraform", ".git"}

# Leading binary operators checkov rejects after a unary operand (verified one by one
# against bc-python-hcl2 0.4.3). A leading `:` parses, so it is not listed (except after
# a for expression's `in !x`, which also fails but needs a parser to tell apart).
LEADING_BINARY = {
    "&&",
    "||",
    "==",
    "!=",
    "<",
    ">",
    "<=",
    ">=",
    "+",
    "-",
    "*",
    "/",
    "%",
    "?",
}
OPERATORS = sorted(
    "&& || == != <= >= => ... + - * / % < > ! ? : = . , ( ) [ ] { }".split(),
    key=len,
    reverse=True,
)
OPEN, CLOSE = "([{", ")]}"
NUMBER = re.compile(r"\d+(\.\d+)?([eE][+-]?\d+)?")
# HCL identifiers may contain dashes: `a-b` is one identifier, not a subtraction.
IDENT = re.compile(r"[A-Za-z_][A-Za-z0-9_-]*")
HEREDOC = re.compile(r"<<-?([A-Za-z_][A-Za-z0-9_-]*)[ \t]*\r?\n")
REWRITE_HINT = "rewrite as `x == false`, wrap the operand `(!x)`, or end the line with the operator"


class Token:
    __slots__ = ("kind", "text", "line")

    def __init__(self, kind, text, line):
        self.kind, self.text, self.line = kind, text, line

    def __repr__(self):
        return f"{self.kind}({self.text!r}@{self.line})"


def _skip_template(src, i):
    """Return the index just past the closing quote of the string whose body starts at i."""
    n = len(src)
    while i < n:
        c = src[i]
        if c == "\\":
            i += 2
        elif c == '"':
            return i + 1
        elif c == "\n":  # unterminated: stop at the line end rather than eat the file
            return i
        elif src.startswith("$${", i) or src.startswith("%%{", i):
            i += 3
        elif src.startswith("${", i) or src.startswith("%{", i):
            i = _skip_interpolation(src, i + 2)
        else:
            i += 1
    return n


def _skip_interpolation(src, i):
    """Return the index just past the `}` closing an interpolation whose body starts at i."""
    depth, n = 1, len(src)
    while i < n:
        c = src[i]
        if c == '"':
            i = _skip_template(src, i + 1)
            continue
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                return i + 1
        elif c == "\n":
            return i
        i += 1
    return n


def tokenize(src):
    """Tokens: NL, ID, NUM, STR (quoted string or heredoc) and OP. Comments are dropped;
    a line comment leaves its newline, an inline comment counts as whitespace."""
    tokens, i, line, n = [], 0, 1, len(src)
    while i < n:
        c = src[i]
        if c == "\n":
            tokens.append(Token("NL", "\n", line))
            line += 1
            i += 1
        elif c in " \t\r":
            i += 1
        elif c == "#" or src.startswith("//", i):
            end = src.find("\n", i)
            i = n if end < 0 else end
        elif src.startswith("/*", i):
            end = src.find("*/", i + 2)
            end = n if end < 0 else end + 2
            line += src.count("\n", i, end)
            i = end
        elif c == '"':
            end = _skip_template(src, i + 1)
            tokens.append(Token("STR", src[i:end], line))
            line += src.count("\n", i, end)
            i = end
        elif src.startswith("<<", i) and HEREDOC.match(src, i):
            m = HEREDOC.match(src, i)
            start_line, j = line, m.end()
            line += 1
            # The body ends at the first line that is exactly the delimiter (indent allowed).
            while j < n:
                eol = src.find("\n", j)
                eol = n if eol < 0 else eol
                if src[j:eol].strip() == m.group(1):
                    j = eol
                    break
                line += 1
                j = eol + 1
            tokens.append(Token("STR", src[i:j], start_line))
            i = j
        elif c.isdigit():
            m = NUMBER.match(src, i)
            tokens.append(Token("NUM", m.group(), line))
            i = m.end()
        elif IDENT.match(src, i):
            m = IDENT.match(src, i)
            tokens.append(Token("ID", m.group(), line))
            i = m.end()
        else:
            op = next((o for o in OPERATORS if src.startswith(o, i)), c)
            tokens.append(Token("OP", op, line))
            i += len(op)
    return tokens


def _ends_operand(tok):
    if tok.kind in ("NUM", "STR"):
        return True
    if tok.kind == "ID":
        return tok.text not in ("if", "in")
    return tok.kind == "OP" and tok.text in CLOSE


def _skip_group(tokens, i):
    """tokens[i] opens a bracket; return the index just past its match."""
    depth = 0
    while i < len(tokens):
        t = tokens[i]
        if t.kind == "OP" and t.text in OPEN:
            depth += 1
        elif t.kind == "OP" and t.text in CLOSE:
            depth -= 1
            if depth == 0:
                return i + 1
        i += 1
    return i


def _operand_end(tokens, i):
    """Index just past the expr_term that starts at tokens[i] (the unary's operand):
    a literal, identifier, call or bracketed group, then any `.attr`, `.*` or `[index]`.
    """
    if i >= len(tokens):
        return i
    t = tokens[i]
    if t.kind == "OP" and t.text in ("!", "-"):
        return _operand_end(tokens, i + 1)
    if t.kind == "OP" and t.text in OPEN:
        i = _skip_group(tokens, i)
    elif t.kind in ("ID", "NUM", "STR"):
        i += 1
        if (
            t.kind == "ID"
            and i < len(tokens)
            and tokens[i].kind == "OP"
            and tokens[i].text == "("
        ):
            i = _skip_group(tokens, i)
    else:
        return i
    while i < len(tokens):
        t = tokens[i]
        if t.kind == "OP" and t.text == "." and i + 1 < len(tokens):
            nxt = tokens[i + 1]
            if nxt.kind in ("ID", "NUM") or (nxt.kind == "OP" and nxt.text == "*"):
                i += 2
                continue
        if t.kind == "OP" and t.text == "[":
            i = _skip_group(tokens, i)
            continue
        break
    return i


def find_hits(src):
    """Yield (unary_line, operator_line, operator) for each unary operand that ends a line
    whose next code line starts with a binary operator."""
    tokens = tokenize(src)
    prev, prev_unary = (
        None,
        False,
    )  # previous non-newline token, and whether it was a unary op
    for i, t in enumerate(tokens):
        if t.kind == "NL":
            continue
        is_unary = t.kind == "OP" and (
            t.text == "!" or (t.text == "-" and not (prev and _ends_operand(prev)))
        )
        # `!!x` / `-!x`: the outer unary already covers the nested one's operand.
        if is_unary and not prev_unary:
            end = _operand_end(tokens, i + 1)
            if end < len(tokens) and tokens[end].kind == "NL":
                j = end
                while j < len(tokens) and tokens[j].kind == "NL":
                    j += 1
                # `.attr` / `[index]` continuing the operand on the next line
                # fails the same way (`!var\n.b`, `!var.l\n[0]`).
                if (
                    j < len(tokens)
                    and tokens[j].kind == "OP"
                    and (
                        tokens[j].text in LEADING_BINARY or tokens[j].text in (".", "[")
                    )
                ):
                    yield t.line, tokens[j].line, tokens[j].text
        prev, prev_unary = t, is_unary


def iter_tf_files(paths):
    for path in paths:
        if os.path.isfile(path):
            yield path
            continue
        for root, dirs, files in os.walk(path):
            dirs[:] = sorted(d for d in dirs if d not in SKIP_DIRS)
            for name in sorted(files):
                if name.endswith(".tf"):
                    yield os.path.join(root, name)


def main(argv):
    explicit = argv[1:]
    paths = explicit or [p for p in DEFAULT_PATHS if os.path.exists(p)]
    missing = [p for p in explicit if not os.path.exists(p)]
    if missing:
        print(
            f"check-hcl-unary-newline: no such path: {', '.join(missing)}",
            file=sys.stderr,
        )
        return 2
    hits = unreadable = 0
    for path in iter_tf_files(paths):
        try:
            with open(path, encoding="utf-8") as fh:
                src = fh.read()
        except (OSError, UnicodeDecodeError) as exc:
            unreadable += 1
            print(
                f"check-hcl-unary-newline: cannot read {path}: {exc}", file=sys.stderr
            )
            continue
        lines = src.splitlines()
        for unary_line, op_line, op in find_hits(src):
            hits += 1
            print(
                f"{path}:{op_line}: a unary !/- operand ends line {unary_line} and line {op_line} "
                f"starts with `{op}`; checkov cannot parse this file and silently skips it"
            )
            for n in range(unary_line, op_line + 1):
                print(f"  {n:>5} | {lines[n - 1]}")
            print(f"  fix: {REWRITE_HINT}")
    if hits:
        print(f"check-hcl-unary-newline: {hits} hit(s)")
        return 1
    # terraform rejects a non-UTF-8 .tf too, so an unreadable file is an error, not a pass.
    return 2 if unreadable else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
