#!/bin/bash
PATH='/usr/local/bin:/bin:/usr/bin:/usr/local/sbin:/usr/sbin'
PUSSY_CHAIN_ID="space-pussy-pruned"
PUSSY_SNAP_PATH="/mnt/nvme4tb/shared"
PUSSY_LOG_PATH="/mnt/nvme4tb/snapshots/pussy/pussy_log.txt"
PUSSY_DATA_PATH="/mnt/nvme4tb/.pussy/"
PUSSY_SERVICE_NAME="space-pussy-pruned"
PUSSY_LAST_BLOCK_HEIGHT=$(docker exec -t space-pussy-pruned pussy status | jq -r .SyncInfo.latest_block_height)
PUSSY_SNAP_NAME=$(echo "${PUSSY_CHAIN_ID}_${PUSSY_LAST_BLOCK_HEIGHT}_$(date '+%Y-%m-%d').tar")
PUSSY_OLD_SNAP=$(ls ${PUSSY_SNAP_PATH} | egrep -o "${PUSSY_CHAIN_ID}.*tar")
PUSSY_IPFS_HASH=$(cat /mnt/nvme4tb/snapshots/pussy/ipfs_hash)
export IPFS_PATH="/mnt/nvme4tb/.ipfs"
export PUSSY_PATH="/mnt/nvme4tb/.pussy/"

now_date() {
    echo -n $(TZ=":Europe/Moscow" date '+%Y-%m-%d_%H:%M:%S')
}

log_this() {
    YEL='\033[1;33m' # yellow
    NC='\033[0m'     # No Color
    local logging="$@"
    printf "|$(now_date)| $logging\n" | tee -a ${PUSSY_LOG_PATH}
}

log_this "remove and create pussy log file"
rm /mnt/nvme4tb/snapshots/pussy/pussy_log.txt
touch /mnt/nvme4tb/snapshots/pussy/pussy_log.txt

log_this "remove old ipfs pins"
ipfs pin rm $(cat /mnt/nvme4tb/snapshots/pussy/ipfs_hash); echo $? >> ${PUSSY_LOG_PATH}
sleep 8

log_this "unpin ipfs hashes"
ipfs pin ls --type recursive | cut -d' ' -f1 | xargs -n1 ipfs pin rm
sleep 8

log_this "repo gc"
ipfs repo gc; echo $? >> ${PUSSY_LOG_PATH}
sleep 8

log_this "LAST_BLOCK_HEIGHT ${PUSSY_LAST_BLOCK_HEIGHT}"

log_this "Stopping "${PUSSY_SERVICE_NAME}""
docker stop ${PUSSY_SERVICE_NAME}; echo $? >> ${PUSSY_LOG_PATH}

log_this "cosmprund data"
cd /root/cosmprund && ./build/cosmprund prune /mnt/nvme4tb/.pussy/data/ --cosmos-sdk=false
sleep 8

log_this "Creating new snapshot"
time tar --exclude='config' --exclude='cosmovisor'  --exclude='priv_validator_key.json' --exclude='cache' -zcvf /mnt/nvme4tb/shared/${PUSSY_SNAP_NAME} -C /mnt/nvme4tb/.pussy/ .

log_this "Removing old snapshot(s):"
cd ${PUSSY_SNAP_PATH}; echo $? >> ${PUSSY_LOG_PATH}
rm -fv ${PUSSY_OLD_SNAP} &>> ${PUSSY_LOG_PATH}
sleep 8

log_this "add snapshot to ipfs and hash to file"
cd /mnt/nvme4tb/shared/ && ipfs add -q space-pussy-pruned_*.tar | tee /mnt/nvme4tb/snapshots/pussy/ipfs_hash
sleep 8

log_this "add block to file"
cd /mnt/nvme4tb/shared/ && block_num=$(find . -name "space-pussy-pruned_*.tar" | grep -oE '[[:digit:]]{7}' | sed 's/^0*//') && echo $block_num > /mnt/nvme4tb/snapshots/pussy/ipfs_block
sleep 8

log_this "pin ipfs hash"
ipfs pin add $(cat /mnt/nvme4tb/snapshots/pussy/ipfs_hash)
sleep 8

log_this "add block to ipfs"
ipfs add /mnt/nvme4tb/snapshots/pussy/ipfs_block | tail -n1 | awk '{print $2}' > /mnt/nvme4tb/snapshots/pussy/ipfs_block_hash

log_this "add snapshot url to file"
find /mnt/nvme4tb/shared/ -type f -name 'space-pussy-pruned*' -exec echo "https://jupiter.cybernode.ai/shared/{}" \; | head -n1 > /mnt/nvme4tb/snapshots/pussy/snap_url

log_this "add snapshot url to ipfs"
ipfs add /mnt/nvme4tb/snapshots/pussy/snap_url | tail -n1 | awk '{print $2}' > /mnt/nvme4tb/snapshots/pussy/snap_url_hash

log_this "Starting ${PUSSY_SERVICE_NAME}"
docker container start ${PUSSY_SERVICE_NAME}; echo $? >> ${PUSSY_LOG_PATH}
sleep 8

log_this "add cyberlinks from snapshot to block number and from block number to actual snap"
sleep 8
/root/go/bin/pussy tx graph cyberlink $(cat /mnt/nvme4tb/snapshots/pussy/tweet_hash) $(cat /mnt/nvme4tb/snapshots/pussy/ipfs_block_hash) --node tcp://0.0.0.0:46657  --from snapshot_bot --keyring-backend test --chain-id space-pussy -y &>> ${PUSSY_LOG_PATH}
sleep 80
/root/go/bin/pussy tx graph cyberlink $(cat /mnt/nvme4tb/snapshots/pussy/ipfs_block_hash) $(cat /mnt/nvme4tb/snapshots/pussy/ipfs_hash) --node tcp://0.0.0.0:46657 --from snapshot_bot --keyring-backend test --chain-id space-pussy -y &>> ${PUSSY_LOG_PATH}
sleep 80
/root/go/bin/pussy tx graph cyberlink $(cat /mnt/nvme4tb/snapshots/pussy/ipfs_block_hash) $(cat /mnt/nvme4tb/snapshots/pussy/snap_url_hash) --node tcp://0.0.0.0:46657 --from snapshot_bot --keyring-backend test --chain-id space-pussy -y &>> ${PUSSY_LOG_PATH}
sleep 80
/root/go/bin/pussy tx graph cyberlink $(cat /mnt/nvme4tb/snapshots/pussy/ipfs_block_hash) $(cat /mnt/nvme4tb/snapshots/pussy/manual) --node tcp://0.0.0.0:46657 --from snapshot_bot --keyring-backend test --chain-id space-pussy -y &>> ${PUSSY_LOG_PATH}
sleep 8

du -hs ${PUSSY_SNAP_PATH}/${PUSSY_SNAP_NAME} | tee -a ${PUSSY_LOG_PATH}

log_this "Done\n---------------------------\n"
