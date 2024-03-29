# k8scluster - Kube + ESXI + Vagrant + Ansible
K8S Cluster with 3 workers - ESXi 6.5 deployment with Vagrant and Ansible
Full automated deploy, let's begin to create pod or wathever.

Tested in a debian11 VM (hosted esxi).
```bash
ansible [core 2.15.9]
  config file = None
  configured module search path = ['/home/vagrant/.ansible/plugins/modules', '/usr/share/ansible/plugins/modules']
  ansible python module location = /home/vagrant/.local/lib/python3.9/site-packages/ansible
  ansible collection location = /home/vagrant/.ansible/collections:/usr/share/ansible/collections
  executable location = /home/vagrant/.local/bin/ansible
  python version = 3.9.2 (default, Feb 28 2021, 17:03:44) [GCC 10.2.1 20210110] (/usr/bin/python3)
  jinja version = 3.1.3
  libyaml = True
```
https://github.com/josenk/vagrant-vmware-esxi

##### OVF Tools install
Here : https://docs.vmware.com/en/VMware-Telco-Cloud-Operations/1.4.0/deployment-guide-140/GUID-95301A42-F6F6-4BA9-B3A0-A86A268754B6.html

You need to have X11 enable cause of the window to validate install : so if the commande **./VMware[...].bundle** don't work, check it. https://www.cyberciti.biz/faq/x11-connection-rejected-because-of-wrong-authentication/
```shell
apt install xauth
sudo mkdir /root/.Xauthority
mkdir /home/vagrant/.Xauthority

export DISPLAY=localhost:0.0

sudo ./VMware-ovftool-4.3.0-7948156-lin.x86_64.bundle
Extracting VMware Installer...done.
```
Or install with :

```shell
sudo ./VMware-ovftool-4.3.0-7948156-lin.x86_64.bundle --console
```

Execute :
Execute run.sh after modify the Vagrantfile and/or other to match with your organization.
snap.sh can be executed after deployment, simple snapshot with vagrant.
```bash
cd k8scluster-eva
./run.sh
```

# Prerequisite

You need ovftools installed.

You need to do a DHCP reservation before deployment. MAC address are specified in Vagrantfile. Workaround can be setup with ansible. It's due to the fact that the Vagrant esxi plugin can not specify an ip address on the main interface, but only to assign a static IP to an additionnal interface.

See vlaine5/bind9-dhcp repository for simple pre configured server with mac reservation

# Troubleshooting

With the bento image on Vagrant, there is bug you can avoid, here is the error you get :
```bash
==> master: An error occurred. The error will be shown after all tasks complete.
Opening VMX source: /root/.vagrant.d/boxes/bento-VAGRANTSLASH-ubuntu-20.04/202112.19.0/vmware_desktop/ZZZZ_worker-1.vmx
Error: File (/Users/tsmith/.cache/packer/62850188884fff34d447798ebc9d9b22bf1f3f1f.iso) could not be found.
Completed with errors
```

The Vagrant box search for a DVD, it's not that serious, juste fake it or use an other image.
In your host :
```bash
mkdir -p /Users/tsmith/.cache/packer/
touch /Users/tsmith/.cache/packer/62850188884fff34d447798ebc9d9b22bf1f3f1f.iso
```

Addionnaly, i run it with a DNS configured, maybe you'll need to add resolution of master, worker-1, worker-2 etc...
