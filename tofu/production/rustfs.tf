# RustFS (apps/rustfs) root credentials. Alphanumeric: they end up in env vars and S3 signatures.
resource "random_password" "rustfs_access_key" {
  length  = 20
  special = false
}

resource "random_password" "rustfs_secret_key" {
  length  = 40
  special = false
}

# Not reachable until Flux has deployed apps/rustfs: bootstrap with `-exclude=module.rustfs` first
provider "rustfs" {
  endpoint   = var.rustfs_endpoint
  access_key = random_password.rustfs_access_key.result
  secret_key = random_password.rustfs_secret_key.result
}

module "rustfs" {
  source = "../modules/rustfs"
}
