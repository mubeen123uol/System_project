# Multi-Site Resilient & Automated Kubernetes Platform (Part 1)

## Executive Summary
This project implements **Part 1: Build a Multi-Site, Fully Automated, Highly Available Platform**.
The core goal is to architect and provision a resilient multi-site network and a multi-node Kubernetes cluster that is **deployed, managed, and rebuilt entirely from code**.

---

## Architecture Overview

```
                                  +-------------------------------------+
                                  |    Global Edge Load Balancer (LB)   |
                                  |       HAProxy (Port 80 & 8404)      |
                                  +------------------+------------------+
                                                     |
                         +---------------------------+---------------------------+
                         |                                                       |
        +----------------v----------------+                     +----------------v----------------+
        |             SITE A              |                     |             SITE B              |
        |      (Primary Data Center)      |<=== WAN Gateway ===>|  (Disaster Recovery Data Center)|
        |     Subnet: 172.28.10.0/24      |  (15ms latency sim) |     Subnet: 172.28.20.0/24      |
        |                                 |                     |                                 |
        |  - Worker 1: site-a-worker1     |                     |  - Worker 3: site-b-worker1     |
        |  - Worker 2: site-a-worker2     |                     |  - Worker 4: site-b-worker2     |
        |  - Replicas: HA Pods (Site-A)   |                     |  - Replicas: HA Pods (Site-B)   |
        +---------------------------------+                     +---------------------------------+
```

### Key Architectural Components

1. **Multi-Site Resilient Network:**
   - **Site-A LAN:** `172.28.10.0/24` representing the Primary Data Center.
   - **Site-B LAN:** `172.28.20.0/24` representing the Disaster Recovery Data Center.
   - **WAN Interconnect:** `172.28.0.0/24` with Linux kernel IP forwarding, custom iptables inter-site filtering, and `tc netem` simulated WAN propagation latency (15ms).

2. **Multi-Node Kubernetes Platform:**
   - 5-Node Kubernetes cluster orchestrated via KinD.
   - 1 Control Plane + 4 Workers (2 partitioned into `site-a` and 2 partitioned into `site-b`).
   - Dynamic topology labels applied at node registration: `topology.kubernetes.io/zone=site-a` and `topology.kubernetes.io/zone=site-b`.

3. **High-Availability (HA) Application Workload:**
   - **Topology Spread Constraints:** Enforces `maxSkew: 1` across `topology.kubernetes.io/zone` to guarantee equal pod allocation across both data centers.
   - **Pod Anti-Affinity:** Prevents pod colocation on identical worker nodes.
   - **Pod Disruption Budget (PDB):** Enforces a minimum of 2 available pods at all times.
   - **Liveness & Readiness Probes:** Actively monitors container health on `/healthz`.

4. **Global Edge Traffic Management (HAProxy):**
   - Active Layer-7 health check probes (`inter 2s fall 2 rise 2`) continuously probing all site worker endpoints.
   - Automatic failover: When Site-A experiences degradation or total failure, 100% of traffic is automatically directed to Site-B with zero dropped connections.
   - Live statistics and health telemetry available at `/stats` (port 8404).

---

## Repository Structure

```
.
├── config/
│   └── multi-site-cluster.yaml    # KinD 5-node multi-zone cluster specification
├── manifests/
│   ├── 01-namespace.yaml          # ha-platform namespace
│   ├── 02-app-config.yaml         # Python 3 Multi-Site HA server & live UI
│   ├── 03-ha-deployment.yaml      # HA Deployment with topology spread & anti-affinity
│   ├── 04-service.yaml            # NodePort service on port 30080
│   └── 05-poddisruptionbudget.yaml# Pod Disruption Budget
├── lb/
│   ├── haproxy.cfg.template       # Dynamic configuration template for edge LB
│   └── haproxy.cfg                # Generated active configuration
├── network/
│   └── setup_multisite_net.sh     # Multi-site network, WAN latency, and routing setup
├── scripts/
│   ├── install_tools.sh           # Prerequisite validation & installer
│   ├── deploy.sh                  # Single-command end-to-end deployment
│   ├── teardown.sh                # Clean resource destruction
│   ├── rebuild.sh                 # Full teardown and rebuild entirely from code
│   └── test_resilience.sh         # Automated chaos testing and failover verification
└── README.md                      # Complete system documentation
```

---

## Quick Start & Usage

### 1. Deploy the Entire Platform from Code
Run the single automated deployment script:
```bash
chmod +x scripts/*.sh network/*.sh
./scripts/deploy.sh
```

### 2. Verify Endpoints
* **Web UI (Edge Gateway):** `http://<VM_IP>/` (e.g., `http://192.168.138.128/` or `http://localhost/`)
* **Health API:** `http://<VM_IP>/healthz`
* **HAProxy Live Stats Dashboard:** `http://<VM_IP>:8404/stats`

### 3. Rebuild Entirely from Code (IaC Test)
To verify that the entire platform can be destroyed and reconstructed with zero manual intervention:
```bash
./scripts/rebuild.sh
```

### 4. Execute Failover & Resilience Chaos Testing
To simulate a complete failure of Site-A and observe automatic zero-downtime failover and recovery:
```bash
./scripts/test_resilience.sh
```
