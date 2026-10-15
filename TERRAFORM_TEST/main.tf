module "vm"
    source = "./modules/vm"
    for_each = var.vms
    providers = {