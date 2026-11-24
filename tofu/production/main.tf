terraform {
  required_version = "1.13.2"

  backend "s3" {
    bucket                      = "tofu-state"
    encrypt                     = true
    endpoint                    = "https://997f91bd76e7456df317ac9ac3fff92b.r2.cloudflarestorage.com"
    key                         = "homelab/terraform.tfstate"
    region                      = "auto"
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_s3_checksum            = true
    use_path_style              = true
    # access_key                  = "<redacted>"
    # secret_key                  = "<redacted>"
  }

  encryption {
    key_provider "pbkdf2" "this" {
      passphrase = var.passphrase
    }

    method "aes_gcm" "this" {
      keys = key_provider.pbkdf2.this
    }

    state {
      method = method.aes_gcm.this
    }
  }

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.0"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5"
    }
    github = {
      source  = "integrations/github"
      version = "~> 6.13"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.4"
    }
    rustfs = {
      source  = "caberdo/rustfs"
      version = "0.10.0"
    }
  }
}
