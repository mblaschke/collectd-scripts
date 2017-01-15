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
    snmpwalk -v 2c -c public "$HOSTNAME" "$1" |grep -e "$2" | cut -f 1 -d '=' | xargs
}

snmp_simple_value() {
    STATS_NODE=$1
    SNMP_NODE=$2

    value=$(fetch_snmp $SNMP_NODE)
    if [[ "$value" -gt 0 ]]; then
        send_data "$STATS_NODE" "$value"
    fi
}

get_volume_usage () {
    VOLUME_NAME="$1"
    VOLUME_PATH="$2"
    SNMP_NODE_ID=$(search_snmp_id "1.3.6.1.2.1.25.2.3.1.3" "$VOLUME_PATH")

    VOLUME_NODE_ID=$(echo $SNMP_NODE_ID | rev | cut -d. -f1 | rev)

    snmp_simple_value "volume.${VOLUME_NAME}.used"      "1.3.6.1.2.1.25.2.3.1.6.${VOLUME_NODE_ID}"
    snmp_simple_value "volume.${VOLUME_NAME}.capacity"  "1.3.6.1.2.1.25.2.3.1.5.${VOLUME_NODE_ID}"
    snmp_simple_value "volume.${VOLUME_NAME}.blocksize" "1.3.6.1.2.1.25.2.3.1.4.${VOLUME_NODE_ID}"
}

get_drive_temps () {
    counter=0
    while [  "$counter" -lt "$DRIVE_COUNT" ]; do
        #Get Drive Name
        syno_drivename=$(fetch_snmp 1.3.6.1.4.1.6574.2.1.1.2.$counter)
        if [[ "$syno_drivename" == *"exists"* ]]; then
            let counter=counter+1
        	continue
        fi

        syno_drivename=$(echo $syno_drivename | cut -c 10-)
        syno_drivename=${syno_drivename// /_}

        #Get Health Status
        snmp_simple_value "disk${counter}.health"      "1.3.6.1.4.1.6574.2.1.1.5.$counter"

        #Get temperature
        snmp_simple_value "disk${counter}.temperature"      "1.3.6.1.4.1.6574.2.1.1.6.$counter"

        let counter=counter+1
    done
}

get_sys_stats() {
    # System
    snmp_simple_value "system.temperature" "1.3.6.1.4.1.6574.1.2.0"

    # Cpu
    snmp_simple_value "cpu.user"      "1.3.6.1.4.1.2021.11.9.0"
    snmp_simple_value "cpu.system"    "1.3.6.1.4.1.2021.11.10.0"
    snmp_simple_value "cpu.idle"      "1.3.6.1.4.1.2021.11.11.0"

    # Load
    snmp_simple_value "load.1"      "1.3.6.1.4.1.2021.10.1.5.1"
    snmp_simple_value "load.5"      "1.3.6.1.4.1.2021.10.1.5.2"
    snmp_simple_value "load.15"     "1.3.6.1.4.1.2021.10.1.5.3"

    # Memory
    snmp_simple_value "memory.swap_total"      "1.3.6.1.4.1.2021.4.3.0"
    snmp_simple_value "memory.swap_avail"      "1.3.6.1.4.1.2021.4.4.0"
    snmp_simple_value "memory.mem_total"       "1.3.6.1.4.1.2021.4.5.0"
    snmp_simple_value "memory.mem_total_real"  "1.3.6.1.4.1.2021.4.5.0"
    snmp_simple_value "memory.mem_avail_real"  "1.3.6.1.4.1.2021.4.6.0"
    snmp_simple_value "memory.mem_total_free"  "1.3.6.1.4.1.2021.4.11.0"
    snmp_simple_value "memory.mem_shared"      "1.3.6.1.4.1.2021.4.13.0"
    snmp_simple_value "memory.mem_buffer"      "1.3.6.1.4.1.2021.4.14.0"
    snmp_simple_value "memory.mem_cached"      "1.3.6.1.4.1.2021.4.15.0"
}

get_net_stats() {
    counter=1
    while [  $counter -lt "$NETWORK_COUNT" ]; do
        #Get Drive Name
        net_ifname=$(fetch_snmp 1.3.6.1.2.1.31.1.1.1.1.$counter)
        if [[ "$net_ifname" == *"exists"* ]]; then
            break
        fi

        net_rx=$(fetch_snmp 1.3.6.1.2.1.31.1.1.1.6.$counter)
        net_tx=$(fetch_snmp 1.3.6.1.2.1.31.1.1.1.10.$counter)

        if [[ "$net_rx" -le 0 || "$net_tx" -le 0 ]]; then
            true
        else
            send_data_counter "network.${net_ifname}.rx"  "$net_rx"
            send_data_counter "network.${net_ifname}.tx"  "$net_tx"
        fi

        let counter=counter+1
    done
}

send_data() {
	VAR_NAME=${1//./_}
	VAR_VALUE=$2
	echo "PUTVAL \"$HOSTNAME/synology/gauge-$VAR_NAME\" interval=$INTERVAL N:$VAR_VALUE"
}

send_data_counter() {
	VAR_NAME=${1//./_}
	VAR_VALUE=$2
	echo "PUTVAL \"$HOSTNAME/synology/counter-$VAR_NAME\" interval=$INTERVAL N:$VAR_VALUE"
}

main() {
    get_sys_stats
    get_net_stats
    get_drive_temps
    get_volume_usage "volume1" "\"/volume1\""
    get_volume_usage "volume2" "\"/volume2\""
    get_volume_usage "volume3" "\"/volume3\""
}

main
