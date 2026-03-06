resource "talos_image_factory_schematic" "this" {
  schematic = yamlencode({
    customization = {
      systemExtensions = {
        officialExtensions = var.image_factory_extensions
      }
    }
  })
}

data "talos_image_factory_urls" "this" {
  talos_version = var.talos_version_full
  schematic_id  = talos_image_factory_schematic.this.id
  platform      = "nocloud"
}
