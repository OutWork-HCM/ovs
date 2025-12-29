#### REF
[NVIDIA MLNX_OFED Documentation Rev 5.3-1.0.0.1](https://docs.nvidia.com/networking/display/mlnxofedv531001/ovs+offload+using+asap%C2%B2+direct#)

[OVS-Kernel SR-IOV Based Supported Operating Systems](https://docs.nvidia.com/networking/display/mlnxenv581011/general+support#src-99404587_GeneralSupport-OVS-KernelSR-IOVBasedSupportedOperatingSystems)

[OVS-DPDK SR-IOV Based Supported OSs](https://docs.nvidia.com/networking/display/mlnxenv581011/general+support#src-99404587_GeneralSupport-OVS-DPDKSR-IOVBasedSupportedOSs)

[ASAP2 Requirements](https://docs.nvidia.com/networking/display/mlnxenv581011/general+support#src-99404587_GeneralSupport-ASAP2Requirements)

[Supported NIC Firmware Versions](https://docs.nvidia.com/networking/display/mlnxenv581011/general+support#src-99404587_GeneralSupport-SupportedNICFirmwareVersions)

[Mellanox Adapters - Comparison Table](https://enterprise-support.nvidia.com/s/article/mellanox-adapters---comparison-table)

[Lets understand the openvswitch hardware offload!](https://hareshkhandelwal.blog/2020/03/11/lets-understand-the-openvswitch-hardware-offload/)

[Firmware Support and Downloads - Identifying Adapter Cards](https://network.nvidia.com/support/firmware/identification/)

```yaml
linux@tester03:~$ sudo -i
[sudo] password for linux:       
root@tester03:~# 
root@tester03:~# flint -d /dev/m
mapper/ mcelog  mei0    mem     mqueue/ mtd0    mtd0ro  
root@tester03:~# mst start        
Starting MST (Mellanox Software Tools) driver set
Loading MST PCI module - Success
Loading MST PCI configuration module - Success
Create devices
Unloading MST PCI module (unused) - Success
root@tester03:~# mst status
MST modules:
------------
    MST PCI module is not loaded
    MST PCI configuration module loaded

MST devices:
------------
/dev/mst/mt4117_pciconf0         - PCI configuration cycles access.
                                   domain:bus:dev.fn=0000:01:00.0 addr.reg=88 data.reg=92 cr_bar.gw_offset=-1
                                   Chip revision is: 00

root@tester03:~# flint -d /dev/mst/mt4117_pciconf0 q
Image type:            FS3
FW Version:            14.18.2030
FW Release Date:       20.4.2017
Product Version:       rel-14_18_2030
Rom Info:              type=UEFI version=14.12.27 cpu=AMD64
                       type=PXE version=3.5.110
Description:           UID                GuidsNumber
Base GUID:             9cdc71ffff556630        16
Base MAC:              9cdc71556630            16
Image VSD:             N/A
Device VSD:            N/A
PSID:                  HP_2420110034
Security Attributes:   N/A
```

[Online Firmware Upgrade Utility (Linux x86_64) for HPE Mellanox Ethernet only adapters](https://support.hpe.com/connect/s/softwaredetails?language=en_US&collectionId=MTX-5c045315a07d4577&tab=releaseNotes)


Our NIC
```bash
lspci -nn | grep -i Mellanox
```

```yaml
linux@tester03:~$ lspci -nn | grep -i Mellanox
01:00.0 Ethernet controller [0200]: Mellanox Technologies MT27710 Family [ConnectX-4 Lx] [15b3:1015]
```

```bash
ethtool -i enp1s0f0np0
```

```yaml
linux@tester03:~$ ethtool -i enp1s0f0np0
driver: mlx5_core
version: 6.5.0-14-generic
firmware-version: 14.18.2030 (HP_2420110034)
expansion-rom-version: 
bus-info: 0000:01:00.0
supports-statistics: yes
supports-test: yes
supports-eeprom-access: no
supports-register-dump: no
supports-priv-flags: yes
```

```bash
lspci -nnv -s 01:00.0
```

```yaml
linux@tester03:~$ lspci -nnv -s 01:00.0
01:00.0 Ethernet controller [0200]: Mellanox Technologies MT27710 Family [ConnectX-4 Lx] [15b3:1015]
	Subsystem: Hewlett Packard Enterprise MT27710 Family [ConnectX-4 Lx] [1590:00d4]
	Flags: bus master, fast devsel, latency 0, IRQ 16, IOMMU group 12
	Memory at 4a000000 (64-bit, prefetchable) [size=32M]
	Expansion ROM at 42700000 [disabled] [size=1M]
	Capabilities: <access denied>
	Kernel driver in use: mlx5_core
	Kernel modules: mlx5_core
```

```bash
ethtool -k enp1s0f0np0 | grep tc-offload
```

```yaml
linux@tester03:~$ ethtool -k enp1s0f0np0 | grep tc-offload
hw-tc-offload: off
```

```bash
sudo ethtool -K enp1s0f0np0 hw-tc-offload on && ethtool -k enp1s0f0np0 | grep tc-offload
```

```yaml
linux@tester03:~$ sudo ethtool -K enp1s0f0np0 hw-tc-offload on && ethtool -k enp1s0f0np0 | grep tc-offload
hw-tc-offload: on
```

```bash
dmesg | egrep -i 'iommu|dmar'
```

```yaml
linux@tester03:~$ dmesg | egrep -i 'iommu|dmar'
[    0.000000] Command line: BOOT_IMAGE=/boot/vmlinuz-6.5.0-14-generic root=UUID=a7ae2a0f-aa4e-43c6-ada8-78414cf7ba2c ro default_hugepagesz=1G hugepagesz=1G hugepages=4 quiet splash intel_iommu=on iommu=pt
[    0.018262] ACPI: DMAR 0x00000000350AB000 000088 (v02 INTEL  EDK2     00000002      01000013)
[    0.018312] ACPI: Reserving DMAR table memory at [mem 0x350ab000-0x350ab087]
[    0.154632] Kernel command line: BOOT_IMAGE=/boot/vmlinuz-6.5.0-14-generic root=UUID=a7ae2a0f-aa4e-43c6-ada8-78414cf7ba2c ro default_hugepagesz=1G hugepagesz=1G hugepages=4 quiet splash intel_iommu=on iommu=pt
[    0.154718] DMAR: IOMMU enabled
[    1.770630] DMAR: Intel(R) Virtualization Technology for Directed I/O
```

```yaml
linux@tester03:~$ cat /sys/class/net/enp1s0f0np0/device/sriov_totalvfs
4
```

```yaml
linux@tester03:~$ sudo lspci -vv -s 01:00.0 
01:00.0 Ethernet controller: Mellanox Technologies MT27710 Family [ConnectX-4 Lx]
	Subsystem: Hewlett Packard Enterprise MT27710 Family [ConnectX-4 Lx]
	Control: I/O- Mem+ BusMaster+ SpecCycle- MemWINV- VGASnoop- ParErr- Stepping- SERR- FastB2B- DisINTx+
	Status: Cap+ 66MHz- UDF- FastB2B- ParErr- DEVSEL=fast >TAbort- <TAbort- <MAbort- >SERR- <PERR- INTx-
	Latency: 0, Cache Line Size: 64 bytes
	Interrupt: pin A routed to IRQ 16
	IOMMU group: 12
	Region 0: Memory at 4a000000 (64-bit, prefetchable) [size=32M]
	Expansion ROM at 42700000 [disabled] [size=1M]
	Capabilities: [60] Express (v2) Endpoint, MSI 00
		LnkCap:	Port #0, Speed 8GT/s, Width x8, ASPM not supported
		LnkCap2: Supported Link Speeds: 2.5-8GT/s, Crosslink- Retimer- 2Retimers- DRS-
		LnkCtl2: Target Link Speed: 8GT/s, EnterCompliance- SpeedDis-
	Capabilities: [48] Vital Product Data
		Product Name: HPE Eth 10/25Gb 2p 640SFP28 Adptr
		Read-only fields:
			[PN] Part number: 817751-001
			[EC] Engineering changes: C-5712
			[SN] Serial number: IL27110584
			[V0] Vendor specific: PCIe GEN3 x8 10/25Gb 15W
			[V2] Vendor specific: 5712
			[V4] Vendor specific: 9CDC71556630
			[V5] Vendor specific: 0C
			[VA] Vendor specific: HP:V2=MFG:V3=FW_VER:V4=MAC:V5=PCAR
			[VB] Vendor specific: HPE ConnectX-4 Lx SFP28
			[V1] Vendor specific: 14.12.00.27     
			[YA] Asset tag: N/A                   
			[V3] Vendor specific: 14.18.20.30     
			[V6] Vendor specific: 03.05.01.10     
			[RV] Reserved: checksum good, 0 byte(s) reserved
		End
	Capabilities: [180 v1] Single Root I/O Virtualization (SR-IOV)
		IOVCap:	Migration-, Interrupt Message Number: 000
		IOVCtl:	Enable+ Migration- Interrupt- MSE+ ARIHierarchy+
		IOVSta:	Migration-
		Initial VFs: 4, Total VFs: 4, Number of VFs: 2, Function Dependency Link: 00
		VF offset: 2, stride: 1, Device ID: 1016

	Kernel driver in use: mlx5_core
	Kernel modules: mlx5_core
```


## 1. OVS Operational Modes for ConnectX-4 Lx

| *Mode*                           | *Processing Location*    | *Best For...*                       | *Performance*                    |
| -------------------------------- | ------------------------ | ----------------------------------- | -------------------------------- |
| **Standard OVS (Kernel)**        | Linux Kernel             | General purpose, simple setups.     | Lowest (CPU intensive).          |
| **OVS-DPDK**                     | User-space (PMD threads) | High throughput, low latency.       | High (uses dedicated CPU cores). |
| **OVS Hardware Offload (ASAP²)** | NIC eSwitch (Hardware)   | Maximum performance, zero CPU load. | Highest (Wire-speed).            |
Hardware Offload (ASAP²)

Mellanox's **Accelerated Switching and Packet Processing (ASAP²)** is the "holy grail" for CX-4 Lx. It allows the NIC's internal "eSwitch" to handle flow lookups and packet modifications (like VLAN tagging/stripping) without ever involving the host CPU - [OVS Offload Using ASAP² Direct](https://docs.nvidia.com/networking/display/mlnxofedv531001/ovs+offload+using+asap%C2%B2+direct#)
## 2. Key Capabilities & Limitations

It is critical to note that while the ConnectX-4 Lx supports hardware offloading, it has specific limitations compared to newer cards (like the CX-5 or CX-6):
- **VLAN Offload:** Fully supported in hardware.  
- **VXLAN/Tunneling:** The CX-4 Lx supports _stateless_ offloads (like checksum and RSS) for VXLAN, but it **cannot** offload the full encapsulation/decapsulation process to hardware via ASAP². Full tunnel offloading for OVS was introduced in the **ConnectX-5** series. [Offloading VXLAN Encapsulation/Decapsulation Actions](https://docs.nvidia.com/networking/display/mlnxofedv473290/ovs+offload+using+asap2+direct#src-19812087_safe-id-T1ZTT2ZmbG9hZFVzaW5nQVNBUDJEaXJlY3QtT2ZmbG9hZGluZ1ZYTEFORW5jYXBzdWxhdGlvbi9EZWNhcHN1bGF0aW9uQWN0aW9ucw)
- **Switchdev Model:** The CX-4 Lx supports the modern Linux `switchdev` model, which is the prerequisite for OVS hardware offloading.
- **SR-IOV:** It supports up to 256 Virtual Functions (VFs), allowing VMs to bypass the hypervisor for near-native networking.
- **Feature Conflicts** (RoCE vs. Tunneling): Hardware-offloaded tunneling on the CX-4 Lx is managed via the FDB (Forwarding Database). If this is enabled, **RoCE (RDMA over Converged Ethernet)** cannot be used simultaneously.
## 3. Required Versions for ConnectX-4 LX
| **Component**          | **Minimum Version** | **Recommended Version**         |
| ---------------------- | ------------------- | ------------------------------- |
| **Firmware**           | **14.21.0338**      | **14.32.1010** (or later)       |
| **MLNX_OFED Driver**   | **4.4**             | **5.0** (or later)              |
| **Open vSwitch (OVS)** | **2.8.0**           | **2.13+** (for stability)       |
| **Linux Kernel**       | **4.12**            | **5.4+** (for `switchdev` mode) |
| **iproute2**           | **4.12**            | Latest for your OS              |
### **Official Documentation Links**

NVIDIA (formerly Mellanox) provides these requirements across two primary technical pages:

1. **[NVIDIA MLNX_OFED General Support Matrix](https://docs.nvidia.com/networking/display/mlnxenv581011/general+support)** This link shows the **"Supported NIC Firmware Versions"** table. For the ConnectX-4 Lx, it explicitly lists **14.32.1010** as the current recommended firmware for the LTS driver branch.
    
2. **[OVS Offload Using ASAP² Direct Requirements](https://docs.nvidia.com/networking/display/mlnxofedv531001/ovs+offload+using+asap%C2%B2+direct)** This page details the software stack requirements. Under the **"Installing OVS-Kernel ASAP² Packages"** section, it specifies that **MLNX_OFED v4.4 and above** is required for the complete solution.

## Test Plan

To provide a rigorous performance evaluation of **Open vSwitch (OVS)** on the **ConnectX-4 Lx (CX-4 Lx)**, your test plan must distinguish between the **Kernel Datapath** (CPU-heavy) and **Hardware Offload (ASAP²)**.

Because the CX-4 Lx has specific hardware limits (VLAN vs. VXLAN), this plan is designed to find the "breaking point" of the card.

---

### Phase 1: Environment & Hardware Setup

#### 1. Topology Requirements

- **Two Identical Servers:**
    
    - **Node A (DUT):** Device Under Test (where OVS is configured).
        
    - **Node B (TG):** Traffic Generator.
        
- **Connectivity:** Direct connection via DAC cable or Fiber (10G/25G/40G/50G depending on your CX-4 Lx model).
    
- **BIOS Settings:**
    
    - Enable **VT-d / IOMMU**.
        
    - Enable **SR-IOV Support**.
        
    - Set PCIe Gen3 x8 (ensure the slot provides full bandwidth).
        

#### 2. Software Stack (Verified for CX-4 Lx)

- **OS:** Ubuntu 22.04 LTS (Kernel 5.15+).
    
- **Firmware:** 14.32.1010 or newer.
    
- **Driver:** MLNX_OFED 5.0 or newer.
    
- **OVS:** version 2.17+ (Ubuntu default is sufficient).
    

---

### Phase 2: Implementation Workflow (The Setup)

Run these steps on **Node A (DUT)** to enable the Hardware Offload environment.

#### Step 1: Enable SR-IOV and Switchdev

Bash

```
# 1. Enable 4 Virtual Functions
echo 4 > /sys/class/net/enp3s0f0/device/sriov_numvfs

# 2. Get PCI Address
PCI_ADDR=$(ethtool -i enp3s0f0 | grep bus-info | awk '{print $2}')

# 3. Unbind VFs to allow mode change
for vf in $(ls /sys/class/net/enp3s0f0/device/virtfn* -d | xargs -n1 readlink -f | xargs -n1 basename); do
    echo $vf > /sys/bus/pci/drivers/mlx5_core/unbind
done

# 4. Set to Switchdev mode (The ASAP2 requirement)
devlink dev eswitch set pci/$PCI_ADDR mode switchdev

# 5. Re-bind VFs
for vf in $(ls /sys/class/net/enp3s0f0/device/virtfn* -d | xargs -n1 readlink -f | xargs -n1 basename); do
    echo $vf > /sys/bus/pci/drivers/mlx5_core/bind
done
```

#### Step 2: Configure OVS with Offload

Bash

```
# Enable HW Offload in the OVS Database
ovs-vsctl set Open_vSwitch . other_config:hw-offload=true
systemctl restart openvswitch-switch

# Create Bridge and add the Physical PF and the VF Representor
ovs-vsctl add-br br-offload
ovs-vsctl add-port br-offload enp3s0f0      # Physical Port
ovs-vsctl add-port br-offload enp3s0f0v0    # VF 0 Representor
```

---

### Phase 3: Detailed Test Plan

#### Test Goal

To measure the impact of hardware offloading on **Throughput**, **Latency**, and **CPU Utilization** across different packet sizes.

| **Test ID** | **Scenario**               | **Logic**                              | **Expected Outcome**               |
| ----------- | -------------------------- | -------------------------------------- | ---------------------------------- |
| **T1**      | **Baseline (No OVS)**      | Traffic directly between two VFs.      | Maximum possible wire-speed.       |
| **T2**      | **OVS Kernel Mode**        | `hw-offload=false`. CPU handles flows. | High CPU usage, lower throughput.  |
| **T3**      | **OVS HW Offload (VLAN)**  | `hw-offload=true` using 802.1Q.        | **Best Performance** (Wire-speed). |
| **T4**      | **OVS HW Offload (VXLAN)** | `hw-offload=true` using VXLAN.         | **Bottle-neck** (CX-4 Lx limit).   |

---

#### Test Scenarios & Methodology

##### Scenario A: Throughput vs. Packet Size (IMIX)

- **Tool:** `TRex` (DPDK-based) or `iperf3` (Multiple streams).
    
- **Method:** Run traffic starting at 64B packets up to 1500B (Jumbo frames optional).
    
- **Metric:** Gbps and Packets Per Second (PPS).
    
- **Why:** CX-4 Lx offload is most noticeable at small packet sizes where the CPU usually struggles to keep up with the interrupt rate.
    

##### Scenario B: Latency Analysis

- **Tool:** `netperf` or `sockperf`.
    
- **Method:** Measure Round Trip Time (RTT) for 100,000 packets.
    
- **Metric:** 99th percentile latency (μs).
    
- **Why:** Hardware offload bypasses the kernel stack, which should reduce latency by 20–40%.
    

##### Scenario C: CPU "Tax" Measurement

- **Tool:** `mpstat -P ALL 1`.
    
- **Method:** Measure CPU load on Node A while pushing 10Gbps+ of traffic.
    
- **Metric:** %CPU consumption per core.
    
- **Why:** In T2 (Kernel), you will likely see 100% load on the OVS handler cores. In T3 (Offload), CPU load should drop to near 0%.
    

---

### Phase 4: Verification (Is it actually offloaded?)

Before you record data, you **must** verify the traffic isn't "cheating" and falling back to software.

1. Check OVS DPCTL:
    
    ovs-appctl dpctl/dump-flows -m type=offloaded
    
    If this returns empty while traffic is running, your offload is not working.
    
2. Check TC Filters:
    
    tc filter show dev enp3s0f0 ingress
    
    Look for the string in_hw or skip_sw.
    

---

### Phase 5: Reporting Template for Management

| **Scenario** | **Packet Size** | **Throughput** | **Latency (Avg)** | **CPU Load** |
| ------------ | --------------- | -------------- | ----------------- | ------------ |
| OVS Kernel   | 64B             | X Mpps         | Y μs              | 100%         |
| OVS Offload  | 64B             | **X+ Mpps**    | **Y- μs**         | **<5%**      |
| OVS Kernel   | 1500B           | 9.2 Gbps       | Z μs              | 40%          |
| OVS Offload  | 1500B           | **9.9 Gbps**   | **Z- μs**         | **<2%**      |

#### Final Recommendation for your Test

**Focus on the "Small Packet" test.** High-end NICs like the CX-4 Lx handle large packets easily even in software. The true value of OVS Offload is demonstrated when handling millions of small packets (64B) where the hardware can maintain wire-speed while the CPU remains idle.

