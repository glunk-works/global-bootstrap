# Decision log

DRAFT, 2026-10-02: reconstructed from commit messages, with PR numbers as the source. IDs are
assigned in the order the PRs merged. Review before merge. New entries append; never renumber.

## GB-D1: PR-time plan runs on a separate read-only role (#1)

Widening the apply role's subject to accept `pull_request` would hand apply-capable credentials
to any PR, because workflow edits in a PR take effect for its own run. Each opted-in project
gets a second, read-only role assumable only from `:pull_request`, with an explicit Deny on the
findings bucket.

## GB-D2: Environment subjects are added to the apply role, not substituted (#1)

A job under a GitHub Environment presents `...:environment:<name>`. `extra_oidc_subjects` appends
it to the branch subject, since sibling workflows on the same role still present the branch
subject. Narrowing to the environment subject alone is a possible follow-up.

## GB-D3: Scanner VM credential is a chained, narrower role (#3)

bounty-scanner-s3-writer is reached by `sts:AssumeRole` from the existing bounty-infra identity,
not by a new OIDC subject. It has an explicit Deny on `PutObject` to `roe/*`.

## GB-D4: Remove the dormant bedrock-serverless-rag role until its identity sprint (#5)

The old grant had `iam:CreateRole` and `iam:PassRole` on `*` and became assumable the moment the
repo transferred into the org. It returned in #11 with a permissions boundary, an IAM role-path
scope and a findings Deny covering `kms:` as well as `s3:`.

## GB-D5: Per-project OIDC subject prefix (BR-D27) (#8)

`oidc_subject_prefix` overrides the computed `repo:<org>/<repo>` for ID-qualified subjects. The
default leaves every existing rendered subject byte-identical.

## GB-D6: Trust-policy subject uses StringEquals, never StringLike (F2) (#9)

In IAM StringLike, `*` matches `:`, so a wildcard in `extra_oidc_subjects` would glob past the
federated principal. Every rendered subject is exact.

## GB-D7: State encryption is client-side, key lives beside the bucket (BR-D22) (#11)

The mechanism is OpenTofu's native `encryption {}` block, not SSE-KMS, because SSE does not
protect state from a role that can `GetObject` it, and a plan role is assumable from any PR.
Flipping the bucket to SSE-KMS would also break every sibling plan. The key is created in this
repo so it outlives any project's destroy cycles. The plan role holds `Decrypt` and
`DescribeKey` only, not `GenerateDataKey`.
