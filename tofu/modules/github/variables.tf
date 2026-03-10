variable "owner" {
  description = "GitHub user or organization that owns the repository"
  type        = string
}

variable "repository" {
  description = "Repository name (without owner prefix)"
  type        = string
}

variable "deploy_key_pub" {
  description = "SSH public key to register as a read-only deploy key on the repository"
  type        = string
}
