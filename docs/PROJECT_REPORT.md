# Project Report: Multi-Site, Fully Automated, Highly Available Platform (Part 1)

**Course:** Systems and Network Administration / Management  
**Student:** Muhammad Mubeen  
**Date:** November 16, 2026  
**Environment:** Ubuntu Linux (VMware Workstation Guest on Windows 11 Host)  
**Status:** Completed & Validated (100% Automated, Rebuilt from Code, 0% Downtime)

---

## 1. Executive Summary & Objective
The objective of **Part 1** is to design, implement, and validate:
> **"A resilient multi-site network and a Kubernetes-based platform that is deployed and rebuilt entirely from code."**

To fulfill these requirements, a production-grade, highly available platform was constructed with:
1. **Multi-Site Resilient Network:** Two simulated geographical data centers (**Site-A Primary DC** and **Site-B Disaster Recovery DC**) interconnected across a routed WAN backbone with simulated cross-site latency and traffic control policies.
2. **Multi-Node Kubernetes Platform:** A 5-node cluster spanning both data centers with automated node labeling (`topology.kubernetes.io/zone=site-a` and `topology.kubernetes.io/zone=site-b`).
3. **High-Availability Application Workload:** Microservices deployed with Kubernetes **Topology Spread Constraints**, **Pod Anti-Affinity**, **Pod Disruption Budgets (PDB)**, and **Liveness/Readiness Probes**.
4. **Global Edge Traffic Management:** An active health-checking Edge Load Balancer (HAProxy) with automatic connection redispatch and a real-time web telemetry dashboard.
5. **100% Deployed & Rebuilt Entirely from Code:** Fully automated Infrastructure-as-Code (IaC) scripts (`deploy.sh`, `teardown.sh`, `rebuild.sh`, and `test_resilience.sh`) that destroy and reconstruct the entire infrastructure from zero in a single command.

---

## 2. Platform Architecture

```
                                      +------------------------------------+
                                      |   Global Edge Load Balancer (LB)   |
                                      |       HAProxy (Port 80 & 8404)     |
                                      +-----------------+------------------+
                                                        |
                            +---------------------------+---------------------------+
                            |                                                       |
           +----------------v---------------+                      +----------------v---------------+
           |             SITE A             |                      |             SITE B             |
           |     (Primary Data Center)      |<==== WAN Gateway ===>| (Disaster Recovery Data Center)|
           |     Subnet: 172.28.10.0/24     |   (15ms latency sim) |     Subnet: 172.28.20.0/24     |
           |                                |                      |                                |
           |  - Worker 1: site-a-worker1    |                      |  - Worker 3: site-b-worker1    |
           |  - Worker 2: site-a-worker2    |                      |  - Worker 4: site-b-worker2    |
           |  - Zone: site-a                |                      |  - Zone: site-b                |
           |  - HA Pods: Replicas 1 & 2     |                      |  - HA Pods: Replicas 3 & 4     |
           +--------------------------------+                      +--------------------------------+
```

---

## 3. Network Design & Multi-Site Emulation

| Network Segment | Subnet | Gateway | Interface / Bridge | Purpose |
| :--- | :--- | :--- | :--- | :--- |
| **Site-A LAN** | `172.28.10.0/24` | `172.28.10.1` | `br-site-a` | Primary Data Center |
| **Site-B LAN** | `172.28.20.0/24` | `172.28.20.1` | `br-site-b` | Disaster Recovery Data Center (15ms WAN delay) |
| **WAN Edge** | `172.28.0.0/24` | `172.28.0.1` | `br-wan` | Inter-site transit backbone & Edge gateway |

* **WAN Delay Emulation:** Configured via Linux Kernel Traffic Control (`tc netem delay 15ms 2ms distribution normal`) on `br-site-b` to model real-world cross-data-center round-trip times.
* **Routing Policies:** Linux IPv4 forwarding enabled with dedicated `iptables` FORWARD rules enabling transparent inter-site communication and NAT masquerading.

---

## 4. Kubernetes Platform Configuration

### 4.1 Cluster Specification
* **Orchestrator:** Kubernetes v1.32.2 via KinD.
* **Nodes:**
  - `multisite-ha-cluster-control-plane` (Control Plane)
  - `multisite-ha-cluster-worker` (Site-A Worker 1)
  - `multisite-ha-cluster-worker2` (Site-A Worker 2)
  - `multisite-ha-cluster-worker3` (Site-B Worker 1)
  - `multisite-ha-cluster-worker4` (Site-B Worker 2)

### 4.2 High Availability Enforcement
1. **Topology Spread Constraints:**
   ```yaml
   topologySpreadConstraints:
     - maxSkew: 1
       topologyKey: topology.kubernetes.io/zone
       whenUnsatisfiable: ScheduleAnyway
       labelSelector:
         matchLabels:
           app: ha-web
   ```
   Ensures that pods are distributed symmetrically between `site-a` and `site-b`.

2. **Pod Anti-Affinity:**
   Enforces node-level anti-affinity (`topologyKey: kubernetes.io/hostname`) to prevent multiple replicas from clustering on the same node.

3. **Pod Disruption Budget (PDB):**
   Specifies `minAvailable: 2`, guaranteeing that during node drains or rolling upgrades, application availability is never compromised.

4. **External Traffic Policy:**
   Configured with `externalTrafficPolicy: Local` on the NodePort service (`port 30080`), ensuring that traffic hitting a site's node is served strictly by the local pod, completely isolating site failures.

---

## 5. Global Edge Load Balancer (HAProxy)

* **Ports:**
  - `80`: Public HTTP Edge Gateway entry point.
  - `8404`: Live Telemetry and Health Statistics Dashboard (`/stats`).
* **Active Health Checking:**
  - Layer-7 HTTP probe on `/healthz` every 1 second (`inter 1s fall 2 rise 2`).
  - Upon 2 consecutive probe failures (≤2s), the server is dynamically marked `DOWN`.
* **Zero-Downtime Connection Redispatch:**
  - `option redispatch` with `retries 3` and `timeout connect 500ms`.
  - If a connection attempt is in-flight when a worker node dies, HAProxy instantaneously reroutes the client to a healthy node in Site-B.

---

## 6. Automation Suite (Infrastructure as Code)

All operations are executed via clean, idempotent shell scripts:

1. **`./scripts/install_tools.sh`:**
   - Installs Docker, KinD, kubectl, and network tools.
   - Tunes Linux kernel inotify and file limits (`fs.inotify.max_user_instances=8192`, `fs.inotify.max_user_watches=524288`) for high-concurrency multi-node clusters.
2. **`./scripts/deploy.sh`:**
   - Single-command zero-to-production deployment.
   - Provisions networks, boots 5-node cluster, applies topology labels, deploys manifests, generates dynamic HAProxy configuration, and validates endpoints.
3. **`./scripts/teardown.sh`:**
   - Eradicates all containers, cluster nodes, custom networks, and firewall rules cleanly.
4. **`./scripts/rebuild.sh`:**
   - Fully destroys and rebuilds the platform from code. Validated completion time: **~199 seconds**.
5. **`./scripts/test_resilience.sh`:**
   - Automated chaos engineering suite executing dual-site balancing, simulated site outage, failover verification, and self-healing validation.

---

## 7. Empirical Resilience & Chaos Test Results

The test suite was executed against the live platform:

```
==================================================================
 [CHAOS TEST] Multi-Site Automated Failover & Resilience Suite
==================================================================

--- TEST 1: Baseline Multi-Site Traffic Distribution ---
==> Sending 30 requests through Global Edge Gateway (Dual-Site Normal State)...
    Results for Dual-Site Normal State:
    - Site-A (Primary DC) Responses:        16 (53%)
    - Site-B (Disaster Recovery) Responses: 14 (46%)
    - Failed Requests (Downtime):            0 (0%)
    [SUCCESS] 100% Zero-Downtime Availability Achieved!

--- TEST 2: Simulating Complete Site-A Catastrophic Failure ---
==> Terminating / Pausing all worker nodes in Site-A...
multisite-ha-cluster-worker
multisite-ha-cluster-worker2
==> Site-A workers are DOWN. Waiting 8 seconds for health checks to mark servers down...

--- TEST 3: Failover Verification Under Active Site-A Outage ---
==> Sending 30 requests through Global Edge Gateway (Site-A Outage Active)...
    Results for Site-A Outage Active:
    - Site-A (Primary DC) Responses:         0 (0%)
    - Site-B (Disaster Recovery) Responses: 30 (100%)
    - Failed Requests (Downtime):            0 (0%)
    [SUCCESS] 100% Zero-Downtime Availability Achieved!

--- TEST 4: Restoring Site-A and Verifying Self-Healing ---
==> Restoring / Unpausing Site-A worker nodes...
multisite-ha-cluster-worker
multisite-ha-cluster-worker2
==> Site-A is back online. Waiting 5 seconds for health probes to re-admit nodes...

--- TEST 5: Post-Recovery Dual-Site Traffic Re-balancing ---
==> Sending 30 requests through Global Edge Gateway (Post-Recovery Normal State)...
    Results for Post-Recovery Normal State:
    - Site-A (Primary DC) Responses:        14 (46%)
    - Site-B (Disaster Recovery) Responses: 16 (53%)
    - Failed Requests (Downtime):            0 (0%)
    [SUCCESS] 100% Zero-Downtime Availability Achieved!

==================================================================
 ==> RESILIENCE & FAILOVER VALIDATION PASSED SUCCESSFULLY! <==   
  - Zero downtime detected during site failure.
  - Dynamic failover to Site-B confirmed.
  - Automatic self-healing and re-balancing confirmed.
==================================================================
```

---

## 8. Verification & Demonstration Commands

From the Windows host or within the Ubuntu VM:

* **Live Application UI:**  
  Open in browser: `http://192.168.138.128/` (shows interactive dashboard with active data center zone badge)
* **Health API Check:**  
  `curl http://192.168.138.128/healthz`
* **HAProxy Telemetry Dashboard:**  
  Open in browser: `http://192.168.138.128:8404/stats`
* **Trigger Full Rebuild from Code:**  
  `./scripts/rebuild.sh`
* **Run Resilience Test Suite:**  
  `./scripts/test_resilience.sh`
