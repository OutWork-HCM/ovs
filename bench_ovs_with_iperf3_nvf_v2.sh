#!/bin/bash
# bench_ovs_with_iperf3_nvf_v2.sh
# Comprehensive Parallel Benchmark Script for OVS using iperf3 and Linux Network Namespaces
#
# This script benchmarks Open vSwitch (OVS) by running parallel iperf3 client-server pairs
# across multiple network namespaces (VFs). It automates server/client launching with CPU pinning,
# collects CPU usage statistics, parses iperf3 JSON output for detailed metrics, and generates
# both detailed and aggregated throughput reports.
#
# Usage:
#   - Adjust NUM_VFs to set the number of virtual functions (must be even).
#   - Ensure network namespaces and IPs are pre-configured.
#   - Run as root for namespace and sysctl operations.

# --- Variables ---
NUM_VFs=16          # Number of Virtual Functions (VFs) / network namespaces (must be even)
DURATION=60         # Duration of each iperf3 test in seconds
IP_BASE="192.168.50" # Base IP for server assignment
NS_PREFIX="ns"      # Prefix for network namespace names
LOG_DIR="/tmp/iperf_logs" # Directory to store iperf3 JSON logs
NUM_PAIRS=$((NUM_VFs / 2)) # Number of client-server pairs

# Prepare clean log directory
rm -rf $LOG_DIR && mkdir -p $LOG_DIR

# Function: start_server
# Starts an iperf3 server in a given namespace, pinned to a specific CPU core.
# Arguments:
#   $1 - Server index (namespace and CPU core are derived from this)
function start_server() {
    local s_idx=$1
    local ns_server="${NS_PREFIX}${s_idx}"
    # Server runs on even-numbered CPU cores (0, 2, 4...)
    local server_cpu=$(( (s_idx * 2) % 32 ))
    # Run iperf3 server, exit after one client (-1)
    ip netns exec $ns_server taskset -c $server_cpu iperf3 -s -1 > /dev/null 2>&1 &
}

# Function: start_client
# Starts an iperf3 client in a given namespace, targeting a server namespace/IP, with CPU pinning.
# Arguments:
#   $1 - Client index (namespace and CPU core)
#   $2 - Server index (namespace and IP)
function start_client() {
    local c_idx=$1
    local s_idx=$2
    local ns_client="${NS_PREFIX}${c_idx}"
    local server_ip="${IP_BASE}.$(($s_idx + 10))"
    # Client runs on odd-numbered CPU cores (1, 3, 5...)
    local client_cpu=$(( (c_idx * 2 + 1) % 32 ))

    echo "Pairing: $ns_client (CPU $client_cpu) -> $server_ip"
    # Run iperf3 client, output JSON for later parsing
    ip netns exec $ns_client taskset -c $client_cpu iperf3 -c $server_ip -t $DURATION --json > "${LOG_DIR}/client_${c_idx}.json" &
}

# Cleanup any old iperf3 processes
killall iperf3 > /dev/null 2>&1

echo ">>> Preparation: Starting $NUM_PAIRS Servers..."
# Start servers on the upper half of the namespace range
for ((i=0; i<NUM_PAIRS; i++)); do
    s_idx=$((NUM_VFs - 1 - i))
    start_server $s_idx
done

sleep 2

echo ">>> Benchmark: Starting $NUM_PAIRS Clients (Taskset enabled)..."
echo "-----------------------------------------------------------"
# Start CPU usage logging in the background
sar 1 $((DURATION - 5)) > /tmp/sar_cpu.log & 
SAR_PID=$!

# Launch all client-server pairs in parallel
for ((i=0; i<NUM_PAIRS; i++)); do
    start_client $i $((NUM_VFs - 1 - i))
done

# Wait for all iperf3 clients to finish
wait

echo "-----------------------------------------------------------"

# --- Extract and Summarize Results ---
FINAL_REPORT="iperf3_detailed_summary.log"
# Write CSV header to report
echo "Pair,Throughput(Gbps),Retransmits,Avg_RTT(ms),Max_CWND(KB)" > $FINAL_REPORT
echo "-----------------------------------------------------------" >> $FINAL_REPORT

TOTAL_BPS=0
COUNT=0

echo ">>> Processing logs and saving to $FINAL_REPORT..."
# --- CPU USAGE EXTRACTION ---
# Get average CPU idle percentage from sar log
CPU_IDLE=$(grep "Average" /tmp/sar_cpu.log | awk '{print $NF}' | tr ',' '.')
# Calculate CPU usage as 100 - idle
CPU_USAGE=$(echo "100 - $CPU_IDLE" | bc)

# Print CPU usage summary
echo -e "Average CPU Idle: \033[1;36m$CPU_IDLE%\033[0m"
echo -e "Average CPU Usage: \033[1;33m$CPU_USAGE%\033[0m"

# Process each iperf3 client JSON log for detailed metrics
for log in ${LOG_DIR}/*.json; do
    if [ -f "$log" ]; then
        # Extract throughput, retransmits, RTT, and max CWND using Python
        STATS=$(python3 -c "
import json
try:
    with open('$log') as f:
        d = json.load(f)
    end = d['end']['sum_sent']
    # RTT and CWND from first stream
    rtt = d['end']['streams'][0]['sender']['mean_rtt'] / 1000.0 # ms
    cwnd = d['end']['streams'][0]['sender']['max_snd_cwnd'] / 1024.0 # KB
    print(f\"{end['bits_per_second']:.0f}|{end['retransmits']}|{rtt:.2f}|{cwnd:.0f}\")
except:
    print('0|0|0|0')
")
        # Parse extracted stats
        IFS='|' read -r BW RETR RTT CWND <<< "$STATS"

        if [ "$BW" != "0" ]; then
            COUNT=$((COUNT + 1))
            TOTAL_BPS=$(echo "$TOTAL_BPS + $BW" | bc)
            PAIR_GBPS=$(echo "scale=2; $BW / 1000000000" | bc)

            # Write detailed result to report
            echo "Pair $COUNT,$PAIR_GBPS,$RETR,$RTT,$CWND" >> $FINAL_REPORT
            # Print summary to terminal
            echo "Pair $COUNT: $PAIR_GBPS Gbps | Retrans: $RETR | RTT: ${RTT}ms"
        fi
    fi
done

# Calculate and print total aggregated throughput
if [ $COUNT -gt 0 ]; then
    TOTAL_GBPS=$(echo "scale=2; $TOTAL_BPS / 1000000000" | bc)
    echo "-----------------------------------------------------------" >> $FINAL_REPORT
    echo "TOTAL AGGREGATED: $TOTAL_GBPS Gbps" >> $FINAL_REPORT

    echo -e "\n--- SUMMARY REPORT ---"
    echo "Total Throughput: $TOTAL_GBPS Gbps"
    echo "Detailed log saved to: $FINAL_REPORT"
fi

echo "-----------------------------------------------------------"
