# RustFS (apps/rustfs) root credentials. Alphanumeric: they end up in env vars and S3 signatures.
resource "random_password" "rustfs_access_key" {
  length  = 20
  special = false
}

resource "random_password" "rustfs_secret_key" {
  length  = 40
  special = false
}
