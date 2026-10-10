output "host_1_domains" {
  value = module.host_1.created_domains
}

output "host_2_domains" {
  value = module.host_2.created_domains
}

output "storage_pool_paths" {
  value = {
    host_1 = module.host_1.storage_pool_path
    host_2 = module.host_2.storage_pool_path
  }
}

