terraform {
  backend "s3" {
    bucket  = "gotit-terraform-state"
    region  = "ap-southeast-1"
    encrypt = true
  }
}