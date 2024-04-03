# raspi-cluster-setup


```bash
sudo su -
wget --no-cache https://raw.githubusercontent.com/kta/proxmox-k8s-cluster-setup/main/deploy-vm.sh
chmod +x deploy-vm.sh
./deploy-vm.sh


qm start 201
qm start 211
qm start 202
qm start 212

qm stop 201
qm stop 211
qm stop 202
qm stop 212

qm destroy 201
qm destroy 211
qm destroy 202
qm destroy 212
qm destroy 203
qm destroy 213
```


qm resize 201 scsi0 100G
qm resize 202 scsi0 100G
qm resize 211 scsi0 100G
qm resize 212 scsi0 100G

## install ceph

```bash

sudo su -
wget --no-cache https://raw.githubusercontent.com/kta/proxmox-k8s-cluster-setup/main/ceph.sh
chmod +x ./ceph.sh
./ceph.sh
```


## install k8s

```bash

sudo su -
wget --no-cache https://raw.githubusercontent.com/kta/proxmox-k8s-cluster-setup/main/install_k8s.sh
chmod +x ./install_k8s.sh
./install_k8s.sh pve-vm-cp-1
```

```
qm stop 203
qm destroy 203
./deploy-vm.sh
rm ~/.ssh/known_hosts
ssh user@192.168.11.203




sudo su -

wget --no-cache https://raw.githubusercontent.com/kta/proxmox-k8s-cluster-setup/main/install_k8s.sh
chmod +x ./install_k8s.sh
/install_k8s.sh pve-vm-cp-3
```
