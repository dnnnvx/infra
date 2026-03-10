resource "kubernetes_secret_v1" "secrets" {
  for_each = { for s in var.secrets : "${s.namespace}/${s.name}" => s }

  metadata {
    name      = each.value.name
    namespace = each.value.namespace
  }

  data = each.value.data

  # data_wo/binary_data_wo are write-only variants exposed by the Kubernetes provider;
  # they can never be read back, so they always appear as "will be updated" in plans.
  # Ignoring them here suppresses that cosmetic noise — data changes still trigger updates.
  lifecycle {
    ignore_changes = [data_wo, binary_data_wo]
  }

  depends_on = [
    kubernetes_namespace_v1.namespaces,
    helm_release.flux_operator
  ]
}
