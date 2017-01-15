#!/bin/bash

set -o pipefail  ## trace ERR through pipes
set -o errtrace  ## trace ERR through 'time command' and other functions
set -o nounset   ## set -u : exit the script if you try to use an uninitialised variable
set -o errexit   ## set -e : exit the script if any statement returns a non-true return value

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
NODES_JSON="/dev/shm/ffs-stats-nodes.json"
NODES_URL="http://hg.albi.info/json/nodes.json"
HOSTNAME="$1"
INTERVAL="${COLLECTD_INTERVAL:-60}"
NODE_ID=$1

if [[ "$NODE_ID" == "update" ]]; then
	wget -O"${NODES_JSON}.tmp" "$NODES_URL"
	mv "${NODES_JSON}.tmp" "${NODES_JSON}"
	exit 0
fi


extract_stat() {
	VAR_NAME=$1
	VAR_VALUE=$(echo "$NODE_STATS_JSON" | jq ".$VAR_NAME")
	echo "PUTVAL \"freifunk/${HOSTNAME}/gauge-$VAR_NAME\" interval=$INTERVAL N:$VAR_VALUE"
}

NODE_STATS_JSON=$(cat "${NODES_JSON}" | jq -c ".nodes[] | select(.nodeinfo.node_id == \"$NODE_ID\") | .statistics")
extract_stat "uptime"
extract_stat "loadavg"
extract_stat "clients"
extract_stat "memory_usage"
extract_stat "rootfs_usage"
extract_stat "clients"
