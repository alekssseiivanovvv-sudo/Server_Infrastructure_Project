output "created_domains" {
  value = concat(
    sort(keys(libvirt_domain.router)),
    sort(keys(libvirt_domain.server))
  )
}

output "storage_pool_path" {
  value = var.pool_path
}

