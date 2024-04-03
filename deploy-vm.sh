#!/usr/bin/env bash

set -eu

# region : set variables

IMG_FILE_URL=https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-arm64.img
DOWNLOAD_FILE_PATH=/tmp/cloudimg-arm64.img
SNIPPET_TARGET_PATH=/var/lib/vz/snippets
TEMPLATE_BOOT_IMAGE_TARGET_VOLUME=local
GITHUB_ACCOUNT=kta
SSHKEY=https://github.com/${GITHUB_ACCOUNT}.keys
TEMPLATE_VMID=9900

VM_LIST=(
	# ---
	# vmid:       proxmox上でVMを識別するID
	# vmname:     proxmox上でVMを識別する名称およびホスト名
	# cpu:        VMに割り当てるコア数(vCPU)
	# mem:        VMに割り当てるメモリ(MB)
	# vmsrvip:    VMのService Segment側NICに割り振る固定IP
	# targetip:   VMの配置先となるProxmoxホストのIP
	# targethost: VMの配置先となるProxmoxホストのホスト名
	# ---
	#vmid #vmname    #cpu #mem  #vmsrvip       #gatewayip   #targetip      #targethost
	"201 pve-vm-cp-1 2    4094  192.168.11.201 192.168.11.1 192.168.11.101 pve-node1"
	"211 pve-vm-wk-1 2    4094  192.168.11.211 192.168.11.1 192.168.11.101 pve-node1"
	"202 pve-vm-cp-2 2    4094  192.168.11.202 192.168.11.1 192.168.11.102 pve-node2"
	"212 pve-vm-wk-2 2    4094  192.168.11.212 192.168.11.1 192.168.11.102 pve-node2"
	"203 pve-vm-cp-3 2    4094  192.168.11.203 192.168.11.1 192.168.11.103 pve-node3"
	"213 pve-vm-wk-3 2    4094  192.168.11.213 192.168.11.1 192.168.11.103 pve-node3"
)

# endregion

# region : preparing for vm creation

if !(type cloud-init > /dev/null 2>&1); then
	apt install cloud-init -y
fi

# Download image
if [ ! -e $DOWNLOAD_FILE_PATH ]; then
	curl $IMG_FILE_URL >$DOWNLOAD_FILE_PATH
fi

# endregion

# region : create template

# region : create template-vm

# create a new VM and attach Network Adaptor
# vmbr0=Service Network Segment (172.16.0.0/20)

STORAGE=local

qm create ${TEMPLATE_VMID} \
	--cores 2 \
	--memory 2048 \
	--scsihw virtio-scsi-single \
	--bios ovmf \
	--efidisk0 ${STORAGE}:0,efitype=4m,pre-enrolled-keys=1,size=64M \
	--scsi0 ${STORAGE}:0,import-from=$DOWNLOAD_FILE_PATH \
	--sata0 ${STORAGE}:cloudinit \
	--boot order=scsi0 \
	--net0 virtio,bridge=vmbr0 \
	--serial0 socket

qm template $TEMPLATE_VMID

# endregion

# region : main

for array in "${VM_LIST[@]}"; do
	echo "${array}" | while read -r vmid vmname cpu mem vmsrvip gatewayip targetip targethost; do

		CLOUD_CONFIG_FILE_NAME=${SNIPPET_TARGET_PATH}/${vmid}-cloud-init.yaml

		echo "----------- ${vmid} ------------"
		# export cloud-config
		cat >"${CLOUD_CONFIG_FILE_NAME}" <<EOF
#cloud-config
hostname: ${vmname}
manage_etc_hosts: true
user: user
password: pass
chpasswd: {expire: False}
ssh_pwauth: true
package_upgrade: true
package_reboot_if_required: true
locale: en_US.UTF-8
timezone: Asia/Tokyo
ssh_authorized_keys: []
write_files:
  - path: /etc/network/ifcfg-eth0
    owner: root:root
    permissions: '0644'
    content: |
      TYPE=Ethernet
      DEVICE=eth0
      ONBOOT=yes
      BOOTPROTO=static
      IPADDR=${vmsrvip}
      PREFIX=24
      GATEWAY=${gatewayip}
      DNS1=${gatewayip}
      DEFROUTE=yes
      PEERDNS=yes
      PEERROUTES=yes
      IPV4_FAILURE_FATAL=no
      IPV6INIT=no
bootcmd:
  - ifdown eth0
  - ifup eth0
runcmd:
  # set ssh_authorized_keys
  - su - user -c "curl -sS ${SSHKEY} >> ~/.ssh/authorized_keys"
  - su - user -c "chmod 600 ~/.ssh/authorized_keys"
  # install kubernetes
  # - su - user -c "wget --no-cache https://raw.githubusercontent.com/${GITHUB_ACCOUNT}/proxmox-k8s-cluster-setup/main/install_k8s.sh"
  # - su - user -c "chmod +x install-k8s.sh"
  # - su - user -c "sudo bash install-k8s.sh"
EOF

		# scp ${CLOUD_CONFIG_FILE_NAME} user@${targetip}:${CLOUD_CONFIG_FILE_NAME}

		# create vm
		qm clone "${TEMPLATE_VMID}" "${vmid}" --name "${vmname}" --full true --target "${targethost}"

		ssh -n ${targetip} qm move-disk "${vmid}" scsi0 "${BOOT_IMAGE_TARGET_VOLUME}" --delete true
		ssh -n ${targetip} qm set "${vmid}" --cores "${cpu}" --memory "${mem}"
		ssh -n ${targetip} qm resize "${vmid}" scsi0 100G

		# set environment
		ssh -n ${targetip} qm set ${vmid} --ipconfig0 ip=${vmsrvip}/24,gw=${gatewayip}
		ssh -n ${targetip} qm set ${vmid} --cicustom "user=local:snippets/${vmid}-cloud-init.yaml"
		ssh -n ${targetip} qm cloudinit dump ${vmid} user
		ssh -n ${targetip} qm start ${vmid}
	done
done

# endregion

qm destroy ${TEMPLATE_VMID}
