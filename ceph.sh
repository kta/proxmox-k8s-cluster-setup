# cephのインストール
# https://github.com/laowolf/pve-docs/blob/master/pveceph.adoc



# Diskを確認
lsblk -f
# 削除
wipefs --force --all /dev/sda
# フォーマット
mkfs.xfs /dev/sda


# Cephのインストール
pveceph install --repository  no-subscription 

pveceph init --network 192.168.11.101/24 --name ceph01 
pveceph mon create --mon-address 192.168.11.101
pveceph mon create --mon-address 192.168.11.102


# モニターの作成
pveceph createmon

# MGRの作成
pveceph createmgr

# OSDの作成
pveceph createosd /dev/sda

# メタデータサーバーの作成
pveceph mds create

# プールの作成
pveceph createpool rbd_01


# 確認
ceph osd crush tree --show-shadow



# ---------- pve-node02の追加 ----------
pveceph install --repository  no-subscription 
pveceph createosd /dev/sda
