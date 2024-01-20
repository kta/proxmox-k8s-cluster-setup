VM_ID=$0

IMG_FILE_URL=https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-arm64.img
DOWNLOAD_FILE_PATH=/tmp/cloudimg-arm64.img

if !(type cloud-init > /dev/null 2>&1); then
 apt install cloud-init
fi


# Download image
if [ ! -e $DOWNLOAD_FILE_PATH ]; then
 curl $IMG_FILE_URL > $DOWNLOAD_FILE_PATH
fi

# Download cloud config
wget https://raw.githubusercontent.com/kta/raspi-cluster-setup/main/cloudinit/$VM_ID-cloud-init.yml -O $VM_ID-cloud-init.yml
cp $VM_ID-cloud-init.yml /var/lib/vz/snippets/

qm create $VM_ID \
--cpulimit 1 \
--memory 2048  \
--net0 virtio,bridge=vmbr0  \
--scsihw virtio-scsi-single \
--bios ovmf \
--efidisk0 local:0,efitype=4m,pre-enrolled-keys=1,size=64M \
--scsi0 local:0,import-from=$DOWNLOAD_FILE_PATH \
--sata0 local:cloudinit \
--boot order=scsi0 \
--serial0 socket

qm set $VM_ID --sshkey ~/.ssh/id_rsa.pub
qm set $VM_ID --ipconfig0 ip=192.168.11.201/24,gw=192.168.11.1
# qm set $VM_ID --ipconfig0 ip=10.0.10.101/24,gw=10.0.10.1
qm set $VM_ID --cicustom "user=local:snippets/$VM_ID-cloud-init.yml"
qm cloudinit dump $VM_ID user
qm start $VM_ID
