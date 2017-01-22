#!/bin/bash

if [[ -n "$FORCE_UPDATE" ]]; then
	FORCE_UPDATE=1
else
	FORCE_UPDATE=0
fi

set -o pipefail  ## trace ERR through pipes
set -o errtrace  ## trace ERR through 'time command' and other functions
set -o nounset   ## set -u : exit the script if you try to use an uninitialised variable
set -o errexit   ## set -e : exit the script if any statement returns a non-true return value

# Automatic update
# -> 1 = enabled
# -> 0 = disabled
CONF_AUTO_UPDATE=1

# -> 0 = always
# -> 5 = every 5 minutes
CONF_AUTO_UPDATE_AGE=5

# URL for nodes.json
CONF_NODE_JSON_URL="http://hg.albi.info/json/nodes.json"

# Storage path for nodes.json
CONF_NODE_JSON_PATH="/dev/shm/ffs-stats-nodes.json"


### do not change below ###

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
HOSTNAME="$1"
INTERVAL="${COLLECTD_INTERVAL:-60}"

update_nodes_json() {
	RUN_UPDATE=0
	if [[ ! -f "${CONF_NODE_JSON_PATH}" ]]; then
		RUN_UPDATE=1
	fi

	if [[ "$FORCE_UPDATE" -eq 1 ]]; then
		RUN_UPDATE=1
	fi

	if test $(find "${CONF_NODE_JSON_PATH}" -mmin +"$CONF_AUTO_UPDATE_AGE" &> /dev/null); then
		RUN_UPDATE=1
	fi

	if [[ "$UPDATE_FINSIHED" -eq 0 ]]; then
		# check age
		if [[ "$RUN_UPDATE" -eq 1 ]]; then
			UPDATE_TIME=$(date +%s)
			wget -O"${CONF_NODE_JSON_PATH}.tmp" "$CONF_NODE_JSON_URL" &> /dev/null
			if [[ -f "${CONF_NODE_JSON_PATH}.tmp" ]]; then
				mv -f "${CONF_NODE_JSON_PATH}.tmp" "${CONF_NODE_JSON_PATH}" &> /dev/null || rm -f "${CONF_NODE_JSON_PATH}.tmp"
				rm -f "${CONF_NODE_JSON_PATH}.tmp"
				UPDATE_TIME=$(($(date +%s)-UPDATE_TIME))
				UPDATE_SIZE=$(stat -c%s "${CONF_NODE_JSON_PATH}")
				echo "PUTVAL \"freifunk/stats/gauge-update_time\" interval=${INTERVAL} N:$UPDATE_TIME"
				echo "PUTVAL \"freifunk/stats/gauge-update_filesize\" interval=${INTERVAL} N:$UPDATE_SIZE"
			fi
		fi
		UPDATE_FINSIHED=1
	fi
}

collectd_translate_name() {
  key="$*"
  key=$(echo "$key" | sed 's/[^[:print:]]//')
  key=${key//./_}
  key=${key//\//_}
  key=${key// /_}
  echo "$key"
}

collectd_translate_variable() {
  key="$*"
  key=$(echo "$key" | sed 's/[^[:print:]]//')
  key=${key//./_}
  key=${key//\//_}
  key=${key// /_}
  echo "$key"
}

extract_stat() {
	NODE_ID=$(collectd_translate_name "$NODE_ID")
	NODE_NAME=$(collectd_translate_name "$NODE_NAME")
	VAR_NAME="$1"
	COLLECTD_NODE=$(collectd_translate_variable "$2")
	VAR_VALUE=$(echo "$NODE_STATS_JSON" | jq -r ".$VAR_NAME")

	if [[ "$#" -eq 3 ]]; then
		VAR_VALUE=$("$3" "$VAR_VALUE")
	fi

	echo "PUTVAL \"freifunk/node-${NODE_ID}-${NODE_NAME}/${COLLECTD_NODE}\" interval=${INTERVAL} N:${VAR_VALUE}"
}

const_stat() {
	NODE_ID=$(collectd_translate_name "$NODE_ID")
	NODE_NAME=$(collectd_translate_name "$NODE_NAME")
	COLLECTD_NODE=$(collectd_translate_variable "$1")
	VAR_VALUE="$2"

	echo "PUTVAL \"freifunk/node-${NODE_ID}-${NODE_NAME}/${COLLECTD_NODE}\" interval=${INTERVAL} N:${VAR_VALUE}"
}

to_int() {
        VAL=$(echo "$1" | sed 's/[^[:print:]]//')
	printf '%.*f' 0 "$VAL"
}

to_float() {
        VAL=$(echo "$1" | sed 's/[^[:print:]]//')
	printf '%.*f' 5 "$VAL"
}

main() {
	UPDATE_FINSIHED=0
	if [[ "$CONF_AUTO_UPDATE" -eq 1 ]]; then
		update_nodes_json
		sleep 1
	fi

	COLLECT_TIME=$(date +%s)
	for NODE_ID in $@; do
		case "$NODE_ID" in
			"update")
				update_nodes_json
				;;

			*)
				# fix numeric translation from collectd 
				# workaround if mac-address is numeric and not quoted inside collect.dconf
				NODE_ID=$(echo "$NODE_ID" | cut -d '.' -f 1)

				if [[ -f "${CONF_NODE_JSON_PATH}" ]]; then
					NODE_JSON=$(cat "${CONF_NODE_JSON_PATH}" | jq -c ".nodes[] | select(.nodeinfo.node_id == \"$NODE_ID\")")
					NODE_STATS_JSON=$(echo "${NODE_JSON}" | jq -c ".statistics")
					NODE_NAME=$(echo "${NODE_JSON}" | jq -r ".nodeinfo.hostname")

					if [[ "$NODE_STATS_JSON" != '{}' ]]; then
						const_stat "power" 1
						extract_stat "uptime" "uptime" "to_int"
						extract_stat "loadavg" "gauge-loadavg" "to_float"
						extract_stat "clients" "users" "to_int"
						extract_stat "memory_usage" "percent-memory" "to_float"
						extract_stat "rootfs_usage" "percent-rootfs" "to_float"
					fi
				fi
				;;
		esac
	done
	COLLECT_TIME=$(($(date +%s)-COLLECT_TIME))
	echo "PUTVAL \"freifunk/stats/gauge-collect_time\" interval=${INTERVAL} N:$COLLECT_TIME"
}

# first run
main $@

# loop'ed run
while sleep "$INTERVAL"; do
	main $@
done
