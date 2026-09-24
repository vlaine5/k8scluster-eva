# =============================================================================
#  Nœud de TEST : un conteneur systemd Ubuntu 24.04 qui imite une VM cloud
#  (utilisateur "ubuntu", sudo sans mot de passe, SSH par clé, cloud-init
#  désactivé). Utilisé uniquement par tests/kubeadm-in-docker/run.sh.
# =============================================================================
ARG BASE_IMAGE=docker.io/library/ubuntu:24.04
FROM ${BASE_IMAGE}

ENV container=docker DEBIAN_FRONTEND=noninteractive

RUN apt-get update -qq \
    && apt-get install -y -qq --no-install-recommends \
       systemd systemd-sysv dbus openssh-server sudo python3 ca-certificates iproute2 iptables kmod cloud-init \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# L'image officielle contient déjà l'utilisateur "ubuntu" (uid 1000), comme les images cloud.
RUN usermod -aG sudo ubuntu \
    && echo 'ubuntu ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/ubuntu && chmod 0440 /etc/sudoers.d/ubuntu \
    && install -d -m 0700 -o ubuntu -g ubuntu /home/ubuntu/.ssh \
    && rm -f /etc/ssh/ssh_host_* \
    && touch /etc/cloud/cloud-init.disabled \
    && printf '[Unit]\nBefore=ssh.service\n[Service]\nType=oneshot\nExecStart=/usr/bin/ssh-keygen -A\n[Install]\nWantedBy=multi-user.target\n' \
       > /etc/systemd/system/ssh-host-keys.service \
    && systemctl enable ssh ssh-host-keys.service

STOPSIGNAL SIGRTMIN+3
CMD ["/sbin/init"]
