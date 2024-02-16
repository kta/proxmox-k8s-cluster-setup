# cephのインストール
# https://github.com/laowolf/pve-docs/blob/master/pveceph.adoc

CEPH_CLUSTER_IP_1=192.168.11.101
CEPH_CLUSTER_IP_2=192.168.11.102
CEPH_CLUSTER_IP_3=192.168.11.103

# Diskを確認
lsblk -f
# 削除
wipefs --force --all /dev/sda
# フォーマット
mkfs.xfs /dev/sda

# Cephのインストール
pveceph install --repository no-subscription

pveceph init --network ${CEPH_CLUSTER_IP_1}/24 --name ceph01
pveceph mon create --mon-address ${CEPH_CLUSTER_IP_1}
pveceph mon create --mon-address ${CEPH_CLUSTER_IP_2}
pveceph mon create --mon-address ${CEPH_CLUSTER_IP_3}

# モニターの作成
pveceph createmon

# MGRの作成
pveceph createmgr

# OSDの作成
pveceph createosd /dev/sda
# メタデータサーバーの作成
pveceph mds create

# プールの作成
pveceph pool create cephfs02 --application cephfs --size 2
pveceph fs create --pg_num 128 --add-storage 1

# 確認
ceph osd crush tree --show-shadow

# ---------- pve-node02の追加 ----------
pveceph install --repository no-subscription
pveceph createosd /dev/sda

FS_NAME=cephfs
pveceph fs destroy ${FS_NAME}
pveceph mds destroy pve-node1
pveceph pool destroy ${FS_NAME}_data
pveceph pool destroy ${FS_NAME}_metadata

pveceph mds create

# プールの作成
pveceph pool create rbd_01
pveceph fs create --pg_num 128 --add-storage 1
pveceph fs create --pg_num 128 --add-storage 1 --name pve-cephfs
