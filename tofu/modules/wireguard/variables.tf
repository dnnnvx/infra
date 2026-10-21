variable "hostname" {
  description = "Public DNS name clients use as Endpoint (kept pointed at the home IP by DDNS)"
  type        = string
}

variable "peers" {
  description = "Client devices: name → tunnel address (e.g. 10.10.0.2)"
  type        = map(string)
}

variable "address" {
  description = "Server tunnel address, as a prefix covering the peers"
  type        = string
  default     = "10.10.0.1/24"
}

variable "listen_port" {
  description = "UDP port the server listens on (forwarded by the router)"
  type        = number
  default     = 51820
}

variable "routed_ips" {
  description = "Extra addresses clients route through the tunnel (must be local to the endpoint node)"
  type        = list(string)
  default     = []
}
