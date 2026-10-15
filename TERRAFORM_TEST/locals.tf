locals {
  # Разворачиваем extra_drives для каждой VM в плоский список
  # с уже готовыми именами.
  vm_extra_drives = {
    for vm_key, vm in var.vm-servers : vm_key => [
      for idx, d in coalesce(vm.extra_drives, []) : {
        key = format(
          "%s-%d",
          d.name,
          length([
            for x in slice(coalesce(vm.extra_drives, []), 0, idx + 1) :
            x if x.name == d.name
          ])
        )
        name = d.name
        size = d.size
      }
    ]
  }

  # Удобная карта: { "<vm_key>/<drive_key>" => {vm_key, drive_key, size} }
  vm_extra_drives_map = merge([
    for vm_key, drives in local.vm_extra_drives : {
      for d in drives : "${vm_key}/${d.key}" => {
        vm_key    = vm_key
        drive_key = d.key
        name      = d.name
        size      = d.size
      }
    }
  ]...)
}