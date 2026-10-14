#!/usr/bin/env python3
"""Fail a local state read that an instance resolves in a stack without its target.

Atmos resolves every !terraform.state / !terraform.output read in an instance's
`metadata.inherits` chain, even one the instance overrides: a read in an
abstract runs for each inheriting instance, and a local read (`<component>
<expr>`, no stack argument) of a component its stack does not declare stops
`describe component` and plan with "Could not find the component <reader> in
the stack <stack>". The DR standbys, with no kms/main, hit this (#372).

Reads `atmos describe stacks --process-functions=false --include-empty-stacks
--format json` on stdin. For every real (non-abstract) terraform instance in
every stack, it collects the local reads in the instance itself and in each
abstract of its `inheritance` chain (as resolved in that stack), and fails one
whose target is not a real instance of that stack. A cross-stack read
(`<component> <stack> <expr>`) is skipped. A disabled instance
(`metadata.enabled: false`) is checked like an enabled one, as reader and as
target: it is meant to be enabled later (a DR standby's components at failover),
and Atmos finds a disabled target, so only a missing or abstract one fails.
Exit 0 when clean, 1 otherwise.
"""
import importlib.util
import json
import pathlib
import sys
from typing import Any, Iterator

COMMON = pathlib.Path(__file__).resolve().parents[1] / "workflows" / "scripts" / "common"
_spec = importlib.util.spec_from_file_location("check_dependencies", COMMON / "check-dependencies.py")
check_dependencies = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(check_dependencies)  # puts COMMON on sys.path for fixtures
import fixtures  # noqa: E402

CHECK = "check-inherited-state-reads"


def strings(value: Any, path: str) -> Iterator[tuple[str, str]]:
    """Yield (path, string) for every string under value."""
    if isinstance(value, dict):
        for key, item in value.items():
            yield from strings(item, f"{path}.{key}" if path else str(key))
    elif isinstance(value, list):
        for index, item in enumerate(value):
            yield from strings(item, f"{path}[{index}]")
    elif isinstance(value, str):
        yield path, value


def local_reads(config: dict) -> Iterator[tuple[str, str, str]]:
    """Yield (path, target, read) for every local state read in an instance's vars, settings and env."""
    for section in ("vars", "settings", "env"):
        for path, value in strings(config.get(section) or {}, section):
            for target, stack, _ in check_dependencies.reads(value.strip()):
                if stack is None:
                    yield path, target, value.strip()


def check(stacks: dict) -> list[str]:
    errors = []
    for stack_name, stack in sorted(stacks.items()):
        instances = (stack.get("components") or {}).get("terraform") or {}
        real = {name for name, config in instances.items()
                if ((config or {}).get("metadata") or {}).get("type") != "abstract"}
        for name in sorted(real):
            config = instances[name] or {}
            for source in [name, *(config.get("inheritance") or [])]:
                for path, target, read in local_reads(instances.get(source) or {}):
                    if target in real:
                        continue
                    origin = "" if source == name else f" inherited from {source}"
                    errors.append(
                        f"{stack_name}: {name} resolves `{read}` ({path}{origin}), "
                        f"but {target} is not a real instance of {stack_name}"
                    )
    return errors


def main() -> int:
    errors = fixtures.fatal(check(json.load(sys.stdin)), CHECK)
    for error in errors:
        print(f"ERROR {error}")
    if errors:
        print(f"{len(errors)} local state read(s) whose target is not in the reader's stack "
              "(move a read out of the abstract onto the instances whose stacks declare its target)")
        return 1
    print("every local !terraform.state/!terraform.output read an instance resolves, its own or "
          "inherited from an abstract, names a real instance of its stack")
    return 0


if __name__ == "__main__":
    sys.exit(main())
