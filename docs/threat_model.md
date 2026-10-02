# Threat model

DRAFT, 2026-10-02: derived from the IAM and trust-policy code and the comments in it. Review and
correct before merge.

## What this repo protects

This repo decides what every other Glunk Works repo's CI may do in one AWS account. That
account also holds the bug-bounty findings archive (third-party vulnerability data), the shared
OpenTofu state bucket and lock table, and the state and findings KMS keys. Every `.tf` change is
a behavior change, applied by hand with `tofu apply`.

## Trust boundaries

1. **GitHub OIDC token to AWS role.** Trust is the `sub` claim, matched with `StringEquals`.
   Anything that can change what subject a repo presents (a repo transfer, a renamed repo, a new
   Environment) changes who can assume a role, with no diff in this repo.
2. **PR-triggered code to credentials.** Workflow edits in a PR run in that PR. Only the
   read-only plan role is assumable from `:pull_request`.
3. **CI role to IAM.** Roles that can create roles are a path to account admin unless bounded.
4. **Plan role to state.** Plan roles read state, and state can hold secrets.
5. **Local apply.** Applied by a human with AWS SSO credentials. Nothing is applied by CI here.

## Threats and current controls

| Threat | Control | Residual |
|---|---|---|
| PR gains apply-capable credentials | Separate read-only plan role, `:pull_request` only | None known |
| Wildcard in a trust subject globs past the principal | `StringEquals`, no wildcards rendered | `extra_oidc_subjects` is unvalidated input |
| Transferred or renamed repo makes a dormant role assumable | Dormant roles removed (GB-D4) | Any entry in `var.projects` for a repo not yet in the org |
| CI role escalates via IAM | Permissions boundary, role-path scope, `iam:PermissionsBoundary` condition (bedrock-rag only) | `UpdateAssumeRolePolicy` can still rewrite trust; tri-loop-dev and resume-optimizer still hold `iam:*Role*` on `*` |
| PR-time or scanner role reads findings | Explicit Deny on findings bucket and key | The bounty-infra plan role's own inline Deny covers `s3:` only (tracked in #6) |
| Scanner VM tampers with RoE data | Chained role, Deny on `PutObject` to `roe/*`, per-scan session policy | Depends on the session policy staying in the consuming repo |
| Plan role reads plaintext state | `encryption {}` planned per consumer (GB-D7) | Not wired for any project yet |
| Cross-repo literal drift (collection, budget, role path) | Documented in `project_policies.tf` | Surfaces as AccessDenied at apply, not at plan |

## Out of scope

AWS account-level controls (SCPs, CloudTrail, break-glass), the contents of consuming repos, and
GitHub organization settings except where they change an OIDC subject.
