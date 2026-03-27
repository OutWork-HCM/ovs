# TODO:

## INTEL Network Adapter
- [ ] On Linux Mint with same Intel E810 NIC, check hw-tc-offload info with `ethtool -k <interface>` (check all PF, VFs and Representors) and `devlink dev eswitch show <interface>`.

On Proxmox with Intel E810 NIC, the info is as follows:

```yaml
PROXMOX 8.4-1

root@pve /usr/local/bin $ devlink dev eswitch show pci/0000:01:00.0 
pci/0000:01:00.0: mode switchdev

root@pve /usr/local/bin $ ip link show enp1s0f0np0
4: enp1s0f0np0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 8996 qdisc mq master ovs-system state UP mode DEFAULT group default qlen 1000
    link/ether 6c:fe:54:40:c9:c0 brd ff:ff:ff:ff:ff:ff
    vf 0     link/ether 0e:14:8f:ad:e2:88 brd ff:ff:ff:ff:ff:ff, spoof checking on, link-state enable, trust off
    vf 1     link/ether 22:d9:5d:58:68:c5 brd ff:ff:ff:ff:ff:ff, spoof checking on, link-state enable, trust off
    vf 2     link/ether fe:b7:34:c9:41:bc brd ff:ff:ff:ff:ff:ff, spoof checking on, link-state enable, trust off
    vf 3     link/ether 8e:df:f9:c6:1d:01 brd ff:ff:ff:ff:ff:ff, spoof checking on, link-state enable, trust off

root@pve /usr/local/bin $ ethtool -k enp1s0f0npf0vf0 | grep hw-tc
hw-tc-offload: on

root@pve /usr/local/bin $ ethtool -k enp1s0f0v2 | grep hw-tc
hw-tc-offload: off [fixed]

root@pve /usr/local/bin $ ethtool -k enp1s0f0npf0vf0 | grep hw-tc
hw-tc-offload: on
```

- [ ] Check for any known issues with the Intel E810 NIC and hardware offload, especially related to interrupt handling and CPU load. For example, there are reports of high CPU usage on a single core due to ksoftirqd when using 100G network cards, which may be relevant:

https://forum.proxmox.com/threads/100g-network-card-and-interrupt-handling-ksoftirqd-process-loads-a-single-cpu-core-at-100.167268/

