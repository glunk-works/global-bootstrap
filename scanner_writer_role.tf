# ==============================================================================
# BOUNTY-SCANNER S3 WRITER ROLE
# ==============================================================================
# bounty-infra's SE sprint (BI-D5, sprints/SE_egress_migration): the per-scan
# Vultr VM's ONLY credential. run-scan.yml assumes this via ROLE CHAINING from
# its existing github-actions-bounty-infra identity -- not a new OIDC subject,
# not a widened trust condition -- then narrows it further with an inline
# session policy scoped to that one scan's domain/program/run_id before the
# credential ever reaches the VM (via cloud-init user-data). This role's own
# permissions are only the OUTER bound that session policy can narrow, never
# widen, so they stay broader than any single scan's actual need.
#
# Role chaining (assuming a role using credentials from ANOTHER assumed role,
# rather than a fresh OIDC handshake) hard-caps the session at 1 hour
# regardless of max_session_duration -- fine, bounty-infra's default scan
# timeout is 1800s (30 min) plus a margin, well under the cap.

resource "aws_iam_role" "bounty_scanner_s3_writer" {
  name        = "bounty-scanner-s3-writer"
  description = "Chain-only role for bounty-infra's per-scan Vultr VM S3 writes -- never assumed directly via OIDC, only by role-chaining from github-actions-bounty-infra"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowChainFromBountyInfraPipeline"
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.github_actions_role["bounty-infra"].arn
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "bounty_scanner_s3_writer_policy" {
  name = "bounty-scanner-s3-writer-policy"
  role = aws_iam_role.bounty_scanner_s3_writer.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # The launcher (run-scan.yml) needs to read the RoE scope object once
        # per scan, and both write AND poll-read its own status sentinel.
        # Findings themselves are never read back -- this role is write-only
        # for scan output.
        Sid    = "AllowReadRoEAndStatusSentinel"
        Effect = "Allow"
        Action = "s3:GetObject"
        Resource = [
          "${aws_s3_bucket.findings_bucket.arn}/roe/*",
          "${aws_s3_bucket.findings_bucket.arn}/runs/*"
        ]
      },
      {
        # Findings land under an unpredictable <domain>/<timestamp>/* prefix
        # (scanner.py, bounty-infra), so this can't be scoped tighter at the
        # role level -- the per-scan session policy narrows it to that scan's
        # own domain prefix at assume-role time.
        Sid      = "AllowWriteFindingsAndStatusSentinel"
        Effect   = "Allow"
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.findings_bucket.arn}/*"
      },
      {
        # Belt and braces (mirrors plan_roles.tf's DenyBountyFindingsDataAccess
        # pattern): the broad PutObject grant above exists only because
        # findings paths are unpredictable, but this role must never be able
        # to tamper with RoE authorization data -- even if a future edit
        # widens the Allow above, this Deny still wins.
        Sid      = "DenyWritingRoE"
        Effect   = "Deny"
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.findings_bucket.arn}/roe/*"
      },
      {
        Sid      = "AllowKMSForFindings"
        Effect   = "Allow"
        Action   = ["kms:GenerateDataKey*", "kms:Decrypt"]
        Resource = aws_kms_key.findings_key.arn
      }
    ]
  })
}
