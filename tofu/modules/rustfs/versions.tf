terraform {
  required_version = ">= 1.9"

  required_providers {
    rustfs = {
      source = "caberdo/rustfs"
      # 0.x so it's pinned exactly, bump after reading the changelog
      version = "0.10.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }
  }
}
