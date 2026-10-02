# global-bootstrap roadmap

DRAFT, 2026-10-02: written from the repo's git history. Review and correct before merge.

## Status

| Area | Status | Notes |
|---|---|---|
| State backend (S3 + DynamoDB lock) | Done | Applied locally, state migrated to S3 |
| GitHub OIDC apply roles, one per project | Done | `var.projects` in `variables.tf` |
| Read-only PR-time plan roles | Done | bounty-infra and bedrock-serverless-rag opted in |
| bedrock-serverless-rag identity (S2-T0c) | Merged, not applied | Human apply upstream |
| State encryption key (BR-D22) | Key created, not wired | Consumers add their own `encryption {}` block |
| Repo CI (`tofu fmt` / `validate`) | Not started | No `.github/workflows` yet |
| Branch ruleset on `main` | Not started | Blocks `ruleset.*` in `.ai/project.yml` |
| Over-broad `Resource = "*"` IAM grants | Open | #6, in S1 |

## Sprints

Work is tracked as GitHub milestones; this file does not duplicate their task lists.

- [S1: Pipeline guardrails and IAM hardening](https://github.com/glunk-works/global-bootstrap/milestone/1)
- [S2: bounty-infra findings governance](https://github.com/glunk-works/global-bootstrap/milestone/2)

## Next action

Start S1: add the CI workflow, then the branch ruleset on `main`, then fill `ruleset.*` in
`.ai/project.yml`.
