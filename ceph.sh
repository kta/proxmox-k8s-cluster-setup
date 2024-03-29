# cephのインストール
# https://github.com/laowolf/pve-docs/blob/master/pveceph.adoc

CEPH_CLUSTER_IP_1=192.168.11.101
CEPH_CLUSTER_IP_2=192.168.11.102
CEPH_CLUSTER_IP_3=192.168.11.103

DEVICE_NAME=/dev/sda

# memo:ディスクはUIで破棄した方が良いかも
# Diskを確認
lsblk -f
# 削除
wipefs --force --all ${DEVICE_NAME}
dmsetup remove_all

# フォーマット
# mkfs.xfs -f ${DEVICE_NAME}

# ------------- メインサーバーのみ -------------------
# Cephのインストール
pveceph install --repository no-subscriptiopveceph install --repository no-subscriptionn

pveceph init --network ${CEPH_CLUSTER_IP_1}/24

# モニターの作成
pveceph mon create --mon-address ${CEPH_CLUSTER_IP_1}

# MGRの作成
pveceph mgr create

pveceph osd create ${DEVICE_NAME}

# メタデータサーバーの作成
pveceph mds create

# pveceph fs create --pg_num 30 --add-storage
# pveceph fs create --pg_num 30 --add-storage

# プールの作成
# pveceph pool create cephfs_01
# 動くかわからない
pveceph pool create cephfs_01 --add_storages

ceph osd crush tree --show-shadow

# ------------- メインサーバー以外 -------------------
# OSDの作成

# pveceph osd create ${DEVICE_NAME}
