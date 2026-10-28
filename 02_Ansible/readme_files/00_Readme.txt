command to run 00:
ansible-playbook 00_bootstrap_hosts.yml --limit host_1 -e bootstrap_user=user_for_selected_host --ask-pass --ask-become-pass --ask-vault-pass

run 02 and 03:
ansible-playbook 02_routers_creation.yml --ask-vault-pass
ansible-playbook 03_vm_creation.yml --ask-vault-pass
