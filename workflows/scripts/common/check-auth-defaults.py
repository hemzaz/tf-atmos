#!/usr/bin/env python3
"""Fail any committed Atmos auth default: only a profile (profiles/<role>/atmos.yaml) may hold one.

Usage: check-auth-defaults.py --config <describe config JSON> --profile-config <JSON> --profile-config-unset <JSON> < <describe stacks JSON>
  --config: `atmos describe config --format json` (atmos.yaml as Atmos loads it);
  --profile-config: the same with the CI profile merged in, as the lint runs it:
            ATMOS_PROFILE=<ci profile> ATMOS_CI_ROLE_ARN=<--role-arn> atmos describe config --format json;
  --profile-config-unset: the same with ATMOS_CI_ROLE_ARN unset (env -u);
  --role-arn: that dummy; defaults to $ATMOS_CI_ROLE_ARN (lint.yaml sets it once, workflow-level);
  stdin:    `atmos describe stacks --process-functions=false --format json`, where each
            component's `auth` is atmos.yaml's deep-merged with its stack's own.
Both must be described with ATMOS_PROFILE unset (lint step stack-checks does): a profile is
the one place a human default belongs, since CI never sets ATMOS_PROFILE, and only
--profile, ATMOS_PROFILE or atmos.yaml `profiles.default` loads one.

ERROR, each naming the file, the key and the fix:
  - atmos.yaml `profiles.default`: it loads that profile, and its default, in CI too;
  - in atmos.yaml or in a stack's `auth` section: an identity with `default: true` or
    `required: true`, or a provider with `default: true`. Any of them makes every
    non-interactive `atmos terraform plan`/`deploy`/`lint` (CI) try an SSO login and fail
    without a TTY, even with AWS env credentials (E4d0 spike, 2026-10-31).
  - an `aws/iam-identity-center` provider whose `region` differs from the resolved
    `vars.region` of an aws-identity-center instance (its stack's region mixin is the single
    source; atmos.yaml repeats it as a literal because an `!include` there resolves against
    the working directory), or such a provider with no such instance.
  - the CI profile (what --profile-config adds to --config) is not a `github/oidc` provider with
    audience sts.amazonaws.com plus `aws/assume-role` identities via it, holds a default or
    required, edits atmos.yaml's own providers or identities, adds a key outside `auth`, or names the
    role by anything but `!env ATMOS_CI_ROLE_ARN` with no default. The last is read from the resolved
    values: the role must equal --role-arn when the env is set and be empty when it is unset, so a
    literal ARN, a literal hidden as the `!env` default, another env var or a missing one all fail
    (the raw profile text would need a YAML parser here).
A stack-level finding is reported once per stack. Every component type is walked; abstract
instances are skipped. Exits 1 on any ERROR.
"""
import argparse
import json
import os
import sys

IDENTITY_CENTER_PROVIDER = "aws/iam-identity-center"
IDENTITY_CENTER_COMPONENT = "aws-identity-center"
CI_PROFILE = "profiles/<ci profile>/atmos.yaml"
CI_AUDIENCE = "sts.amazonaws.com"
FIX = "move it to profiles/<role>/atmos.yaml and select the role with ATMOS_PROFILE=<role>"


def flagged(auth: dict) -> list[str]:
    """`auth.<...>.<flag>` keys set to true: the defaults (and required) Atmos would act on."""
    keys = []
    for provider, config in sorted(((auth or {}).get("providers") or {}).items()):
        if (config or {}).get("default") is True:
            keys.append(f"auth.providers.{provider}.default")
    for identity, config in sorted(((auth or {}).get("identities") or {}).items()):
        for flag in ("default", "required"):
            if (config or {}).get(flag) is True:
                keys.append(f"auth.identities.{identity}.{flag}")
    return keys


def check_config(config: dict) -> tuple[list[str], set[str]]:
    errors = []
    profile = ((config or {}).get("profiles") or {}).get("default")
    if profile:
        errors.append(
            f"atmos.yaml: profiles.default is {profile!r}, which loads that profile in CI too:"
            " remove it; a human selects a role with ATMOS_PROFILE=<role>"
        )
    keys = flagged((config or {}).get("auth"))
    if profile:
        # It may already sit in that profile: the profiles.default error above carries the fix.
        where = f"atmos.yaml or profiles/{profile}/atmos.yaml (loaded by profiles.default)"
        errors += [f"{where}: {key}: true" for key in keys]
    else:
        errors += [f"atmos.yaml: {key}: true: remove it; {FIX}" for key in keys]
    return errors, set(keys)


def check_stacks(stacks: dict, in_config: set[str]) -> list[str]:
    findings = {}
    for stack_name, stack in sorted((stacks or {}).items()):
        for kind, instances in sorted(((stack or {}).get("components") or {}).items()):
            for name, instance in sorted((instances or {}).items()):
                instance = instance or {}
                if (instance.get("metadata") or {}).get("type") == "abstract":
                    continue
                for key in flagged(instance.get("auth")):
                    if key in in_config:
                        continue
                    found = findings.setdefault((stack_name, key), {"names": [], "files": set()})
                    found["names"].append(f"{kind}/{name}" if kind != "terraform" else name)
                    if instance.get("atmos_stack_file"):
                        found["files"].add(f"stacks/{instance['atmos_stack_file']}.yaml")
    return [
        f"{stack_name}: {key}: true in the stack's auth section"
        f" ({', '.join(sorted(found['files'])) or 'its manifest'} or a file it imports;"
        f" {len(found['names'])} component(s), e.g. {found['names'][0]}): remove it; {FIX}"
        for (stack_name, key), found in sorted(findings.items())
    ]


def check_region(config: dict, stacks: dict) -> list[str]:
    """Each Identity Center provider's region is the aws-identity-center instance's vars.region."""
    providers = {
        name: (provider or {}).get("region")
        for name, provider in sorted((((config or {}).get("auth") or {}).get("providers") or {}).items())
        if (provider or {}).get("kind") == IDENTITY_CENTER_PROVIDER
    }
    if not providers:
        return []
    instances = []
    for stack_name, stack in sorted((stacks or {}).items()):
        for name, instance in sorted((((stack or {}).get("components") or {}).get("terraform") or {}).items()):
            metadata = (instance or {}).get("metadata") or {}
            if metadata.get("component") == IDENTITY_CENTER_COMPONENT and metadata.get("type") != "abstract":
                instances.append((stack_name, name, ((instance or {}).get("vars") or {}).get("region")))
    if not instances:
        return [
            f"atmos.yaml: auth.providers.{name}: no {IDENTITY_CENTER_COMPONENT} instance in any stack to take"
            " its region from: add the instance, or remove the provider"
            for name in providers
        ]
    return [
        f"atmos.yaml: auth.providers.{name}.region is {region!r}, but {IDENTITY_CENTER_COMPONENT} in {stack_name}"
        f" ({instance}) has vars.region {home!r}, Identity Center's home region (set by the region mixin"
        f" under stacks/mixins/region/ that {stack_name} imports, the single source): set"
        f" auth.providers.{name}.region: {home} in atmos.yaml"
        for name, region in providers.items()
        for stack_name, instance, home in instances
        if region != home
    ]


def check_profile(config: dict, profile_config: dict, unset_config: dict, role_arn: str) -> list[str]:
    """What the CI profile adds to atmos.yaml's auth: an OIDC provider and generic identities."""
    base = (config or {}).get("auth") or {}
    merged = (profile_config or {}).get("auth") or {}
    unset = (unset_config or {}).get("auth") or {}
    errors = [
        f"{CI_PROFILE}: adds `{key}` outside `auth`: remove it; the profile holds auth providers and identities only"
        for key in sorted(set(config or {}) | set(profile_config or {}))
        if key != "auth" and (config or {}).get(key) != (profile_config or {}).get(key)
    ]
    added = {}
    for kind in ("providers", "identities"):
        added[kind] = {}
        for name, entry in sorted((merged.get(kind) or {}).items()):
            if name not in (base.get(kind) or {}):
                added[kind][name] = entry
            elif entry != base[kind][name]:
                errors.append(
                    f"{CI_PROFILE}: auth.{kind}.{name} edits atmos.yaml's: don't change atmos.yaml's providers"
                    " or identities in the CI profile, add its own"
                )
    errors += [
        f"{CI_PROFILE}: {key}: true: remove it; CI selects the identity with ATMOS_IDENTITY=ci"
        for key in flagged(added)
    ]
    if not added["providers"] or not added["identities"]:
        errors.append(
            f"{CI_PROFILE}: adds no auth provider or no identity to atmos.yaml's: restore the OIDC provider"
            " (kind github/oidc) and the ci identity (kind aws/assume-role)"
        )
    for name, provider in added["providers"].items():
        kind = (provider or {}).get("kind")
        audience = ((provider or {}).get("spec") or {}).get("audience")
        if kind != "github/oidc" or audience != CI_AUDIENCE:
            errors.append(
                f"{CI_PROFILE}: auth.providers.{name} is kind {kind!r} with audience {audience!r}: set"
                f" kind: github/oidc and spec.audience: {CI_AUDIENCE} (the aud the CI roles trust)"
            )
    for name, identity in added["identities"].items():
        identity = identity or {}
        via = (identity.get("via") or {}).get("provider")
        if identity.get("kind") != "aws/assume-role" or via not in added["providers"]:
            errors.append(
                f"{CI_PROFILE}: auth.identities.{name} is kind {identity.get('kind')!r} via {via!r}: set"
                f" kind: aws/assume-role and via.provider: one of the profile's providers"
                f" ({', '.join(added['providers']) or 'none'})"
            )
        role = (identity.get("principal") or {}).get("assume_role")
        fallback = (((unset.get("identities") or {}).get(name) or {}).get("principal") or {}).get("assume_role")
        if role != role_arn or fallback:
            errors.append(
                f"{CI_PROFILE}: auth.identities.{name}.principal.assume_role resolved to {role!r} with"
                f" ATMOS_CI_ROLE_ARN={role_arn} and to {fallback!r} with it unset (it must be the first and"
                " empty): write `assume_role: !env ATMOS_CI_ROLE_ARN` with no default and no literal ARN"
                " (CI derives it per job, ci-apply-role-arn.py)"
            )
    return errors


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--config", required=True, help="atmos describe config --format json output")
    parser.add_argument(
        "--profile-config", required=True, help="the same, with the CI profile and ATMOS_CI_ROLE_ARN set"
    )
    parser.add_argument(
        "--profile-config-unset", required=True, help="the same as --profile-config with ATMOS_CI_ROLE_ARN unset"
    )
    parser.add_argument(
        "--role-arn",
        default=os.environ.get("ATMOS_CI_ROLE_ARN"),
        help="the ATMOS_CI_ROLE_ARN --profile-config was described with (default: the env's)",
    )
    args = parser.parse_args(argv)
    if not args.role_arn:
        parser.error("--role-arn or ATMOS_CI_ROLE_ARN: the value --profile-config was described with")
    with open(args.config) as handle:
        config = json.load(handle)
    with open(args.profile_config) as handle:
        profile_config = json.load(handle)
    with open(args.profile_config_unset) as handle:
        unset_config = json.load(handle)
    stacks = json.load(sys.stdin)
    defaults, in_config = check_config(config)
    defaults += check_stacks(stacks, in_config)
    region = check_region(config, stacks)
    profile = check_profile(config, profile_config, unset_config, args.role_arn)
    errors = defaults + region + profile
    for error in errors:
        print(f"ERROR {error}")
    if errors:
        why = []
        if defaults:
            why.append(
                "a committed default breaks CI, which cannot log in (only profiles/<role>/atmos.yaml may set one, E4d0)"
            )
        if profile:
            why.append("the CI profile must be an OIDC provider and a generic identity named by env")
        if region:
            why.append("the Identity Center provider's region must be the aws-identity-center stack's")
        print(f"{len(errors)} auth problem(s): {'; '.join(why)}")
        return 1
    print(
        "no auth default or required identity outside profiles/, no profiles.default, the CI profile"
        " is an OIDC provider and a generic identity named by env, and the"
        " Identity Center provider's region is the aws-identity-center stack's"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
