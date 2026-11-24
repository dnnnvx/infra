output "credentials" {
  description = "S3 credentials per client, as AWS SDK environment variables."
  sensitive   = true
  value = {
    for name, user in rustfs_user.clients : name => {
      AWS_ACCESS_KEY_ID     = user.access_key
      AWS_SECRET_ACCESS_KEY = random_password.clients[name].result
    }
  }
}
