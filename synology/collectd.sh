#!/bin/bash

#This script pulls storage information from the Synology NAS

set -o pipefail  ## trace ERR through pipes
set -o errtrace  ## trace ERR through 'time command' and other functions
set -o nounset   ## set -u : exit the script if you try to use an uninitialised variable
set -o errexit   ## set -e : exit the script if any statement returns a non-true return value

DRIVE_COUNT=9
NETWORK_COUNT=10
HOSTNAME="$1"
INTERVAL="${COLLECTD_INTERVAL:-60}"

fetch_snmp() {
    snmpget -v 2c -c public "$HOSTNAME" "$1" -Ov | cut -f 2 -d ':' | xargs
}

search_snmp_id() {
    (
        set +o pipefail
        set +o errexit
	snmpwalk -v 2c -c public "$HOSTNAME" "$1" | grep -v 'No Such Object available on this agent at this OID' | grep -E -e "$2" | cut -f 1 -d '=' | xargs
    ) | cat
}

to_int() {
        printf '%.*f' 0 "$1"
}

to_float() {
        printf '%.*f' 5 "$1"
}

extract_last_node_id() {
    echo "$1" | rev | cut -d. -f1 | rev
}

snmp_simple_multi() {
    MAIN_NODE=$1
    STATS_NODE=$2
    shift
    shift

   VALUE_LIST=""
   for SNMP_NODE in $@; do
     value=$(fetch_snmp "$SNMP_NODE")
     value=$(to_int "$value")
     if [[ -n "$VALUE_LIST" ]]; then
       VALUE_LIST="$VALUE_LIST:$value"
     else
       VALUE_LIST="$value"
     fi
   done

   if [[ -n "$VALUE_LIST" ]]; then
     collectd_native "$MAIN_NODE" "$STATS_NODE" "$VALUE_LIST"
   fi
}

snmp_simple_native() {
    MAIN_NODE=$1
    STATS_NODE=$2
    SNMP_NODE=$3

    value=$(fetch_snmp "$SNMP_NODE")
    value=$(to_int "$value")

    if [[ "$value" != "" ]]; then
        collectd_native "$MAIN_NODE" "$STATS_NODE" "$value"
    fi
}

snmp_simple_derive() {
    MAIN_NODE=$1
    STATS_NODE=$2
    SNMP_NODE=$3

    value=$(fetch_snmp "$SNMP_NODE")
    value=$(to_int "$value")

    if [[ "$value" != "" ]]; then
        collectd_derive "$MAIN_NODE" "$STATS_NODE" "$value"
    fi
}

snmp_simple_gauge() {
    MAIN_NODE=$1
    STATS_NODE=$2
    SNMP_NODE=$3

    value=$(fetch_snmp "$SNMP_NODE")
    value=$(to_float "$value")

    if [[ "$value" != "" ]]; then
        collectd_gauge "$MAIN_NODE" "$STATS_NODE" "$value"
    fi
}

snmp_simple_absolute() {
    MAIN_NODE=$1
    STATS_NODE=$2
    SNMP_NODE=$3

    value=$(fetch_snmp "$SNMP_NODE")
    value=$(to_int "$value")

    if [[ "$value" != "" ]]; then
        collectd_counter "$MAIN_NODE" "$STATS_NODE" "$value"
    fi
}

get_volume_usage () {
    NODE_LIST=$(search_snmp_id "1.3.6.1.2.1.25.2.3.1.3" "$1")

    if [[ -z "$NODE_LIST" ]]; then
        return
    fi

    for SNMP_NODE_ID in $NODE_LIST; do
         ITEM_ID=$(extract_last_node_id "$SNMP_NODE_ID")
         ITEM_NAME=$(fetch_snmp "1.3.6.1.2.1.25.2.3.1.3.${ITEM_ID}" | tr -d '/')

         snmp_simple_gauge "volume.${ITEM_NAME}" "blocksize" "1.3.6.1.2.1.25.2.3.1.4.${ITEM_ID}"

         snmp_simple_gauge "volume.${ITEM_NAME}" "used"      "1.3.6.1.2.1.25.2.3.1.6.${ITEM_ID}"
         snmp_simple_gauge "volume.${ITEM_NAME}" "capacity"  "1.3.6.1.2.1.25.2.3.1.5.${ITEM_ID}"
    done
}

get_drive_stats () {
    NODE_LIST=$(search_snmp_id "1.3.6.1.4.1.6574.2.1.1.2" "$1")

    if [[ -z "$NODE_LIST" ]]; then
        return
    fi

    for SNMP_NODE_ID in $NODE_LIST; do
        ITEM_ID=$(extract_last_node_id "$SNMP_NODE_ID")

        #Get Health Status
        snmp_simple_derive "disk${ITEM_ID}" "health"       "1.3.6.1.4.1.6574.2.1.1.5.${ITEM_ID}"

        #Get temperature
        snmp_simple_native "disk${ITEM_ID}" "temperature"  "1.3.6.1.4.1.6574.2.1.1.6.${ITEM_ID}"
    done
}

get_raid_stats () {
    NODE_LIST=$(search_snmp_id "1.3.6.1.4.1.6574.3" "")

    if [[ -z "$NODE_LIST" ]]; then
        return
    fi

    for SNMP_NODE_ID in $NODE_LIST; do
        ITEM_ID=$(extract_last_node_id "$SNMP_NODE_ID")

        #Get Health Status
        snmp_simple_derive "disk${ITEM_ID}" "health"       "1.3.6.1.4.1.6574.2.1.1.5.$ITEM_ID"

        #Get temperature
        snmp_simple_native "disk${ITEM_ID}" "temperature"  "1.3.6.1.4.1.6574.2.1.1.6.$ITEM_ID"
    done
}

get_sys_stats() {
    # System
    snmp_simple_native "system" "temperature" "1.3.6.1.4.1.6574.1.2.0"

    # Cpu
    snmp_simple_native "system" "cpu-user"      "1.3.6.1.4.1.2021.11.9.0"
    snmp_simple_native "system" "cpu-system"    "1.3.6.1.4.1.2021.11.10.0"
    snmp_simple_native "system" "cpu-idle"      "1.3.6.1.4.1.2021.11.11.0"

    # Load
    snmp_simple_multi "system" "load"           "1.3.6.1.4.1.2021.10.1.5.1" "1.3.6.1.4.1.2021.10.1.5.2" "1.3.6.1.4.1.2021.10.1.5.3"

    # Memory
    snmp_simple_native "system.memory" "swap-total"      "1.3.6.1.4.1.2021.4.3.0"
    snmp_simple_native "system.memory" "swap-avail"      "1.3.6.1.4.1.2021.4.4.0"

    snmp_simple_native "system.memory" "memory-total_real"  "1.3.6.1.4.1.2021.4.5.0"
    snmp_simple_native "system.memory" "memory-avail_real"  "1.3.6.1.4.1.2021.4.6.0"
    snmp_simple_native "system.memory" "memory-total_free"  "1.3.6.1.4.1.2021.4.11.0"
    snmp_simple_native "system.memory" "memory-shared"      "1.3.6.1.4.1.2021.4.13.0"
    snmp_simple_native "system.memory" "memory-buffer"      "1.3.6.1.4.1.2021.4.14.0"
    snmp_simple_native "system.memory" "memory-cached"      "1.3.6.1.4.1.2021.4.15.0"
}

get_ups_stats() {
    NODE_LIST=$(search_snmp_id "1.3.6.1.4.1.6574.4" "")

    if [[ -z "$NODE_LIST" ]]; then
        return
    fi

    snmp_simple_native "ups" "percent-load"            "1.3.6.1.4.1.6574.4.2.12.1"
    snmp_simple_native "ups" "percent-charge"          "1.3.6.1.4.1.6574.4.3.1.1"
    snmp_simple_native "ups" "percent-charge-warning"  "1.3.6.1.4.1.6574.4.3.1.4"
    snmp_simple_gauge  "ups" "battery-type"            "1.3.6.1.4.1.6574.4.3.12"
}

get_service_stats() {
    NODE_LIST=$(search_snmp_id "1.3.6.1.4.1.6574.6.1.1.2" "")

    if [[ -z "$NODE_LIST" ]]; then
        return
    fi

    for SNMP_NODE_ID in $NODE_LIST; do
        ITEM_ID=$(extract_last_node_id "$SNMP_NODE_ID")
        ITEM_NAME=$(fetch_snmp "1.3.6.1.4.1.6574.6.1.1.2.${ITEM_ID}")

        snmp_simple_native "service.${ITEM_NAME}" "users" "1.3.6.1.4.1.6574.6.1.1.3.${ITEM_ID}"
    done
}

get_net_stats() {
    NODE_LIST=$(search_snmp_id "1.3.6.1.2.1.31.1.1.1.1" "$1")

    if [[ -z "$NODE_LIST" ]]; then
        return
    fi

    for SNMP_NODE_ID in $NODE_LIST; do
        ITEM_ID=$(extract_last_node_id "$SNMP_NODE_ID")
        ITEM_NAME=$(fetch_snmp "1.3.6.1.2.1.31.1.1.1.1.${ITEM_ID}")

        snmp_simple_multi "network.${ITEM_NAME}" "if_octets"  "1.3.6.1.2.1.31.1.1.1.6.${ITEM_ID}" "1.3.6.1.2.1.31.1.1.1.10.${ITEM_ID}"
    done
}

get_storage_io_stats() {
    NODE_LIST=$(search_snmp_id "1.3.6.1.4.1.6574.101.1.1.1" "")

    if [[ -z "$NODE_LIST" ]]; then
        return
    fi

    for SNMP_NODE_ID in $NODE_LIST; do
        ITEM_ID=$(extract_last_node_id "$SNMP_NODE_ID")
        ITEM_NAME=$(fetch_snmp "1.3.6.1.4.1.6574.101.1.1.2.${ITEM_ID}")

        snmp_simple_multi "storageio.${ITEM_NAME}" "disk_ops-bytes" "1.3.6.1.4.1.6574.101.1.1.12.${ITEM_ID}" "1.3.6.1.4.1.6574.101.1.1.13.${ITEM_ID}"
        snmp_simple_multi "storageio.${ITEM_NAME}" "disk_ops-count" "1.3.6.1.4.1.6574.101.1.1.5.${ITEM_ID}"  "1.3.6.1.4.1.6574.101.1.1.6.${ITEM_ID}"
        snmp_simple_multi "storageio.${ITEM_NAME}" "load"           "1.3.6.1.4.1.6574.101.1.1.9.${ITEM_ID}"  "1.3.6.1.4.1.6574.101.1.1.10.${ITEM_ID}" "1.3.6.1.4.1.6574.101.1.1.11.${ITEM_ID}"
    done
}

get_space_io_stats() {
    NODE_LIST=$(search_snmp_id "1.3.6.1.4.1.6574.102.1.1.2" "$1")

    if [[ -z "$NODE_LIST" ]]; then
        return
    fi

    for SNMP_NODE_ID in $NODE_LIST; do
        ITEM_ID=$(extract_last_node_id "$SNMP_NODE_ID")
        ITEM_NAME=$(fetch_snmp "1.3.6.1.4.1.6574.102.1.1.2.${ITEM_ID}")

        snmp_simple_multi "space.${ITEM_NAME}" "disk_ops-bytes" "1.3.6.1.4.1.6574.102.1.1.12.${ITEM_ID}" "1.3.6.1.4.1.6574.101.1.1.13.${ITEM_ID}"
        snmp_simple_multi "space.${ITEM_NAME}" "disk_ops-count" "1.3.6.1.4.1.6574.102.1.1.5.${ITEM_ID}"  "1.3.6.1.4.1.6574.102.1.1.6.${ITEM_ID}"
        snmp_simple_multi "space.${ITEM_NAME}" "load"           "1.3.6.1.4.1.6574.102.1.1.9.${ITEM_ID}"  "1.3.6.1.4.1.6574.102.1.1.10.${ITEM_ID}" "1.3.6.1.4.1.6574.102.1.1.11.${ITEM_ID}"
    done
}


collectd_translate_name() {
  key="$*"
  key=${key//./-}
  key=${key//\//-}
  key=${key// /_}
  echo "$key"
}

collectd_native() {
	MAIN_NAME=$(collectd_translate_name "$1")
	VAR_NAME=$(collectd_translate_name "$2")
	VAR_VALUE=$3
	echo "PUTVAL \"${HOSTNAME}/synology-${MAIN_NAME}/${VAR_NAME}\" interval=$INTERVAL N:$VAR_VALUE"
}

collectd_gauge() {
	MAIN_NAME=$(collectd_translate_name "$1")
	VAR_NAME=$(collectd_translate_name "$2")
	VAR_VALUE=$3
	echo "PUTVAL \"${HOSTNAME}/synology-${MAIN_NAME}/gauge-${VAR_NAME}\" interval=$INTERVAL N:$VAR_VALUE"
}

collectd_derive() {
	MAIN_NAME=$(collectd_translate_name "$1")
	VAR_NAME=$(collectd_translate_name "$2")
	VAR_VALUE=$3
	echo "PUTVAL \"${HOSTNAME}/synology-${MAIN_NAME}/derive-${VAR_NAME}\" interval=$INTERVAL N:$VAR_VALUE"
}

collectd_absolute() {
	MAIN_NAME=$(collectd_translate_name "$1")
	VAR_NAME=$(collectd_translate_name "$2")
	VAR_VALUE=$3
	echo "PUTVAL \"${HOSTNAME}/synology-${MAIN_NAME}/COUNTER-${VAR_NAME}\" interval=$INTERVAL N:$VAR_VALUE"
}

main() {
    UPDATE_TIME=$(date +%s)

    get_sys_stats
    get_service_stats
    get_ups_stats
    get_net_stats        "\"(eth|sit)"
    get_drive_stats      "\"Disk[ 0-9]+\""
    get_raid_stats
    get_storage_io_stats
    get_volume_usage     "\"/volume[ 0-9]+\""

    UPDATE_TIME=$(($(date +%s)-UPDATE_TIME))
    collectd_derive "update" "update-time" "$UPDATE_TIME"
}

# first run
main $@

# loop'ed run
while sleep "$INTERVAL"
        main $@
done
