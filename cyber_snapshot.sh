#!/bin/bash
PATH='/usr/local/bin:/bin:/usr/bin:/usr/local/sbin:/usr/sbin'
CHAIN_ID="bostrom_pruned"
SNAP_PATH="/mnt/nvme4tb/shared"
LOG_PATH="/mnt/nvme4tb/snapshots/bostrom/cyber_log.txt"
DATA_PATH="/mnt/nvme4tb/.cyber/"
SERVICE_NAME="bostrom_pruned"
RPC_ADDRESS="http://localhost:28957"
LAST_BLOCK_HEIGHT=$(docker exec -t bostrom_pruned cyber status | jq -r .SyncInfo.latest_block_height)
SNAP_NAME=$(echo "${CHAIN_ID}_${LAST_BLOCK_HEIGHT}_$(date '+%Y-%m-%d').tar")
OLD_SNAP=$(ls ${SNAP_PATH} | egrep -o "${CHAIN_ID}.*tar")
IPFS_HASH="/mnt/nvme4tb/snapshots/bostrom/ipfs_hash"
export IPFS_PATH="/mnt/nvme4tb/.ipfs"
export CYBER_PATH="/root/.cyber"

now_date() {
    echo -n $(TZ=":Europe/Moscow" date '+%Y-%m-%d_%H:%M:%S')
}

log_this() {
    YEL='\033[1;33m' # yellow
    NC='\033[0m'     # No Color
    local logging="$@"
    printf "|$(now_date)| $logging\n" | tee -a ${LOG_PATH}
}

log_this "remove and create cyber log file"
rm /mnt/nvme4tb/snapshots/bostrom/cyber_log.txt
touch /mnt/nvme4tb/snapshots/bostrom/cyber_log.txt

log_this "remove old ipfs pins"
ipfs pin rm $(cat /mnt/nvme4tb/snapshots/bostrom/ipfs_hash); echo $? >> ${LOG_PATH}
sleep 8

log_this "unpin ipfs hashes"
ipfs pin ls --type recursive | cut -d' ' -f1 | xargs -n1 ipfs pin rm
sleep 8

log_this "repo gc"
ipfs repo gc; echo $? >> ${LOG_PATH}
sleep 8

log_this "LAST_BLOCK_HEIGHT ${LAST_BLOCK_HEIGHT}"

log_this "Stopping ${SERVICE_NAME}"
docker stop ${SERVICE_NAME}; echo $? >> ${LOG_PATH}
sleep 8

log_this "cosmprund data"
cd /root/cosmprund && ./build/cosmprund prune /mnt/nvme4tb/.cyber/data/ --cosmos-sdk=false
sleep 8

log_this "Creating new snapshot"
time tar --exclude='bak' --exclude='config' --exclude='cosmovisor' --exclude='cuda-keyring_1.0-1_all.deb' --exclude='priv_validator_key.json' --exclude='cache' -zcvf /mnt/nvme4tb/shared/${SNAP_NAME} -C /mnt/nvme4tb/.cyber/ .

log_this "Removing old snapshot(s):"
cd ${SNAP_PATH}; echo $? >> ${LOG_PATH}
rm -fv ${OLD_SNAP} &>> ${LOG_PATH}

log_this "add snapshot to ipfs and to file and last block to file"
cd /mnt/nvme4tb/shared/ && ipfs add -q bostrom_pruned_*.tar | tee /mnt/nvme4tb/snapshots/bostrom/ipfs_hash
sleep 8

log_this "add block to file"
cd /mnt/nvme4tb/shared/ && block_num=$(find . -name "bostrom_pruned_*.tar" | grep -oE '[[:digit:]]{7}' | sed 's/^0*//') && echo $block_num > /mnt/nvme4tb/snapshots/bostrom/ipfs_block
sleep 8

log_this "pin ipfs hash"
ipfs pin add $(cat /mnt/nvme4tb/snapshots/bostrom/ipfs_hash)

log_this "add block to ipfs"
ipfs add /mnt/nvme4tb/snapshots/bostrom/ipfs_block | tail -n1 | awk '{print $2}' > /mnt/nvme4tb/snapshots/bostrom/ipfs_block_hash

log_this "add snapshot url to file"
find /mnt/nvme4tb/shared/ -type f -name 'bostrom_pruned*' -exec echo "https://jupiter.cybernode.ai/shared/{}" \; | head -n1 > /mnt/nvme4tb/snapshots/bostrom/snap_url

log_this "add snapshot url to ipfs"
ipfs add /mnt/nvme4tb/snapshots/bostrom/snap_url | tail -n1 | awk '{print $2}' > /mnt/nvme4tb/snapshots/bostrom/snap_url_hash
sleep 8

log_this "Starting ${SERVICE_NAME}"
docker container start ${SERVICE_NAME}; echo $? >> ${LOG_PATH}
sleep 8

log_this "add cyberlinks from snapshot to block number and from block number to actual snap"
sleep 8
cyber tx graph cyberlink $(cat /mnt/nvme4tb/snapshots/bostrom/tweet_hash) $(cat /mnt/nvme4tb/snapshots/bostrom/ipfs_block_hash) --from snapshot_bot --keyring-backend test --chain-id bostrom -y &>> ${LOG_PATH}
sleep 8
cyber tx graph cyberlink $(cat /mnt/nvme4tb/snapshots/bostrom/ipfs_block_hash) $(cat /mnt/nvme4tb/snapshots/bostrom/ipfs_hash) --from snapshot_bot --keyring-backend test --chain-id bostrom --gas 700000 --gas-prices 0.01boot -y &>> ${LOG_PATH}
sleep 8
cyber tx graph cyberlink $(cat /mnt/nvme4tb/snapshots/bostrom/ipfs_block_hash) $(cat /mnt/nvme4tb/snapshots/bostrom/snap_url_hash) --from snapshot_bot --keyring-backend test --chain-id bostrom --gas 700000 --gas-prices 0.01boot -y &>> ${LOG_PATH}
sleep 8
cyber tx graph cyberlink $(cat /mnt/nvme4tb/snapshots/bostrom/ipfs_block_hash) $(cat /mnt/nvme4tb/snapshots/bostrom/manual) --from snapshot_bot --keyring-backend test --chain-id bostrom --gas 700000 --gas-prices 0.01boot -y &>> ${LOG_PATH}

du -hs ${SNAP_PATH}/${SNAP_NAME} | tee -a ${LOG_PATH}

log_this "Done\n---------------------------\n"
