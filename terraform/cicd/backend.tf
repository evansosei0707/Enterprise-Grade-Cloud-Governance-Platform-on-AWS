# CI/CD Backend Configuration
terraform {
  backend "s3" {
    bucket         = "cloud-governance-terraform-state-257016720202"
    key            = "cicd/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "cloud-governance-terraform-locks"
    encrypt        = true
  }
}
