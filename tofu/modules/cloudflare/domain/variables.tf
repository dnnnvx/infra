variable "zone_name" {
  description = "Cloudflare zone (domain) to manage"
  type        = string
}

variable "cname_subdomains" {
  description = "Subdomains to create as CNAMEs pointing to the apex (e.g. [\"ha\"])"
  type        = list(string)
  default     = []
}

variable "local_gateway_ip" {
  description = "Private IP of the LAN-only Gateway; creates a DNS-only *.local A record pointing to it. Leave null to skip."
  type        = string
  default     = null
}

variable "atproto_did" {
  description = "AT Protocol DID for handle verification via _atproto TXT record (e.g. did:plc:xxxx). Leave null to skip."
  type        = string
  default     = null
}
