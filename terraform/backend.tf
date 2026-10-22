terraform {
  backend "s3" {
    bucket       = "cally-terraform-state-2026-111"
    key          = "voting-app/terraform.tfstate"
    region       = "eu-west-2"
    encrypt      = true
    use_lockfile = true
  }
}
