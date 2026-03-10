resource "kubernetes_secret_v1" "secrets" {
  for_each = { for s in var.secrets : "${s.namespace}/${s.name}" => s }

  metadata {
    name      = each.value.name
    namespace = each.value.namespace
  }

  data = each.value.data

  depends_on = [
    kubernetes_namespace_v1.namespaces,
    helm_release.flux_operator
  ]
}
