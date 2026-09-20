terraform {
  backend "s3" {
    bucket       = "todo-api-tfstate-475369996910"
    key          = "todo-api/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
