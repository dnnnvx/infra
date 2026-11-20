provider "github" {
  owner = "dnnnvx"
  token = var.github_token
}

locals {
  # Pinned rather than ssh-keyscan'd on every plan (tofu-controller runs this in-cluster).
  # Re-check after a host key rotation: https://api.github.com/meta (ssh_keys).
  git_known_hosts = <<-EOT
    github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl
  EOT
}

# Webhook HMAC secrets: GitHub gets them here, the cluster through flux-substitutions
# (infrastructure/configs/tekton/triggers/github-webhook-secret.yaml, infrastructure/configs/flux/receiver-token.yaml)
resource "random_password" "github_webhook" {
  length  = 48
  special = false
}

resource "random_password" "flux_receiver" {
  length  = 48
  special = false
}

module "github" {
  source = "../modules/github"

  repositories = {
    # CI-built (ci_webhook: Trigger in apps/<project>/ci.yaml or infrastructure/configs/tekton/triggers/)
    infra = {
      description = "Homelab cluster as code"
      topics      = ["fluxcd", "gitops", "homelab", "iac", "kubernetes", "talos", "tofu"]
      ci_webhook  = true
    }
    casasulgorgo = {
      description  = "Local nature, season by season"
      homepage_url = "https://casasulgorgo.net"
      has_wiki     = true
      ci_webhook   = true
    }
    kubbot = {
      description = "A Matrix bot for the homelab (flux, kyverno, tekton, k8s)"
      has_wiki    = true
      topics      = ["alerting", "alerts", "bot", "chat", "ci", "cicd", "fluxcd", "kyverno", "matrix", "tekton"]
      ci_webhook  = true
    }
    marcods = {
      description = "Portfolio / website"
      visibility  = "private"
      ci_webhook  = true
    }
    # settings only
    nix = {
      description = "Macbook and Raspberry Pis setup"
      has_wiki    = true
      topics      = ["dotfiles", "home-manager", "nix"]
    }
    radicle-images = {
      description  = "Radicle container images"
      homepage_url = "https://github.com/dnnnvx?tab=packages&repo_name=radicle-images"
      has_wiki     = true
      topics       = ["container", "containerization", "containers", "docker", "docker-compose", "docker-image", "dockerfile", "kubernetes", "radicle"]
    }
    dnnnvx = {
      description = "dnnnvx meets dnnnvx"
      has_wiki    = true
    }
    tangled-interceptor = {
      description = "Tekton interceptor that verifies Tangled webhook signatures."
      has_wiki    = true
      topics      = ["cicd", "interceptor", "tangled", "tekton", "webhook"]
    }
    dotfiles = {
      description = "dot dot :lizard:"
      has_wiki    = true
      topics      = ["configuration", "dotfiles"]
    }
    solzk = {
      description = "Solidity / ZK circuits / Test & Exercises"
      has_wiki    = true
    }
  }

  ci_webhook = {
    url    = "https://ci.casasulgorgo.net/"
    secret = random_password.github_webhook.result
  }

  flux = {
    repository     = "infra"
    deploy_key_pub = var.flux_deploy_key_pub
    # Flux's path is /hook/sha256(token + name + namespace) of the Receiver (infrastructure/configs/flux/receiver.yaml)
    receiver_url    = "https://flux.casasulgorgo.net/hook/${sha256("${random_password.flux_receiver.result}github-pushflux-system")}"
    receiver_secret = random_password.flux_receiver.result
  }
}
