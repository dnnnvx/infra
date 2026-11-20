# Bootstrap / disaster recovery only. These releases exist so a fresh or rebuilt cluster can
# get Flux running from tofu alone; once Flux syncs, it takes them over through
# infrastructure/controllers/flux/{operator,instance}-release.yaml (same release names) and owns
# every later upgrade and values change. Edit those files, not these.
#
# ignore_changes = all keeps tofu from fighting helm-controller: otherwise every apply creates a
# Helm revision that helm-controller then overwrites, and if the two disagree on values the
# instance can roll back (on 2026-11-20 this reverted the sync URL to an old git source).
resource "helm_release" "flux_operator" {
  name             = "flux-operator"
  namespace        = "flux-system"
  repository       = "oci://ghcr.io/controlplaneio-fluxcd/charts"
  chart            = "flux-operator"
  create_namespace = true

  values = [var.flux_operator_values]

  lifecycle {
    ignore_changes = all
  }
}

resource "helm_release" "flux_instance" {
  depends_on = [helm_release.flux_operator]

  name       = "flux"
  namespace  = "flux-system"
  repository = "oci://ghcr.io/controlplaneio-fluxcd/charts"
  chart      = "flux-instance"

  values = [var.flux_instance_values]

  lifecycle {
    ignore_changes = all
  }
}
