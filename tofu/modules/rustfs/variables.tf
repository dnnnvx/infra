variable "nix_cache_expiration_days" {
  description = "Days before an object in the nix-cache bucket expires."
  type        = number
  default     = 30
}
