terraform {
  required_version = ">= 1.9"

  required_providers {
    wireguard = {
      source  = "ojford/wireguard"
      version = "~> 0.4"
    }
  }
}
