variable "repositories" {
  description = "Repositories under the provider's owner, keyed by name. Each gets the CI push webhook."
  type = map(object({
    description  = string
    visibility   = optional(string, "public")
    homepage_url = optional(string)
    has_wiki     = optional(bool, false)
    topics       = optional(list(string), [])
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
  description = "Repository Flux syncs from: its deploy key (read-write, image automation pushes to main) and the push webhook to the Flux Receiver"
  type = object({
    repository      = string
    deploy_key_pub  = string
    receiver_url    = string
    receiver_secret = string
  })
  sensitive = true
}
