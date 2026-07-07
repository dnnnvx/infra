resource "kubernetes_namespace_v1" "namespaces" {
  for_each = toset(var.namespaces)

  metadata {
    name = each.key
  }

  # These namespaces are only pre-created so bootstrap secrets have somewhere to
  # land; Flux then adopts them and manages their metadata (adding
  # kustomize.toolkit.fluxcd.io/* labels). Ignore label/annotation drift so tofu
  # and Flux stop fighting over ownership on every apply.
  lifecycle {
    ignore_changes = [metadata[0].labels, metadata[0].annotations]
  }
}
