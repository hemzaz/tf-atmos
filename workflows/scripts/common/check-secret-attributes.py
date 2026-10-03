#!/usr/bin/env python3
"""Check that every secretsmanager `secrets` entry uses only attributes the component declares.

Usage: check-secret-attributes.py <components/terraform dir> < describe-stacks.json
Reads `atmos describe stacks --process-functions=false --format json` on stdin.

The secretsmanager component types `secrets` as map(object({...})). Terraform's
object type conversion silently drops attributes the type does not declare, so
a misspelling such as `pasword_length: 48` plans cleanly and the secret falls
back to the default length. No variable validation can see a dropped attribute,
so this compares each entry's keys, in every instance of the component
(abstract ones included, since their vars are inherited), with the attribute
names parsed from the component's own variables.tf. Exits 1 on any unknown
attribute.
"""
import json
import pathlib
import re
import sys

COMPONENT = "secretsmanager"
VARIABLE = "secrets"
ATTRIBUTE = re.compile(r"^\s*([a-z_][a-z0-9_]*)\s*=")


def allowed_attributes(variables_tf: str) -> set[str]:
    """Attribute names of `variable "secrets" { type = map(object({ ... })) }`."""
    match = re.search(
        r'variable\s+"' + VARIABLE + r'"\s*\{\s*type\s*=\s*map\(object\(\{(.*?)\n\s*\}\)\)',
        variables_tf,
        re.DOTALL,
    )
    if match is None:
        raise ValueError(f'variable "{VARIABLE}" with a map(object({{...}})) type not found')
    if "object(" in match.group(1):
        # The match ends at the first `}))`, so a nested object would be cut
        # short and its attributes read as the entry's own.
        raise ValueError(f'variable "{VARIABLE}" nests an object(...) type, which this check cannot read')
    names = {m.group(1) for line in match.group(1).splitlines() if (m := ATTRIBUTE.match(line))}
    if not names:
        raise ValueError(f'variable "{VARIABLE}" declares no attributes')
    return names


def check(stacks: dict, allowed: set[str]) -> list[str]:
    errors = []
    for stack_name, stack in sorted(stacks.items()):
        instances = (stack.get("components") or {}).get("terraform") or {}
        for name, instance in sorted(instances.items()):
            if instance.get("component") != COMPONENT:
                continue
            secrets = (instance.get("vars") or {}).get(VARIABLE) or {}
            for key, entry in sorted(secrets.items()):
                where = f"{stack_name}: {name} {VARIABLE}.{key}"
                if not isinstance(entry, dict):
                    errors.append(f"{where} is not a mapping")
                    continue
                unknown = sorted(set(entry) - allowed)
                if unknown:
                    errors.append(f"{where} has unknown attribute(s) {', '.join(unknown)}")
    return errors


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__.splitlines()[2], file=sys.stderr)
        return 2
    variables_tf = pathlib.Path(sys.argv[1], COMPONENT, "variables.tf").read_text()
    allowed = allowed_attributes(variables_tf)
    errors = check(json.load(sys.stdin), allowed)
    for error in errors:
        print(f"ERROR {error}")
    if errors:
        print(f"{len(errors)} unknown secret attribute(s); allowed: {', '.join(sorted(allowed))}")
        return 1
    print(f"every {COMPONENT} {VARIABLE} entry uses only attributes its variables.tf declares")
    return 0


if __name__ == "__main__":
    sys.exit(main())
