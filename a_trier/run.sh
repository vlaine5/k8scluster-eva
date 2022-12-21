#!/bin/bash
# This script will :
vagrant destroy -f # First destroy old clusters if exist
rm -rf roles/join-command # remove the temporary file
rm -rf roles/completion-command # remove the temporary file
vagrant up --provider=vmware_esxi --no-provision # Create the VM with vagrant but not with Ansible configuration
#
##Provision of VM with ansible, one after an other, without that, that we can have some issue because worker could be deployed with the master at the same time, that we don't want.
#Remove or add line in terms of number of worker you
vagrant provision master
vagrant provision worker-1
vagrant provision worker-2
vagrant provision worker-3
