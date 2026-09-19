# AI Integration Plan

Status: **proposed** · Target: Atmos ≥ 1.229.0 (AI and MCP are still flagged *experimental*, so pin the Atmos version) · Sources: [atmos.tools/ai](https://atmos.tools/ai), [AI config](https://atmos.tools/cli/configuration/ai), [MCP config](https://atmos.tools/cli/configuration/mcp), [MCP server](https://atmos.tools/ai/mcp-server), the `atmos-ai` agent skill.

## Goal

Atmos documents two separate integration patterns. This plan adopts both, in stages, starting read-only:

| Pattern | What it means here | Main commands |
|---|---|---|
| **AI uses Atmos** | Claude Code, Codex, Cursor and similar assistants query this repo's stacks through the Atmos MCP server and apply Atmos-native patterns via Atmos agent skills | `atmos mcp start`, `atmos mcp export`, `atmos ai skill install` |
| **Atmos uses AI** | Atmos calls a model to explain plans, answer questions about the stacks, and summarize CI output | `atmos ai ask/chat/exec`, `atmos terraform plan … --ai` |

There are three layers of context, each with its own MCP server:

| Layer | Server | Answers | Phase |
|---|---|---|---|
| Defined | `atmos` (built-in) | What is in the stacks/components | 1 |
| Deployed | `awslabs/*` AWS MCP servers | What is live in AWS right now | 2 |
| Over time | Atmos Pro MCP (optional, paid) | Drift, deployment history, who changed what | 4 |

## Current state (2026-09-19)

- `.mcp.json` contains 4 generic servers (fetch, memory, sequential-thinking). None of them know about Atmos or AWS, and all run unpinned `npx …@latest`, which is a supply-chain risk.
- `.claude/` holds 17 generic agent personas and around 20 commands. They predate the Atmos agent skills and overlap with them.
- No `ai:`, `mcp:` or `auth:` sections exist in `atmos.yaml`. AWS access comes from ambient `aws_profile` and `role_arn`.
- **Blocker, being resolved by the modernization branch:** `atmos validate stacks` failed on `master`. AI tooling built on stacks that don't resolve would only produce confident nonsense.

## Phase 0: Prerequisites (must finish before any AI work)

1. Merge the Atmos/Terraform modernization so that `atmos validate stacks` and `atmos describe component` pass for every stack.
2. **Atmos Auth**: add `auth.providers` (IAM Identity Center/SSO) and a `readonly` identity (`ReadOnlyAccess` permission set, `default: true`) per account (dev/staging/prod). MCP servers that need AWS credentials use `identity: readonly`, which gives them isolated, short-lived credentials instead of whatever `AWS_PROFILE` happens to be set. *Needs from you: SSO start URL, account IDs, permission-set names.*
3. Pin Atmos with the toolchain (`dependencies.tools`), and pin `uv`/`node` the same way so `uvx`/`npx` servers resolve identically for everyone.
4. Add `ATMOS.md` (the project instructions file read by `ai.instructions`). It is short: naming conventions, stack names, "never apply", "never touch prod without approval", and where state and secrets live.
5. Gitignore `.atmos/sessions/`.

Exit criteria: `atmos auth login readonly` works for every account, `atmos validate stacks` is green, and `ATMOS.md` is reviewed.

## Phase 1: AI uses Atmos (developer workstations, read-only)

```yaml
# atmos.yaml (or atmos.d/ai.yaml)
mcp:
  enabled: true
  routing:
    enabled: true          # start only the servers relevant to a question
  servers:
    atmos:
      command: atmos
      args: ["mcp", "start"]
      description: "Stacks, components, validation, affected"
    aws-docs:
      command: uvx
      args: ["awslabs.aws-documentation-mcp-server@<pinned>"]
      description: "AWS documentation (no auth)"

ai:
  enabled: true
  tools:
    enabled: true
    require_confirmation: true
    blocked:
      - write_component_file   # Phase 1 is read-only
      - write_stack_file
  instructions:
    enabled: true
    file: ATMOS.md
```

Steps:
1. Install the Atmos agent skills into the repo: `atmos ai skill install` (bundled, offline). This writes `.claude/skills/`, `.github/skills/` and `.gemini/skills/`. Commit them, and run `atmos ai skill update` after every Atmos upgrade.
2. Generate client configs from the single source of truth: `atmos mcp export` (writes `.mcp.json` for Claude Code), plus `--output .cursor/mcp.json` and `--output ~/.codex/config.toml` as needed. **Replace** the current `.mcp.json`; don't merge into it. The exported file contains no secrets and is safe to commit.
3. Retire the generic `.claude/agents/*` and `.claude/commands/*` that duplicate skills (terraform-specialist, cloud-architect, network-engineer, `atmos.md`, validate/plan commands). Keep only repo-specific commands that have no skill equivalent.
4. Verify: `atmos mcp list`, `atmos mcp tools atmos`, `atmos mcp test atmos`. Then ask the assistant "which components does fnx-dev-testenv-01 deploy and what depends on vpc?" and check the answer against `atmos describe dependents`.

Exit criteria: every engineer's assistant answers stack questions from live `describe` data. Write tools stay blocked.

## Phase 2: Deployed context (AWS MCP servers through Atmos Auth)

Add pinned `awslabs` servers, all with `identity: readonly`:

| Server | Why here |
|---|---|
| `aws-iam` | Review the IAM roles/policies the `iam` and `eks` components create |
| `aws-cloudtrail` | "Who changed this SG?" during drift/incident triage |
| `aws-pricing`, `aws-billing` | Cost questions next to `cost-optimization` component changes |
| `aws-security` (Well-Architected) | Pair with the `security-monitoring` component and the `atmos-aws-security` skill |

Rules: never use `aws-api` with write access, keep per-domain identities (`billing-auditor`, `security-audit`) only where `ReadOnlyAccess` isn't enough, and test each server with `atmos mcp test <name>` before it goes into `atmos mcp export`.

## Phase 3: Atmos uses AI (local, then CI)

**Local:** use a CLI provider first so developers reuse their existing subscription and no API keys get distributed:

```yaml
ai:
  default_provider: claude-code
  providers:
    claude-code:
      max_turns: 10
    anthropic:                     # fallback / CI
      model: <current Claude model id>
      api_key: !env ANTHROPIC_API_KEY
  send_context: false              # opt-in per command; stacks can contain account IDs
  prompt_on_send: true
  max_tool_iterations: 25
  timeout_seconds: 120
```

Workflows to adopt: `atmos terraform plan <c> -s <stack> --ai --skill atmos-terraform` for plan review, `atmos ai ask "…"` for ad-hoc questions, and `atmos validate stacks --ai` to explain validation failures.

**CI (pull requests only, never apply):**
- Add a step to the native `terraform-ci.yml` plan job that runs `atmos terraform plan … --ai --skill atmos-terraform` and writes the summary to the step summary / PR comment.
- Use an API provider with a repo secret. If data residency matters, **Amazon Bedrock in eu-west-2** keeps prompts inside the AWS account and authenticates via the existing GitHub OIDC role, so no long-lived API key is needed.
- Guardrails: the job runs with `contents: read`, `pull-requests: write` and a readonly OIDC role only; write tools are blocked; `terraform show -json` output is never sent raw (plans can contain secrets, so the AI summarizes the human-readable plan, where sensitive values are already masked); the step is non-blocking (`continue-on-error`) for the first month.

## Phase 4: Optional extensions

- **Atmos Pro MCP** (`claude mcp add --transport http atmos-pro https://atmos-pro.com/mcp`) for drift history, deployment audit and flapping detection. Only worth it if you adopt Atmos Pro drift detection, which is the documented upgrade path for the scheduled drift workflow.
- `atmos aws compliance report` with AI summaries (CIS/SOC2) on a schedule.
- Unblock `write_stack_file` only for scaffolding in dev stacks, behind `require_confirmation: true`, once Phase 1–3 have run cleanly.

## Governance

| Risk | Control |
|---|---|
| Secret/PII egress to a model provider | `send_context: false` by default, sensitive TF outputs masked, Bedrock option for residency, `.atmos/sessions` gitignored |
| AI-initiated changes | Write tools blocked; apply always requires human approval via the existing CD approval gates; readonly identities only |
| Supply chain (MCP servers) | Every `uvx`/`npx` package pinned to a reviewed version and bumped by PR; no `@latest` |
| Experimental feature churn | Atmos version pinned; re-run `atmos ai skill update` and `atmos mcp export` on upgrade |
| Cost | CLI providers locally; CI limited to PRs touching `components/` or `stacks/`, with `max_tool_iterations`/timeouts |

## Decisions needed from you

1. **Model provider:** CLI subscription (Claude Code) locally plus Anthropic API or Bedrock in CI? Bedrock is recommended if prompts must stay in AWS.
2. **Auth details** for Phase 0: SSO start URL, account IDs, permission sets.
3. **Atmos Pro:** adopt it (drift + Pro MCP) or keep drift detection as native scheduled plans?
4. Which existing `.claude/agents` and `.claude/commands` to keep.

## Rollout summary

| Phase | Scope | Reversible by |
|---|---|---|
| 0 | Auth, pins, `ATMOS.md` | Reverting the config PR |
| 1 | MCP + skills, read-only | Removing `mcp:`/`ai:` sections and the regenerated `.mcp.json` |
| 2 | AWS MCP servers | Dropping the servers from `mcp.servers` and re-exporting |
| 3 | `--ai` locally, then non-blocking CI step | Deleting the CI step |
| 4 | Pro MCP, compliance summaries, scoped write tools | Per-feature toggle |
