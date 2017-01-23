#!/bin/bash

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

# Collect stats only on update
# -> 1 = only collect stats on update, cache them in memory
# -> 0 = always do collect
CONF_COLLECT_ONLY_ON_UPDATE=1

###################################################################################################
################################# do not change below #############################################
###################################################################################################

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
HOSTNAME="$1"
INTERVAL="${COLLECTD_INTERVAL:-60}"

FORCE_UPDATE=0
UPDATE_TIME=-1
UPDATE_SIZE=-1
declare -a CACHE_LINES=()

current_time_ms() {
	date +%s%N | cut -b1-13
}

cache_reset() {
	if [[ "$CONF_COLLECT_ONLY_ON_UPDATE" -eq 1 ]]; then
		## reset cache
		unset CACHE_LINES
		declare -a CACHE_LINES=()
	fi
}

cache_output() {
	if [[ "$CONF_COLLECT_ONLY_ON_UPDATE" -eq 1 ]] && [[ -n "$CACHE_LINES" ]]; then
		## output cached lines
		for i in "${CACHE_LINES[@]}"; do
			echo "$i"
		done
	fi
}

cache_echo() {
	if [[ "$CONF_COLLECT_ONLY_ON_UPDATE" -eq 1 ]]; then
		## execute and store in cache
		CACHE_LINES+=("$@")
	else
		## direct execution
		echo "$@"
	fi
}

collectd_putval() {
	cache_echo "PUTVAL \"freifunk/$1/$2\" interval=${INTERVAL} N:$3"
}

update_nodes_json() {
	UPDATED_NODE_JSON=0
	RUN_UPDATE=0

	if [[ "${FORCE_UPDATE}" -eq 1 ]]; then
		RUN_UPDATE=1
	fi

	if [[ ! -f "${CONF_NODE_JSON_PATH}" ]]; then
		RUN_UPDATE=1
	fi

	if [[ -f "${CONF_NODE_JSON_PATH}" ]] && [[ $(find "${CONF_NODE_JSON_PATH}" -mmin +"$CONF_AUTO_UPDATE_AGE") ]]; then
		RUN_UPDATE=1
	fi

	# check age
	if [[ "$RUN_UPDATE" -eq 1 ]]; then
		UPDATE_TIME=$(current_time_ms)
		wget -O"${CONF_NODE_JSON_PATH}.tmp" "$CONF_NODE_JSON_URL" &> /dev/null
		if [[ -f "${CONF_NODE_JSON_PATH}.tmp" ]]; then
			mv -f "${CONF_NODE_JSON_PATH}.tmp" "${CONF_NODE_JSON_PATH}" &> /dev/null || rm -f "${CONF_NODE_JSON_PATH}.tmp"
			rm -f "${CONF_NODE_JSON_PATH}.tmp"
			UPDATE_TIME=$(($(current_time_ms)-UPDATE_TIME))
			UPDATED_NODE_JSON=1
		fi
	fi
}

general_stats() {
	if [[ "$UPDATE_TIME" -ne -1 ]]; then
		collectd_putval "stats" "gauge-update_time" "$UPDATE_TIME"
	fi

	UPDATE_SIZE=$(stat -c%s "${CONF_NODE_JSON_PATH}")
	collectd_putval "stats" "gauge-update_filesize" "$UPDATE_SIZE"
	collectd_putval "stats" "gauge-collect_time" "$COLLECT_TIME"
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

	collectd_putval "node-${NODE_ID}-${NODE_NAME}" "${COLLECTD_NODE}" "${VAR_VALUE}"
}

const_stat() {
	NODE_ID=$(collectd_translate_name "$NODE_ID")
	NODE_NAME=$(collectd_translate_name "$NODE_NAME")
	COLLECTD_NODE=$(collectd_translate_variable "$1")
	VAR_VALUE="$2"

	collectd_putval "node-${NODE_ID}-${NODE_NAME}" "${COLLECTD_NODE}" "${VAR_VALUE}"
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
	UPDATED_NODE_JSON=0
	if [[ "$CONF_AUTO_UPDATE" -eq 1 ]]; then
		update_nodes_json
	fi

	if [[ "$CONF_COLLECT_ONLY_ON_UPDATE" -eq 0 ]] || [[ "$UPDATED_NODE_JSON" -eq 1 ]]; then
		cache_reset

		COLLECT_TIME=$(current_time_ms)
		for NODE_ID in $@; do
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
		done
		COLLECT_TIME=$(($(current_time_ms)-COLLECT_TIME))

		general_stats
	fi

	cache_output
}

# first run
FORCE_UPDATE=1 main $@

# loop'ed run
while sleep "$INTERVAL"; do
	main $@
done
