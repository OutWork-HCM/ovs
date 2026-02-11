#!/bin/bash
# bench_ovs_with_iperf3_nvf.sh
# Parallel Benchmark Script for OVS using iperf3 and Linux Network Namespaces
#
# This script benchmarks Open vSwitch (OVS) by running parallel iperf3 client-server pairs
# across multiple network namespaces (VFs). It automates server/client launching, CPU usage
# measurement, and result reporting.
#
# Usage:
#   - Adjust NUM_VFs to set the number of virtual functions (must be even).
#   - Ensure network namespaces and IPs are pre-configured.
#   - Run as root for namespace operations.

# --- Variables ---
NUM_VFs=4          # Number of Virtual Functions (VFs) / network namespaces (must be even)
DURATION=60        # Duration of each iperf3 test in seconds
IP_BASE="192.168.50" # Base IP for server assignment
NS_PREFIX="ns"     # Prefix for network namespace names

# Calculate number of client-server pairs
NUM_PAIRS=$((NUM_VFs / 2))

# Function: start_server
# Starts an iperf3 server in a given namespace, exits after one session.
# Arguments:
#   $1 - Server index (namespace is derived from this)
function start_server() {
    local s_idx=$1
    local ns_server="${NS_PREFIX}${s_idx}"
    # Run iperf3 server, exit after one client (-1)
    ip netns exec $ns_server iperf3 -s -1 > /dev/null 2>&1 &
}

# Function: start_client
# Starts an iperf3 client in a given namespace, targeting a server namespace/IP.
# Arguments:
#   $1 - Client index (namespace)
#   $2 - Server index (namespace and IP)
function start_client() {
    local c_idx=$1
    local s_idx=$2
    local ns_client="${NS_PREFIX}${c_idx}"
    local server_ip="${IP_BASE}.$(($s_idx + 10))"

    echo "Pairing: $ns_client -> $ns_server ($server_ip)"
    ip netns exec $ns_client iperf3 -c $server_ip -t $DURATION &
}

echo ">>> Preparation: Starting $NUM_PAIRS Servers..."
# Servers are assigned to the upper half of the namespace range
for ((i=0; i<NUM_PAIRS; i++)); do
    s_idx=$((NUM_VFs - 1 - i))
    start_server $s_idx
done

sleep 2

echo ">>> Benchmark: Starting $NUM_PAIRS Clients simultaneously..."
echo "-----------------------------------------------------------"

# [CPU USAGE MEASUREMENT]
# Collects average CPU idle percentage during the test
sar 1 $((DURATION - 10)) | grep "Average" | awk '{print "\n[RESULT] Average CPU Idle: "$8"%"}' &

# [START CLIENT-SERVER PAIRS]
# Clients are assigned to the lower half of the namespace range
for ((i=0; i<NUM_PAIRS; i++)); do
    c_idx=$i
    s_idx=$((NUM_VFs - 1 - i))
    start_client $c_idx $s_idx
done

# Wait for all background jobs to finish
wait

echo "-----------------------------------------------------------"
echo ">>> Finished testing with $NUM_VFs VFs ($NUM_PAIRS pairs)."
