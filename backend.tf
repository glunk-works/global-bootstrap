terraform {
  backend "s3" {
    bucket         = "glunk-works-tofu-state-00042"
    key            = "bootstrap/global-bootstrap.tfstate"
    region         = "us-east-1"
    dynamodb_table = "global-tofu-lock"
    encrypt        = true
  }
}