#!/bin/bash
# Description: Netperf Benchmark với IP cố định cho từng Namespace

# --- Variables ---
DURATION=60        
NS_PREFIX="ns"
CONFIDENCE="-I 99,2.5"

# Định nghĩa IP cố định cho từng Namespace index
# index 0 tương ứng ns0, index 1 tương ứng ns1...
DECLARE_IPS=("192.168.50.10" "192.168.50.20")

# Cấu hình cặp (Pairing configuration)
# Cặp 0: ns0 (Client) -> ns1 (Server)
CLIENTS=(0)
SERVERS=(1)

# Dọn dẹp netserver cũ
killall netserver > /dev/null 2>&1

echo ">>> Preparation: Starting Servers..."
for s_idx in "${SERVERS[@]}"; do
    ns_server="${NS_PREFIX}${s_idx}"
    echo "Starting netserver in $ns_server..."
    ip netns exec $ns_server netserver > /dev/null 2>&1
done

sleep 2 

echo ">>> Benchmark: Starting Clients..."
echo "-----------------------------------------------------------"

# [BẮT ĐẦU ĐO CPU]
# sar 1 $((DURATION - 5)) | grep "Average" | awk '{print "\n[RESULT] Average CPU Idle: "$8"%"}' &

# [KÍCH HOẠT CÁC CẶP]
for i in "${!CLIENTS[@]}"; do
    c_idx=${CLIENTS[$i]}
    s_idx=${SERVERS[$i]}
    
    ns_client="${NS_PREFIX}${c_idx}"
    ns_server="${NS_PREFIX}${s_idx}"
    server_ip="${DECLARE_IPS[$s_idx]}" # Lấy IP của server từ mảng đã fix

    echo "Pairing: $ns_client -> $ns_server ($server_ip)"
    
    # Chạy netperf
    ip netns exec $ns_client netperf -H $server_ip -l $DURATION -t TCP_STREAM -c -C $CONFIDENCE &
done

# Chờ hoàn thành
wait

echo "-----------------------------------------------------------"
echo ">>> Finished testing."

# Dọn dẹp
killall netserver
echo ">>> Cleaned up netservers."
