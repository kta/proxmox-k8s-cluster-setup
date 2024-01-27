# raspi-cluster-setup


```bash
sudo su -
rm deploy_vm.sh
wget --no-cache https://raw.githubusercontent.com/kta/raspi-cluster-setup/main/deploy_vm.sh
chmod +x deploy_vm.sh
./deploy_vm.sh


qm stop 201
qm destroy 201
qm stop 211
qm destroy 211
qm stop 202
qm destroy 202
qm stop 212
qm destroy 212
```

