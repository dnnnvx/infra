resource "github_repository" "repos" {
  # checkov:skip=CKV_GIT_1:Public on purpose (open-source homelab, dotfiles, portfolio); visibility is set per repo
  # checkov:skip=CKV2_GIT_1:Public repos get github_branch_protection.main below; private ones can't on GitHub Free
  for_each = var.repositories

  name         = each.key
  description  = each.value.description
  visibility   = each.value.visibility
  homepage_url = each.value.homepage_url
  topics       = each.value.topics

  has_wiki     = each.value.has_wiki
  has_issues   = true
  has_projects = true

  # Dependabot alerts
  vulnerability_alerts = true

  # a `tofu destroy` (or dropping a repo from the map) archives instead of deleting
  archive_on_destroy = true

  lifecycle {
    prevent_destroy = true
  }
}

# Guards history, not workflow: no force-pushes or deletion of main, while direct pushes (and Flux's
# image automation commits on infra) keep working. Public repos only: GitHub Free doesn't offer branch
# protection on private ones.
resource "github_branch_protection" "main" {
  # checkov:skip=CKV_GIT_5:Solo repos: required approvals would block direct pushes and Flux image automation
  # checkov:skip=CKV_GIT_6:Flux image automation commits unsigned; required signatures would block it
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
