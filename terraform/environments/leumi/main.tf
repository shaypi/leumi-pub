provider "aws" {
  region = var.region
}

data "aws_region" "current" {}

module "task" {

  source = "../../modules/task"

  project = var.project
  env = var.env
}


