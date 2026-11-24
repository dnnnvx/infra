# Buckets and their clients on RustFS (apps/rustfs). Each client is a plain user with one
# bucket-scoped policy; its keys are an output, handed to the cluster as a Secret by module "k8s".

locals {
  read = ["s3:GetObject", "s3:GetBucketLocation", "s3:ListBucket"]
  write = concat(local.read, [
    "s3:PutObject",
    "s3:AbortMultipartUpload",
    "s3:ListBucketMultipartUploads",
    "s3:ListMultipartUploadParts",
  ])

  # client => bucket + actions
  clients = {
    # nix-build substitutes from the cache
    nix-cache-read = { bucket = rustfs_bucket.nix_cache.name, actions = local.read }
    # nix-build's push-cache step uploads (and signs) what the build produced
    nix-cache-write = { bucket = rustfs_bucket.nix_cache.name, actions = local.write }
  }
}

# Nix binary cache for CI (docs/cicd.md). Disposable: anything missing is rebuilt.
resource "rustfs_bucket" "nix_cache" {
  name          = "nix-cache"
  force_destroy = true
}

resource "rustfs_bucket_lifecycle_configuration" "nix_cache" {
  bucket = rustfs_bucket.nix_cache.name
  rule = [
    {
      # Paths still in use are pushed again by the next build that has to rebuild them
      id     = "expire"
      status = "Enabled"
      expiration = {
        days = var.nix_cache_expiration_days
      }
      abort_incomplete_multipart_upload = {
        days_after_initiation = 1
      }
    },
  ]
}

resource "rustfs_policy" "clients" {
  for_each = local.clients

  name = each.key
  statement = [
    {
      effect   = "Allow"
      action   = each.value.actions
      resource = ["arn:aws:s3:::${each.value.bucket}", "arn:aws:s3:::${each.value.bucket}/*"]
    },
  ]
}

resource "random_password" "clients" {
  for_each = local.clients

  length  = 40
  special = false
}

resource "rustfs_user" "clients" {
  for_each = local.clients

  access_key = each.key
  secret_key = random_password.clients[each.key].result
  status     = "enabled"

  policy = rustfs_policy.clients[each.key].name
}
