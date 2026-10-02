"""Template fixtures (stacks/orgs/fnx/fixtures) whose failures are known and not yet fatal.

Each catalog template (stacks/catalog/templates/*.yaml) has a fixture stack,
fnx-fixtures-<short name>, so CI resolves and checks a template no real stack
imports. A template not yet ported to the current component interfaces fails
those checks; listing its fixture here, with the checks it fails (ALL for every
one), reports those failures as KNOWN-BROKEN without failing the run. A port PR
removes its entry, or the checks it fixed, which makes them strict again.

Check names: check-dependencies, check-domains, check-cluster-api-ci,
check-deploy-layers, plan-sweep, tflint (workflows/lint.yaml).
"""
ALL = frozenset({"*"})

KNOWN_BROKEN_FIXTURES = {
    "fnx-fixtures-batch": ALL,
    "fnx-fixtures-pipeline": ALL,
    "fnx-fixtures-serverless": ALL,
    "fnx-fixtures-webapp": ALL,
    # Clean on dependencies, outputs, vars and plan-sweep. No operator path to
    # its private EKS endpoint (no bastion), and deploy-full-stack has no layer
    # for dynamodb, eventbridge, sqs or ses.
    "fnx-fixtures-msplatform": frozenset({"check-cluster-api-ci", "check-deploy-layers"}),
}


def known_broken(stack: str, check: str) -> bool:
    checks = KNOWN_BROKEN_FIXTURES.get(stack, frozenset())
    return checks is ALL or check in checks


def stacks(check: str) -> list[str]:
    """Fixture stacks whose failures of check are not fatal."""
    return sorted(s for s in KNOWN_BROKEN_FIXTURES if known_broken(s, check))


FIXTURE_STAGE = "fixtures"


def unguarded(stacks_json: dict) -> list[str]:
    """Instances in stage fixtures that CI plan/CD/drift would not skip.

    Every one must resolve settings.github.actions_enabled: false (set once in
    stacks/orgs/fnx/fixtures/_defaults.yaml); never relaxed by the allowlist.
    """
    errors = []
    for stack_name, stack in sorted(stacks_json.items()):
        for name, instance in sorted(((stack.get("components") or {}).get("terraform") or {}).items()):
            settings = (instance or {}).get("settings") or {}
            if (settings.get("context") or {}).get("stage") != FIXTURE_STAGE:
                continue
            if (settings.get("github") or {}).get("actions_enabled") is not False:
                errors.append(
                    f"{stack_name}: {name} is in stage {FIXTURE_STAGE} but does not resolve "
                    "settings.github.actions_enabled: false, so CI/CD/drift would run it"
                )
    return errors


def belongs(error: str, stack: str) -> bool:
    """Whether a check's error is about stack: it starts "<stack>: ", or, for
    check-deploy-layers, "<file> `<workflow>`: <stack>: "."""
    return error.startswith(f"{stack}: ") or f"`: {stack}: " in error


def fatal(errors: list[str], check: str) -> list[str]:
    """Print the errors of known-broken fixtures as KNOWN-BROKEN; return the rest."""
    rest = []
    for error in errors:
        if any(belongs(error, stack) for stack in stacks(check)):
            print(f"KNOWN-BROKEN {error}")
        else:
            rest.append(error)
    return rest
