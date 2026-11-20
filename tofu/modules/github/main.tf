resource "github_repository" "repos" {
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
