terraform {
  backend "s3" {
    bucket       = "todo-api-terraform-state-arpitsaini7979"
    key          = "todo-api/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
