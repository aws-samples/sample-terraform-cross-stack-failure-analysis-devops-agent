terraform {
  # Fill in your bucket / dynamodb_table before `terraform init`.
  # Example values shown — replace with your own.
  backend "s3" {
    bucket         = "REPLACE-ME-tf-state-bucket"
    key            = "networking/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "cross-stack-demo-tf-locks"
    encrypt        = true
  }
}
