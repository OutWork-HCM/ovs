# Open vSwitch (OVS) Hardware Offload Benchmarking

This project provides a comprehensive suite of scripts for benchmarking Open vSwitch (OVS) performance, specifically focusing on comparing the legacy **Kernel Datapath** model with the **Hardware Offload (ASAP² / Intel ADQ)** model using:
- **Mellanox ConnectX-4 Lx**
- **Intel E810 (Columbiaville)**

## Overview

The primary goal is to **measure the maximum throughput** of the system using a **Single Server** topology (VF-to-VF communication).
- **Primary Tools:** `iperf3` (Throughput) and `netperf` (Transaction Rate/Latency).
- **Reference Tool:** `pktgen` (Kernel Packet Generator) is included for reference and stress testing but is not the primary metric.

Central to this project is the validation of Hardware Offload capabilities, which offload packet processing from the host CPU to the NIC hardware (eSwitch), offering significant performance gains even for traffic within the same host.

## Prerequisites

### Hardware
- **One Server:** (Single Node / DUT).
- **NIC:** 
  - **Single Port (Port 0)** is used for all VFs.
  - Mellanox ConnectX-4 Lx (or similar).
  - Intel E810 Series (Columbiaville).
- **Topology:** Loopback / Hairpin (VF <-> VF within the same NIC).

### Software
- **OS:** Linux (Ubuntu 20.04/22.04 recommended).
- **Kernel:** 5.4+ (for stable `switchdev` support).
- **Open vSwitch:** 2.13+ recommended.
- **Drivers:** 
  - **Mellanox:** MLNX_OFED (v5.0+ recommended) or upstream `mlx5_core`.
  - **Intel:** Intel Ethernet Adapter Complete Driver Pack (`ice` driver v1.x+ and matching firmware).
- **Tools:**
  - `iperf3` (Main Throughput Tool)
  - `netperf` (Latency/Transactions)
  - `pktgen` (Optional/Reference)
  - `sysstat` (for `sar` CPU monitoring)
  - `ethtool`, `iproute2`, `devlink`

## Project Structure

### Setup Scripts (Primary)
- **`setup_ovs_hw_offload_nvf.sh`**: **(Main)** Configures OVS and the NIC for Hardware Offload with multiple VFs (NVF) on a **Single Port**.
  - Handles SR-IOV, switchdev mode, and OVS bridge configuration.
  - Creates multiple Namespaces (`ns0`, `ns1`...) and assigns VFs to them.
  - Supports Intel E810 and Mellanox ConnectX-4 Lx.

### Benchmarking Scripts (Primary)
- **`bench_ovs_with_iperf3_nvf_v2.sh`**: **(Main)** Throughput testing using `iperf3`.
  - Runs parallel `iperf3` sessions between VFs/Namespaces on the same host.
- **`bench_ovs_with_netperf_nvf.sh`**: **(Main)** Performance testing using `netperf`.
  - Measures transaction rates (TCP_RR/UDP_RR) and latency between VFs.

### Other Scripts
- **`bench_ovs_with_pktgen_*.sh`**: Packet generation tests (Reference only).
- **`setup_ovs_legacy.sh`**: Configures OVS for standard **Kernel Datapath** (No Offload).
- **`OpenVSwith_on_LX4.md`**: Detailed setup guide.
- **`Report.md`**: Logs and results.

## Usage

### 1. Setup Environment
Run the main setup script to prepare the environment for Hardware Offload:

```bash
sudo ./setup_ovs_hw_offload_nvf.sh
```
*This configures VFs on Port 0 and creates namespaces.*

### 2. Configure Benchmarks
Open the desired benchmark script (e.g., `bench_ovs_with_iperf3_nvf_v2.sh`) and review the configuration:

```bash
DURATION=20
SERVER_IP_PREFIX="192.168.50"
# Ensure the script targets the namespaces created by the setup script
```

### 3. Run Throughput Tests
Execute the main `iperf3` benchmark:

```bash
sudo ./bench_ovs_with_iperf3_nvf_v2.sh
```

### 4. Run Netperf Tests
Execute the `netperf` benchmark:

```bash
sudo ./bench_ovs_with_netperf_nvf.sh
```

## Troubleshooting
If Offload performance is lower than expected:
1.  Verify the setup script ran successfully (`setup_ovs_hw_offload_nvf.sh`).
2.  Check for `in_hw` in `tc` rules: `tc -s filter show dev <REPRESENTOR> ingress`.
3.  Ensure `iperf3` is running on the correct namespaces/VFs.
4.  Monitor CPU usage with `htop` or `sar`. High CPU usage on the host usually means traffic is NOT offloaded.
