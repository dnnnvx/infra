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

# Clone keys for private CI repos: GitHub gets the public half (read-only deploy key), the cluster the
# private one through flux-substitutions (infrastructure/configs/tekton/git-ssh-secret.yaml)
resource "tls_private_key" "ci_clone" {
  for_each  = toset(["marcods"])
  algorithm = "ED25519"
}

module "github" {
  source = "../modules/github"

  ci_deploy_keys = { for repo, key in tls_private_key.ci_clone : repo => key.public_key_openssh }

  repositories = {
    # CI-built (ci_webhook: Trigger in apps/<project>/ci.yaml or infrastructure/configs/tekton/triggers/)
    infra = {
      visibility  = "public"
      description = "Homelab cluster as code"
      topics      = ["fluxcd", "gitops", "homelab", "iac", "kubernetes", "talos", "tofu"]
      ci_webhook  = true
    }
    casasulgorgo = {
      visibility   = "public"
      description  = "Local nature, season by season"
      homepage_url = "https://casasulgorgo.net"
      has_wiki     = true
      ci_webhook   = true
    }
    kubbot = {
      visibility  = "public"
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
      visibility  = "public"
      description = "Macbook and Raspberry Pis setup"
      has_wiki    = true
      topics      = ["dotfiles", "home-manager", "nix"]
    }
    radicle-images = {
      visibility   = "public"
      description  = "Radicle container images"
      homepage_url = "https://github.com/dnnnvx?tab=packages&repo_name=radicle-images"
      has_wiki     = true
      topics       = ["container", "containerization", "containers", "docker", "docker-compose", "docker-image", "dockerfile", "kubernetes", "radicle"]
    }
    dnnnvx = {
      visibility  = "public"
      description = "dnnnvx meets dnnnvx"
      has_wiki    = true
    }
    tangled-interceptor = {
      visibility  = "public"
      description = "Tekton interceptor that verifies Tangled webhook signatures."
      has_wiki    = true
      topics      = ["cicd", "interceptor", "tangled", "tekton", "webhook"]
    }
    dotfiles = {
      visibility  = "public"
      description = "dot dot :lizard:"
      has_wiki    = true
      topics      = ["configuration", "dotfiles"]
    }
    solzk = {
      visibility  = "public"
      description = "Solidity / ZK circuits / Test & Exercises"
      has_wiki    = true
      archived    = true
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
    # Public half of infrastructure/configs/flux/signing-key.yaml (SOPS)
    signing_key_pub = file("${path.module}/flux-signing-key.asc")
  }
}
