#!/bin/bash
vagrant destroy -f
rm -rf roles/join-command
rm -rf roles/completion-command
vagrant up --provider=vmware_esxi --no-provision
vagrant provision master
vagrant provision worker-1
vagrant provision worker-2
vagrant provision worker-3
