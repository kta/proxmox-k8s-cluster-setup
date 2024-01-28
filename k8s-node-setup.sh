TARGET_BRANCH="main"

# update and upgrade
apt update
apt upgrade -y

# install ansible
sudo apt-get install -y ansible git sshpass


git clone -b "${TARGET_BRANCH}" https://github.com/kta/proxmox-k8s-cluster-setup.git "$HOME"/proxmox-k8s-cluster-setup

