variable "repositories" {
  description = "Repositories under the provider's owner, keyed by name. ci_webhook: push webhook to the Tekton EventListener (the repo needs a Trigger). archived: read-only."
  type = map(object({
    description  = string
    visibility   = string
    homepage_url = optional(string)
    has_wiki     = optional(bool, false)
    topics       = optional(list(string), [])
    ci_webhook   = optional(bool, false)
    archived     = optional(bool, false)
  }))
}

variable "ci_webhook" {
  description = "Tekton EventListener push webhook (checked by the core github ClusterInterceptor)"
  type = object({
    url    = string
    secret = string
  })
  sensitive = true
}

variable "flux" {
  description = "Repository Flux syncs from: its deploy key (read-write, image automation pushes to main), the push webhook to the Flux Receiver, and the commit signing key (registered on the token owner's account)"
  type = object({
    repository      = string
    deploy_key_pub  = string
    receiver_url    = string
    receiver_secret = string
    # ASCII-armored OpenPGP public key image automation signs commits with
    signing_key_pub = string
  })
  sensitive = true
}

variable "ci_deploy_keys" {
  description = "Read-only deploy keys (OpenSSH public keys) for Tekton to clone private CI repos, keyed by repository name"
  type        = map(string)
  default     = {}
}
