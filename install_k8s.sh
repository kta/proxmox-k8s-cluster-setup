#!/usr/bin/env bash
set -eu

# pve-vm-cp-3
KUBE_API_SERVER_VIP="192.168.11.203"
EXTERNAL_KUBE_API_SERVER_NAME="pve-vm-cp-3"
EXTERNAL_KUBE_API_SERVER_IP="192.168.11.203"

# update時にインタラクティブに対応しない
config_file="/etc/needrestart/needrestart.conf"
new_value="'a'"
sed -i "s/^#\$nrconf{restart} = 'i';/\$nrconf{restart} = $new_value;/" "$config_file"



# apt update and upgrade
apt update
apt upgrade -y

# add hosts
tee -a /etc/hosts <<EOS
192.168.11.201 pve-vm-cp-1
192.168.11.211 pve-vm-wk-1
192.168.11.202 pve-vm-cp-2
192.168.11.212 pve-vm-wk-2
192.168.11.203 pve-vm-cp-3
192.168.11.213 pve-vm-wk-3
EOS

# disable swap
swapoff -a
sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# ----------- install containerd ----------------
cat <<EOF | sudo tee /etc/modules-load.d/containerd.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

# sysctl設定
cat <<EOF | sudo tee /etc/sysctl.d/kubernetes.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
vm.overcommit_memory = 1
vm.panic_on_oom = 0
kernel.panic = 10
kernel.panic_on_oops = 1
kernel.keys.root_maxkeys = 1000000
kernel.keys.root_maxbytes = 25000000
net.ipv4.conf.*.rp_filter = 0
EOF

# sysctlの反映
sudo sysctl --system

# install containerd
# containerdのインストール

sudo apt update
sudo apt install -y containerd

# containerdの設定
# containerdの設定ファイルを作成
sudo mkdir -p /etc/containerd
sudo containerd config default | sudo tee /etc/containerd/config.toml >/dev/null

# containerdの設定ファイルを編集
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml

# containerdの再起動
sudo systemctl restart containerd

# containerdの自動起動
systemctl enable containerd

# containerdのバージョン確認
containerd --version

# kubernetesのリポジトリ追加
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
tee /etc/apt/sources.list.d/kubernetes.list <<EOF
deb https://apt.kubernetes.io/ kubernetes-xenial main
EOF

# kubernetesのインストール
sudo apt-get install -y apt-transport-https ca-certificates curl gpg
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt update
sudo apt install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl

# kubernetesの自動起動
systemctl enable kubelet

# kubernetesのバージョン確認
kubeadm version

cat >/etc/crictl.yaml <<EOF
runtime-endpoint: unix:///var/run/containerd/containerd.sock
image-endpoint: unix:///var/run/containerd/containerd.sock
timeout: 10
EOF

# install flannel

# Ends except first-control-plane
case $1 in
pve-vm-cp-3) 
  ;;
pve-vm-cp-2 | pve-vm-cp-1)
	exit 0
	;;
*)
	exit 1
	;;
esac

# region : setup for first-control-plane node

# Set init configuration for the first control plane
KUBEADM_BOOTSTRAP_TOKEN=$(openssl rand -hex 3).$(openssl rand -hex 8)

cat > "$HOME"/init_kubeadm.yaml <<EOF
apiVersion: kubeadm.k8s.io/v1beta3
kind: InitConfiguration
bootstrapTokens:
- token: "$KUBEADM_BOOTSTRAP_TOKEN"
  description: "kubeadm bootstrap token"
  ttl: "24h"
nodeRegistration:
  criSocket: "unix:///var/run/containerd/containerd.sock"
---
apiVersion: kubeadm.k8s.io/v1beta3
kind: ClusterConfiguration
networking:
  serviceSubnet: "10.96.0.0/16"
  podSubnet: "10.128.0.0/16"
kubernetesVersion: "v1.29.2"
controlPlaneEndpoint: "${KUBE_API_SERVER_VIP}:8443"
apiServer:
  certSANs:
  - "${EXTERNAL_KUBE_API_SERVER_NAME}" # generate random FQDN to prevent malicious DoS attack
  # - "${EXTERNAL_KUBE_API_SERVER_IP}" # generate random FQDN to prevent malicious DoS attack
controllerManager:
  extraArgs:
    bind-address: "0.0.0.0"
scheduler:
  extraArgs:
    bind-address: "0.0.0.0"
---
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
cgroupDriver: "systemd"
protectKernelDefaults: true
EOF


# # kubernetesの設定
# mkdir -p $HOME/.kube
# cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
# chown $(id -u):$(id -g) $HOME/.kube/config
#
# # kubernetesのネットワーク設定
# kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml
#
# # kubernetesのネットワーク確認
# kubectl get pods --all-namespaces
#
# # kubernetesのノード確認
# kubectl get nodes

# kubeadm init --pod-network-cidr=10.244.0.0/16 --control-plane-endpoint=pve-vm-cp-1 --apiserver-cert-extra-sans=pve-vm-cp-1
kubeadm init --config "$HOME"/init_kubeadm.yaml --skip-phases=addon/kube-proxy --ignore-preflight-errors=NumCPU,Mem


mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# ----------------- Helm -----------------

# Install Helm
# https://helm.sh/docs/intro/install/#from-apt-debianubuntu
curl https://baltocdn.com/helm/signing.asc | gpg --dearmor | sudo tee /usr/share/keyrings/helm.gpg >/dev/null
sudo apt install apt-transport-https --yes
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list
sudo apt update
sudo apt install -y helm

# Install MetalLB
# https://metallb.universe.tf/installation/#installation-with-helm
helm repo add metallb https://metallb.github.io/metallb
kubectl create namespace metallb-system
helm install metallb metallb/metallb -n metallb-system

# ----------------- Preparation for connecting k8s nodes -----------------

# Generate control plane certificate
KUBEADM_UPLOADED_CERTS=$(kubeadm init phase upload-certs --upload-certs | tail -n 1)

# Set join configuration for other control plane nodes
cat >"$HOME"/join_kubeadm_cp.yaml <<EOF
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
cgroupDriver: "systemd"
protectKernelDefaults: true
---
apiVersion: kubeadm.k8s.io/v1beta3
kind: JoinConfiguration
nodeRegistration:
  criSocket: "unix:///var/run/containerd/containerd.sock"
discovery:
  bootstrapToken:
    apiServerEndpoint: "${KUBE_API_SERVER_VIP}:8443"
    token: "$KUBEADM_BOOTSTRAP_TOKEN"
    unsafeSkipCAVerification: true
controlPlane:
  certificateKey: "$KUBEADM_UPLOADED_CERTS"
EOF

# Set join configuration for worker nodes
cat >"$HOME"/join_kubeadm_wk.yaml <<EOF
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
cgroupDriver: "systemd"
protectKernelDefaults: true
---
apiVersion: kubeadm.k8s.io/v1beta3
kind: JoinConfiguration
nodeRegistration:
  criSocket: "unix:///var/run/containerd/containerd.sock"
discovery:
  bootstrapToken:
    apiServerEndpoint: "${KUBE_API_SERVER_VIP}:8443"
    token: "$KUBEADM_BOOTSTRAP_TOKEN"
    unsafeSkipCAVerification: true
EOF

# install ansible
sudo apt-get install -y ansible git sshpass

# clone repo
TARGET_BRANCH="main"
git clone -b "${TARGET_BRANCH}" https://github.com/kta/proxmox-k8s-cluster-setup "$HOME"/kube-cluster-on-proxmox

# export ansible.cfg target
REPOSITORY_NAME=proxmox-k8s-cluster-setup
ANSIBLE_CONFIG="$HOME"/${REPOSITORY_NAME}/ansible/ansible.cfg

# run ansible-playbook
ansible-galaxy role install -r "$HOME"/${REPOSITORY_NAME}/ansible/roles/requirements.yaml
ansible-galaxy collection install -r "$HOME"/${REPOSITORY_NAME}/ansible/roles/requirements.yaml
ansible-playbook -i "$HOME"/${REPOSITORY_NAME}/ansible/hosts/k8s-servers/inventory "$HOME"/${REPOSITORY_NAME}/ansible/site.yaml
