"""Tests for the CI auth of the read-only workflows (stdlib only, text slicing; no YAML parser is
installed in the Atmos image): python3 -m unittest workflows/scripts/common/test_ci_auth_workflows.py

E4e2: the plan of terraform-ci.yml, drift-detection.yml and disaster-recovery.yml sign in through
Atmos auth (profiles/github/atmos.yaml), not aws-actions/configure-aws-credentials. The step that runs
atmos sets ATMOS_PROFILE=github, ATMOS_IDENTITY=ci, ATMOS_CI_ROLE_ARN (the derive step's output) and
ATMOS_CI_REGION at STEP level only; no GITHUB_TOKEN or ATMOS_CI_GITHUB_TOKEN reaches it at any level.
The effective env of a step is workflow env + job env + step env, so each level is read.
"""
import pathlib
import re
import unittest

WORKFLOWS = pathlib.Path(__file__).resolve().parents[3] / ".github/workflows"
AUTH_KEYS = {"ATMOS_PROFILE", "ATMOS_IDENTITY", "ATMOS_CI_ROLE_ARN", "ATMOS_CI_REGION"}
TOKEN_KEYS = {"GITHUB_TOKEN", "ATMOS_CI_GITHUB_TOKEN"}
ARN = "${{ steps.role.outputs.arn }}"
REGION = "${{ vars.AWS_REGION || 'us-east-1' }}"
# workflow file -> (job, a substring only the signed-in step has, that step's exact own env keys or None
# for "at least the auth keys")
TARGETS = {
    "terraform-ci.yml": ("plan", "atmos terraform plan", AUTH_KEYS | {"COMPONENT", "STACK", "TFSTATE_ACCESS"}),
    "drift-detection.yml": ("detect-drift", "atmos terraform plan", None),
    "disaster-recovery.yml": ("disaster-recovery", "run: atmos workflow", None),
}


def job_span(text: str, name: str) -> tuple:
    match = re.search(rf"^  {re.escape(name)}:\n(.*?)(?=^  [A-Za-z0-9_-]+:\n|\Z)", text, re.MULTILINE | re.DOTALL)
    if not match:
        raise AssertionError(f"no job {name}")
    return match.span(1)


def env_keys(text: str, indent: int) -> dict:
    """{KEY: value} of every `env:` mapping at exactly `indent` spaces in `text` (comments skipped)."""
    out = {}
    pattern = rf"^{' ' * indent}env:\n((?:{' ' * (indent + 2)}\S.*\n)+)"
    for block in re.finditer(pattern, text, re.MULTILINE):
        for line in block.group(1).splitlines():
            if line.strip().startswith("#"):
                continue
            key, _, value = line.strip().partition(":")
            out[key] = value.strip()
    return out


def steps(job_text: str) -> list:
    return re.split(r"(?m)^      - ", job_text.split("\n    steps:\n", 1)[1])[1:]


def problems(text: str, workflow: str) -> list:
    """Every way `text` (a workflow file) breaks the CI auth rules."""
    job, marker, exact = TARGETS[workflow]
    start, end = job_span(text, job)
    job_text = text[start:end]
    head = job_text.split("\n    steps:\n", 1)[0] + "\n"
    workflow_env = env_keys(text.split("\njobs:\n", 1)[0], 0)
    job_env = env_keys(head, 4)
    all_steps = steps(job_text)
    target = [s for s in all_steps if marker in s]
    if len(target) != 1:
        return [f"{len(target)} steps contain {marker!r}, want 1"]
    step_env = env_keys(target[0], 8)
    errs = []
    if re.search(r"uses:\s*aws-actions/configure-aws-credentials", text):
        errs.append("configure-aws-credentials is used")
    if not AUTH_KEYS <= set(step_env):
        errs.append(f"step env lacks {sorted(AUTH_KEYS - set(step_env))}")
    if exact is not None and set(step_env) != exact:
        errs.append(f"step env keys differ: extra={sorted(set(step_env) - exact)} missing={sorted(exact - set(step_env))}")
    if step_env.get("ATMOS_PROFILE") != "github" or step_env.get("ATMOS_IDENTITY") != "ci":
        errs.append("step must set ATMOS_PROFILE: github and ATMOS_IDENTITY: ci")
    if step_env.get("ATMOS_CI_ROLE_ARN") != ARN:
        errs.append(f"ATMOS_CI_ROLE_ARN is not {ARN}: {step_env.get('ATMOS_CI_ROLE_ARN')!r}")
    if step_env.get("ATMOS_CI_REGION") != REGION:
        errs.append(f"ATMOS_CI_REGION is not {REGION}: {step_env.get('ATMOS_CI_REGION')!r}")
    for level, env in (("workflow", workflow_env), ("job", job_env)):
        if (AUTH_KEYS - {"ATMOS_CI_REGION"}) & set(env):
            errs.append(f"{level}-level auth env {sorted((AUTH_KEYS - {'ATMOS_CI_REGION'}) & set(env))}")
    for level, env in (("workflow", workflow_env), ("job", job_env), ("step", step_env)):
        if TOKEN_KEYS & set(env):
            errs.append(f"{level}-level token {sorted(TOKEN_KEYS & set(env))} reaches the signed-in step")
    others = [s for s in all_steps if s != target[0] and "ATMOS_IDENTITY" in env_keys(s, 8)]
    if others:
        errs.append("ATMOS_IDENTITY on a step that does not run atmos terraform/workflow")
    if "id-token: write" not in head:
        errs.append("job lacks id-token: write")
    if not re.search(r"- id: role\n(?:        .*\n)*?        run: python3 workflows/scripts/common/ci-apply-role-arn\.py --kind plan\n",
                     job_text):
        errs.append("no `role` step deriving the ARN with --kind plan")
    if workflow == "disaster-recovery.yml" and '--identity "$ATMOS_IDENTITY"' not in target[0]:
        errs.append('atmos workflow lacks --identity "$ATMOS_IDENTITY"')
    return errs


def edit_job(text: str, workflow: str, fn) -> str:
    start, end = job_span(text, TARGETS[workflow][0])
    return text[:start] + fn(text[start:end]) + text[end:]


class CiAuthWorkflowTest(unittest.TestCase):
    texts = {name: (WORKFLOWS / name).read_text() for name in TARGETS}

    def test_the_workflows_follow_the_rules(self):
        for name, text in self.texts.items():
            self.assertEqual(problems(text, name), [], name)

    def test_every_read_only_workflow_uses_the_profile_and_identity_once(self):
        for name, text in self.texts.items():
            self.assertEqual(text.count("ATMOS_IDENTITY: ci"), 1, name)
            self.assertEqual(text.count("ATMOS_PROFILE: github"), 1, name)

    def bad(self, workflow, mutate, expect):
        text = mutate(self.texts[workflow])
        self.assertNotEqual(text, self.texts[workflow], "the mutation changed nothing")
        errs = problems(text, workflow)
        self.assertTrue(any(expect in e for e in errs), f"{workflow}: want {expect!r} in {errs}")

    def test_negative_configure_aws_credentials_back(self):
        step = "      - uses: aws-actions/configure-aws-credentials@v6\n"
        for name, (job, _, _) in TARGETS.items():
            self.bad(name, lambda t: edit_job(t, name, lambda j: j.replace("    steps:\n", "    steps:\n" + step, 1)),
                     "configure-aws-credentials")

    def test_negative_token_at_each_level(self):
        for name in TARGETS:
            self.bad(name, lambda t: t.replace("ATMOS_PROFILE: github\n",
                                               "GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}\n          ATMOS_PROFILE: github\n", 1),
                     "step-level token")
            self.bad(name, lambda t: edit_job(t, name, lambda j: j.replace(
                "\n    steps:\n", "\n    env:\n      ATMOS_CI_GITHUB_TOKEN: x\n    steps:\n", 1)), "job-level token")
            self.bad(name, lambda t: t.replace("\njobs:\n", "\nenv:\n  GITHUB_TOKEN: ${{ github.token }}\n\njobs:\n", 1),
                     "workflow-level token")

    def test_negative_job_or_workflow_level_identity(self):
        for name in TARGETS:
            self.bad(name, lambda t: edit_job(t, name, lambda j: j.replace(
                "\n    steps:\n", "\n    env:\n      ATMOS_IDENTITY: ci\n    steps:\n", 1)), "job-level auth env")
            self.bad(name, lambda t: t.replace("\njobs:\n", "\nenv:\n  ATMOS_PROFILE: github\n\njobs:\n", 1),
                     "workflow-level auth env")

    def test_negative_arn_not_from_the_derive_step(self):
        for name in TARGETS:
            for bad in ("${{ github.event.pull_request.title }}", "${{ inputs.role }}", "arn:aws:iam::1:role/x"):
                self.bad(name, lambda t: t.replace(f"ATMOS_CI_ROLE_ARN: {ARN}", f"ATMOS_CI_ROLE_ARN: {bad}", 1),
                         "ATMOS_CI_ROLE_ARN is not")

    def test_negative_region_from_a_pr_controlled_value(self):
        for name in TARGETS:
            self.bad(name, lambda t: t.replace(f"ATMOS_CI_REGION: {REGION}",
                                               "ATMOS_CI_REGION: ${{ github.head_ref }}", 1), "ATMOS_CI_REGION is not")

    def test_negative_missing_auth_key_or_wrong_value(self):
        for name in TARGETS:
            self.bad(name, lambda t: t.replace("          ATMOS_IDENTITY: ci\n", "", 1), "lacks")
            self.bad(name, lambda t: t.replace("ATMOS_PROFILE: github", "ATMOS_PROFILE: fnx-sso", 1), "ATMOS_PROFILE: github")

    def test_negative_extra_key_on_the_pr_plan_step(self):
        self.bad("terraform-ci.yml", lambda t: t.replace("TFSTATE_ACCESS: read\n          ATMOS_PROFILE",
                                                         "TFSTATE_ACCESS: read\n          EXTRA: 1\n          ATMOS_PROFILE", 1),
                 "step env keys differ")

    def test_negative_kind_mismatch_and_missing_id_token(self):
        for name in TARGETS:
            self.bad(name, lambda t: edit_job(t, name, lambda j: j.replace("ci-apply-role-arn.py --kind plan", "ci-apply-role-arn.py --kind apply", 1)),
                     "--kind plan")
            self.bad(name, lambda t: edit_job(t, name, lambda j: j.replace("id-token: write", "id-token: none", 1)),
                     "id-token")

    def test_negative_identity_on_the_derive_step(self):
        self.bad("terraform-ci.yml", lambda t: t.replace(
            "          STACK: ${{ matrix.stack }}\n        run: python3 workflows/scripts/common/ci-apply-role-arn.py",
            "          STACK: ${{ matrix.stack }}\n          ATMOS_IDENTITY: ci\n"
            "        run: python3 workflows/scripts/common/ci-apply-role-arn.py", 1), "does not run atmos")

    def test_dr_workflow_passes_the_identity_flag(self):
        self.bad("disaster-recovery.yml", lambda t: t.replace(' --identity "$ATMOS_IDENTITY"', "", 1), "--identity")


if __name__ == "__main__":
    unittest.main()
