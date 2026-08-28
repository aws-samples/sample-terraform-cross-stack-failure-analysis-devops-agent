terraform {
  backend "s3" {
    bucket         = "REPLACE-ME-tf-state-bucket"
    key            = "compute/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "cross-stack-demo-tf-locks"
    encrypt        = true
  }
}
