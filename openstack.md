```
                           ┌───────────────────────────┐
                           │        Horizon             │
                           │   Web Dashboard (UI)       │
                           └─────────────┬─────────────┘
                                         │
                                         ▼
┌────────────────────────────────────────────────────────────────────┐
│                        Keystone (Identity)                           │
│            Authentication • Authorization • Service Catalog          │
└─────────────┬───────────────┬───────────────┬───────────────┬──────┘
              │               │               │               │
              ▼               ▼               ▼               ▼
┌───────────────┐   ┌────────────────┐   ┌──────────────┐   ┌───────────────┐
│     Nova      │   │    Neutron     │   │    Glance    │   │   Octavia     │
│ Compute API   │   │ Networking API │   │ Image Store │   │ Load Balancer │
└───────┬───────┘   └───────┬────────┘   └──────┬──────┘   └───────┬───────┘
        │                   │                   │                  │
        │                   │                   │                  │
        ▼                   ▼                   ▼                  ▼
┌───────────────┐   ┌────────────────┐   ┌──────────────┐   ┌───────────────┐
│    Ironic     │   │  Virtual /     │   │ VM & Bare    │   │ Traffic Mgmt  │
│ Bare Metal    │   │  Provider Nets │   │ Metal Images │   │ (L7 / L4)     │
│ Provisioning  │   └────────────────┘   └──────────────┘   └───────────────┘
└───────────────┘


┌────────────────────────────────────────────────────────────────────┐
│                           Storage Services                          │
└────────────────────────────────────────────────────────────────────┘
              │               │               │
              ▼               ▼               ▼
┌───────────────┐   ┌───────────────┐   ┌───────────────┐
│     Swift     │   │    Cinder     │   │    Manila     │
│ Object Store  │   │ Block Storage │   │ File Shares  │
│ (S3-like)     │   │ (VM Volumes)  │   │ (NFS/SMB)    │
└───────────────┘   └───────────────┘   └───────────────┘


┌────────────────────────────────────────────────────────────────────┐
│                          Workloads                                  │
│  • Virtual Machines (Nova)                                           │
│  • Bare Metal Nodes (Ironic)                                         │
│  • Attached Volumes (Cinder)                                         │
│  • Object Storage (Swift)                                            │
│  • Shared Filesystems (Manila)                                       │
│  • Load-Balanced Apps (Octavia)                                      │
└────────────────────────────────────────────────────────────────────┘

```
