resource "github_repository" "repos" {
  # checkov:skip=CKV_GIT_1:Public on purpose (open-source homelab, dotfiles, portfolio); visibility is set per repo
  # checkov:skip=CKV2_GIT_1:Public repos get github_branch_protection.main below; private ones can't on GitHub Free
  # checkov:skip=CKV_GIT_3:Vulnerability alerts are enabled by github_repository_vulnerability_alerts.repos (the attribute is deprecated)
  for_each = var.repositories

  name         = each.key
  description  = each.value.description
  visibility   = each.value.visibility
  homepage_url = each.value.homepage_url
  topics       = each.value.topics

  has_wiki     = each.value.has_wiki
  has_issues   = true
  has_projects = true

  # a `tofu destroy` (or dropping a repo from the map) archives instead of deleting
  archive_on_destroy = true

  lifecycle {
    prevent_destroy = true
  }
}

# Dependabot alerts, then automatic PRs for vulnerable dependencies (security updates need alerts on)
resource "github_repository_vulnerability_alerts" "repos" {
  for_each = var.repositories

  repository = github_repository.repos[each.key].name
  enabled    = true
}

resource "github_repository_dependabot_security_updates" "repos" {
  for_each = var.repositories

  repository = github_repository_vulnerability_alerts.repos[each.key].repository
  enabled    = true
}

# Guards history, not workflow: no force-pushes or deletion of main, while direct pushes (and Flux's
# image automation commits on infra) keep working. Public repos only: GitHub Free doesn't offer branch
# protection on private ones.
resource "github_branch_protection" "main" {
  # checkov:skip=CKV_GIT_5:Solo repos: required approvals would block direct pushes and Flux image automation
  # checkov:skip=CKV_GIT_6:Not required yet: Flux now signs (github_user_gpg_key.flux), but other machines may push unsigned
  for_each = { for name, repo in var.repositories : name => repo if repo.visibility == "public" }

  repository_id       = github_repository.repos[each.key].node_id
  pattern             = "main"
  enforce_admins      = true
  allows_force_pushes = false
  allows_deletions    = false
}

resource "github_repository_webhook" "ci" {
  for_each = { for name, repo in var.repositories : name => repo if repo.ci_webhook }

  repository = github_repository.repos[each.key].name
  events     = ["push"]
  active     = true

  configuration {
    url          = var.ci_webhook.url
    content_type = "json"
    secret       = var.ci_webhook.secret
    insecure_ssl = false
  }
}

resource "github_repository_deploy_key" "flux" {
  repository = github_repository.repos[var.flux.repository].name
  title      = "flux-homelab"
  key        = var.flux.deploy_key_pub
  read_only  = false
}

resource "github_repository_webhook" "flux_receiver" {
  repository = github_repository.repos[var.flux.repository].name
  events     = ["push"]
  active     = true

  configuration {
    url          = var.flux.receiver_url
    content_type = "json"
    secret       = var.flux.receiver_secret
    insecure_ssl = false
  }
}

# Lets GitHub verify image automation's signed commits (the key's identity is the account's noreply address)
resource "github_user_gpg_key" "flux" {
  armored_public_key = var.flux.signing_key_pub
}

# Read-only keys Tekton's git-clone uses for private CI repos (private halves: Secret tekton-ci/git-ssh)
resource "github_repository_deploy_key" "ci" {
  for_each = var.ci_deploy_keys

  repository = github_repository.repos[each.key].name
  title      = "tekton-ci"
  key        = each.value
  read_only  = true
}
