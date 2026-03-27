#!/bin/bash

# Tiêu đề bảng
printf "%-12s %-12s %-12s\n" "OVS_CPU" "KVM_CPU" "IDLE_CPU"
printf "%-12s %-12s %-12s\n" "------------" "------------" "------------"

while true; do
    # 1. Lấy dữ liệu từ /proc/stat
    stat1=$(grep '^cpu ' /proc/stat)

    # Chạy pidstat lấy dữ liệu trong 1 giây (vừa lấy data OVS/KVM, vừa tạo khoảng nghỉ để tính IDLE)
    data=$(pidstat -t 1 1 | grep -v "Average" | grep -v "UID")

    stat2=$(grep '^cpu ' /proc/stat)

    # 2. Tính toán IDLE_CPU bằng AWK (chính xác cho hệ thống nhiều CPU)
    idle_val=$(awk -v s1="$stat1" -v s2="$stat2" '
    BEGIN {
        split(s1, a); split(s2, b);

        # Tổng thời gian hệ thống (tất cả các cột từ 2 đến 11)
        for (i=2; i<=11; i++) {
            t1 += a[i];
            t2 += b[i];
        }

        # Thời gian rảnh rỗi (cột 5 là idle, cột 6 là iowait)
        id1 = a[5] + a[6];
        id2 = b[5] + b[6];

        # Tính phần trăm: (Chênh lệch rảnh / Chênh lệch tổng) * 100
        printf "%.1f", (id2 - id1) * 100 / (t2 - t1)
    }')

    # 3. Tính toán SUM cho OVS và KVM
    stats=$(echo "$data" | awk '
    BEGIN { ovs_sum=0; kvm_sum=0 }
    {
        cpu_val = $9
        if ($0 ~ /ksoftirqd/ && $0 ~ /\|__/) {
            ovs_sum += cpu_val
        }
        if (($0 ~ /kvm/ || $0 ~ /KVM/) && $0 ~ /\|__/) {
            kvm_sum += cpu_val
        }
    }
    END { printf "%.2f %.2f", ovs_sum, kvm_sum }
    ')

    ovs_total=$(echo $stats | cut -d' ' -f1)
    kvm_total=$(echo $stats | cut -d' ' -f2)

    # 4. Hiển thị kết quả
    printf "%-12s %-12s %-12s\n" "$ovs_total" "$kvm_total" "$idle_val%"
done
