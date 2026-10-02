command to run:
ansible-playbook 00_bootstrap_hosts.yml --limit host_1 -e bootstrap_user=user_for_selected_host --ask-pass --ask-become-pass --ask-vault-pass
