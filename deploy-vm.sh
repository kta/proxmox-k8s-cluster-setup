IMG_FILE_URL=https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-arm64.img
DOWNLOAD_FILE_PATH=/tmp/cloudimg-arm64.img
SNIPPET_TARGET_PATH=/var/lib/vz/snippets
SSHKEY=https://github.com/kta.keys

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
	#vmid #vmname     #cpu #mem  #vmsrvip       #gatewayip   #targetip     #targethost
	"201 pve-vm-cp-1 1    2048  192.168.11.201 192.168.11.1 192.168.11.101 prox-node1"
	"211 pve-vm-wk-1 1    2048  192.168.11.211 192.168.11.1 192.168.11.101 prox-node1"
	"202 pve-vm-cp-2 1    2048  192.168.11.202 192.168.11.1 192.168.11.102 prox-node2"
	"212 pve-vm-wk-2 1    2048  192.168.11.212 192.168.11.1 192.168.11.102 prox-node2"
)

if !(type cloud-init > /dev/null 2>&1); then
	apt install cloud-init
fi

# Download image
if [ ! -e $DOWNLOAD_FILE_PATH ]; then
	curl $IMG_FILE_URL >$DOWNLOAD_FILE_PATH
fi

for array in "${VM_LIST[@]}"; do
	echo "${array}" | while read -r vmid vmname cpu mem vmsrvip gatewayip targetip targethost; do

		echo "----------- ${vmid} ------------"
		# export cloud-config
		cat >"${SNIPPET_TARGET_PATH}/${vmid}-cloud-init.yaml" <<EOF
#cloud-config
hostname: ${vmname}
manage_etc_hosts: true
user: user
password: pass
chpasswd: {expire: False}
ssh_pwauth: true
package_upgrade: true
package_reboot_if_required: true
locale: ja_JP.UTF-8
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
      BOOTPROTO=none
      IPADDR=${vmsrvip}/24
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
  - su - user -c "curl -sS https://github.com/kta.keys >> ~/.ssh/authorized_keys"
  - su - user -c "chmod 600 ~/.ssh/authorized_keys"
EOF

		# create vm
		qm create ${vmid} \
			--cpulimit ${cpu} \
			--memory ${mem} \
			--net0 virtio,bridge=vmbr0 \
			--scsihw virtio-scsi-single \
			--bios ovmf \
			--efidisk0 local:0,efitype=4m,pre-enrolled-keys=1,size=64M \
			--scsi0 local:0,import-from=$DOWNLOAD_FILE_PATH \
			--sata0 local:cloudinit \
			--boot order=scsi0 \
			--serial0 socket

		# set environment
		qm set ${vmid} --ipconfig0 ip=${vmsrvip}/24,gw=${gatewayip}
		qm set ${vmid} --cicustom "user=local:snippets/${vmid}-cloud-init.yaml"
		qm cloudinit dump ${vmid} user
		qm start ${vmid}
	done
done
