resource "time_sleep" "wait_after_routers" {
  depends_on = [
    module.routers_host_1
  ]

  create_duration = "60s"
}


#resource "time_sleep" "wait_after_routers" {
#  depends_on = [
#    module.routers_host_1,
#    module.routers_host_2
# ]
#
# create_duration = "60s"
#}

#bring back after connecting to host 2 restores