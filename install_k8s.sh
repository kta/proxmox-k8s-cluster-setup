#!/usr/bin/env bash

set -eu

# example
# chmod +x install_k8s.sh
# ./install_k8s.sh pve-vm-cp-1 main
# ./install_k8s.sh $(hostname) main
#
# special thanks!:
#       https://gist.github.com/inductor/32116c486095e5dde886b55ff6e568c8
#       https://github.com/unchama/kube-cluster-on-proxmox/blob/main/scripts/k8s-node-setup.sh

# region : script-usage
function usage() {
	echo "usage> k8s-node-setup.sh [COMMAND]"
	echo "[COMMAND]:"
	echo "  help        show command usage"
	echo "  pve-vm-cp-1    run setup script for pve-vm-cp-1"
	echo "  pve-vm-cp-2    run setup script for pve-vm-cp-2"
	echo "  pve-vm-cp-3    run setup script for pve-vm-cp-3"
	echo "  pve-vm-wk-*    run setup script for pve-vm-wk-*"
}

case $1 in
pve-vm-cp-1 | pve-vm-cp-2 | pve-vm-cp-3 | pve-vm-wk-*) ;;
help)
	usage
	exit 255
	;;
*)
	usage
	exit 255
	;;
esac

# endregion

# region : set variables

# Set global variables
TARGET_BRANCH=$2
KUBE_API_SERVER_VIP=192.168.100.201
VIP_INTERFACE=ens19
NODE_IPS=(192.168.100.201 192.168.100.202 192.168.100.203)

# set per-node variables
case $1 in
pve-vm-cp-1)
	KEEPALIVED_STATE=master
	KEEPALIVED_PRIORITY=101
	KEEPALIVED_UNICAST_SRC_IP=${NODE_IPS[0]}
	KEEPALIVED_UNICAST_PEERS=("${NODE_IPS[1]}" "${NODE_IPS[2]}")
	;;
pve-vm-cp-2)
	KEEPALIVED_STATE=BACKUP
	KEEPALIVED_PRIORITY=99
	KEEPALIVED_UNICAST_SRC_IP=${NODE_IPS[1]}
	KEEPALIVED_UNICAST_PEERS=("${NODE_IPS[0]}" "${NODE_IPS[2]}")
	;;
pve-vm-cp-3)
	KEEPALIVED_STATE=BACKUP
	KEEPALIVED_PRIORITY=97
	KEEPALIVED_UNICAST_SRC_IP=${NODE_IPS[2]}
	KEEPALIVED_UNICAST_PEERS=("${NODE_IPS[0]}" "${NODE_IPS[1]}")
	;;
pve-vm-wk-*) ;;
*)
	exit 1
	;;
esac

# endregion

# region : setup for all-node

# set hosts
tee -a /etc/hosts <<EOS
192.168.100.201 pve-vm-cp-1
192.168.100.211 pve-vm-wk-1
192.168.100.202 pve-vm-cp-2
192.168.100.212 pve-vm-wk-2
192.168.100.203 pve-vm-cp-3
192.168.100.213 pve-vm-wk-3
EOS

# Install Containerd
cat <<EOF | sudo tee /etc/modules-load.d/containerd.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

# Setup required sysctl params, these persist across reboots.
cat <<EOF | sudo tee /etc/sysctl.d/99-kubernetes-cri.conf
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF

# Apply sysctl params without reboot
sudo sysctl --system

## Install containerd
apt-get update && apt-get install -y apt-transport-https curl gnupg2

sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo \
	"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
sudo apt-get update && sudo apt-get install -y containerd.io

# Configure containerd
sudo mkdir -p /etc/containerd
sudo containerd config default | sudo tee /etc/containerd/config.toml >/dev/null

if grep -q "SystemdCgroup = true" "/etc/containerd/config.toml"; then
	echo "Config found, skip rewriting..."
else
	sed -i -e "s/SystemdCgroup \= false/SystemdCgroup \= true/g" /etc/containerd/config.toml
fi

sudo systemctl restart containerd

# Modify kernel parameters for Kubernetes
cat <<EOF | tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
vm.overcommit_memory = 1
vm.panic_on_oom = 0
kernel.panic = 10
kernel.panic_on_oops = 1
kernel.keys.root_maxkeys = 1000000
kernel.keys.root_maxbytes = 25000000
net.ipv4.conf.*.rp_filter = 0
EOF
sysctl --system

# Install kubeadm
apt-get update && apt-get install -y apt-transport-https ca-certificates curl gpg
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl

# Disable swap
swapoff -a

cat >/etc/crictl.yaml <<EOF
runtime-endpoint: unix:///var/run/containerd/containerd.sock
image-endpoint: unix:///var/run/containerd/containerd.sock
timeout: 10
EOF

# endregion

# Ends except worker-plane
case $1 in
pve-vm-wk-*)
	exit 0
	;;
pve-vm-cp-1 | pve-vm-cp-2 | pve-vm-cp-3) ;;
*)
	exit 1
	;;
esac

# region : setup for all-control-plane node

# Pull images first
kubeadm config images pull

# endregion

case $1 in
pve-vm-cp-1) ;;
pve-vm-cp-2 | pve-vm-cp-3)
	exit 0
	;;
*)
	exit 1
	;;
esac

# region : setup for first-control-plane node

# Set kubeadm bootstrap token using openssl
KUBEADM_BOOTSTRAP_TOKEN=$(openssl rand -hex 3).$(openssl rand -hex 8)

# kubeadm init --apiserver-advertise-address 192.168.100.201  --pod-network-cidr 10.5.0.0/16 --upload-certs

sudo kubeadm init \
	--pod-network-cidr=10.244.0.0/16 \
	--control-plane-endpoint=$KUBE_API_SERVER_VIP \
	--apiserver-advertise-address=$KUBE_API_SERVER_VIP \
	--upload-certs \
	--token $KUBEADM_BOOTSTRAP_TOKEN

mkdir -p "$HOME"/.kube
cp -i /etc/kubernetes/admin.conf "$HOME"/.kube/config
chown "$(id -u)":"$(id -g)" "$HOME"/.kube/config

# region : setup for cluster
# クラスタ初期セットアップ時に helm　をinstall

# Install Helm CLI
curl https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 | bash

# install CNI
# Needs manual creation of namespace to avoid helm error
kubectl create ns kube-flannel
kubectl get ns
kubectl label --overwrite ns kube-flannel pod-security.kubernetes.io/enforce=privileged

helm repo add flannel https://flannel-io.github.io/flannel/
helm install flannel --set podCidr="10.244.0.0/16" --namespace kube-flannel flannel/flannel

# install MetalLB
kubectl create ns metal-lb
kubectl create ns wp
kubectl get ns

cat >"$HOME"/metallb-config.yaml <<EOF
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: default
  namespace: metal-lb
spec:
  addresses:
  - 192.168.100.200-192.168.100.244
  autoAssign: true
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: default
  namespace: metal-lb
spec:
  ipAddressPools:
  - default
EOF

helm repo add metallb https://metallb.github.io/metallb
helm install metallb metallb/metallb -f metallb-config.yaml

# endregion

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
    apiServerEndpoint: "${KUBE_API_SERVER_VIP}:6443"
    token: "$KUBEADM_BOOTSTRAP_TOKEN"
    unsafeSkipCAVerification: true
controlPlane:
  certificateKey: "$KUBEADM_UPLOADED_CERTS"
EOF

# Set join configuration for worker nodes
# worker use command:    kubeadm join --config /root/join_kubeadm_wk.yaml
#
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
    apiServerEndpoint: "${KUBE_API_SERVER_VIP}:6443"
    token: "$KUBEADM_BOOTSTRAP_TOKEN"
    unsafeSkipCAVerification: true
EOF

# region : setup for debug tool

# install k9s
wget https://github.com/derailed/k9s/releases/download/v0.32.5/k9s_Linux_arm64.tar.gz -O - | tar -zxvf - k9s && sudo mv ./k9s /usr/local/bin/

# endregion

# =========================================================================
#
#
# apt-get update && apt-get install -y apt-transport-https cGa-certificates curl gpg
# curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
#
# # This overwrites any existing configuration in /etc/apt/sources.list.d/kubernetes.list
# echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
#
# sudo apt-get update
# sudo apt-get install -y kubelet kubeadm kubectl
# sudo apt-mark hold kubelet kubeadm kubectl
#
# sudo systemctl enable --now kubelet
#
#
#
#
# echo $TARGET_BRANCH
# echo $KUBE_API_SERVER_VIP
# echo $VIP_INTERFACE
# echo $NODE_IPS
# echo $KEEPALIVED_STATE
# echo $KEEPALIVED_PRIORITY
# echo $KEEPALIVED_UNICAST_SRC_IP
# echo $KEEPALIVED_UNICAST_PEERS
