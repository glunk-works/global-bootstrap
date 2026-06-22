# Global Bootstrap

This repository contains the foundational OpenTofu infrastructure for the Glunk Works organization. It is designed to be applied once locally to provision the core state-tracking and security resources required by all other projects.

## Architecture

* **AWS S3:** A versioned, encrypted bucket to store OpenTofu `.tfstate` files securely.
* **AWS DynamoDB:** A serverless lock table to prevent concurrent state modifications.
* **AWS IAM & OIDC:** A trust relationship allowing GitHub Actions to assume least-privilege, dynamically generated roles for each repository in the organization.

## Usage Instructions

Because this repository manages the state storage for the entire organization, it does not use a remote backend. It should be executed from your local development environment.

1. Clone the repository.
2. Authenticate your local terminal with AWS. If you are using AWS Identity Center (SSO), refresh your credentials by running:

   ```bash
   aws sso login
   ```

   *(If using standard IAM keys, ensure your profile is active via `aws configure`).*
3. Initialize the OpenTofu directory:

   ```bash
   tofu init
   ```

4. Review the plan and apply, providing the required variables:

   ```bash
   tofu apply -var="bootstrap_bucket_name=glunk-works-tofu-state-12345" -var="github_organization=glunk-works"
   ```

**Important:** The S3 bucket name must be globally unique across all of AWS.

## Adding a New Project

To grant CI/CD permissions to a new repository in the Glunk Works organization:

1. Open `variables.tf`.
2. Add a new block to the `projects` variable map, specifying the repository name and the allowed IAM actions.
3. Run `tofu apply` locally.
4. Copy the generated Role ARN from the output and inject it into your new repository's GitHub Actions workflow.
