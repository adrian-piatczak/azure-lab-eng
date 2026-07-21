## Implemented Architecture & Technical Specification

The infrastructure is fully modularized using Azure Bicep and implements a highly secure, isolated environment based on the Hub-and-Spoke deployment model.

### 1. Networking & Traffic Routing (SDN)
* **Hub-and-Spoke Topology:** Centralized transit network (`vnet-hub`, `10.0.0.0/16`) connected via bidirectional Virtual Network Peerings to isolated workloads (`vnet-spoke1-prod`, `10.1.0.0/16` and `vnet-spoke2-data`, `10.2.0.0/16`).
* **Transit Traffic Control:** Network peerings are configured with `allowForwardedTraffic` to enable centralized security inspection.
* **Forced Tunneling:** User Defined Routes (UDR) are bound to all Spoke subnets, intercepting the default route (`0.0.0.0/0`) and forcing all outbound traffic through the central Firewall appliance.

### 2. Security & Perimeter Defense
* **Central Network Firewall:** Azure Firewall (Standard SKU) deployed with a decoupled Firewall Policy. 
  * *L3/L4 Filtering:* Explicit Network Rule allowing internal outbound UDP DNS resolution (Port 53).
  * *L7 FQDN Filtering:* Application Rule explicitly whitelisting OS update endpoints (`*.ubuntu.com`, `*.microsoft.com`) under a Zero-Trust posture.
  * *Ingress Routing:* DNAT rule mapping public TCP Port 80 traffic to the Internal Load Balancer.
* **Subnet-Level Isolation:** Network Security Groups (NSGs) enforce strict Layer 4 ingress filtering on the application tier. Includes an explicit `Deny-All` catch-all rule optimized for SIEM/SOC visibility via Flow Logs.
* **Secure Management:** Azure Bastion (Standard SKU) with native client tunneling enabled, providing secure, out-of-band RDP/SSH access without public IP exposure on compute nodes.

### 3. Identity & Secret Management
* **Data-Plane Protection:** Azure Key Vault deployed using the modern Azure RBAC authorization model, completely disabling legacy vault access policies.
* **Runtime Orchestration Injection:** Enabled for ARM template deployments, allowing the compute tier to pull administrative credentials dynamically at runtime using `getSecret()` references without storing plain-text values in the repository or deployment history.

### 4. Compute & Load Balancing Tier (Stateless Application)
* **High Availability Computing:** Virtual Machine Scale Sets (VMSS) running Ubuntu Server (Gen2) inside the isolated application subnet. Configured with an `Automatic` rolling upgrade policy for zero-downtime base image patching.
* **Horizontal Elasticity:** Metric-driven Azure Monitor Autoscale settings enforcing horizontal resource scaling:
  * *Scale-Out:* Appends 1 node when average cluster CPU exceeds 75% over a 5-minute window.
  * *Scale-In:* Terminates 1 node when average cluster CPU drops below 25%, utilizing safe conjunction (AND) evaluation logic to prevent cluster thrashing.
* **Internal Ingress Integration:** Standard Internal Load Balancer (ILB) configured with a static private IP (`10.1.1.100`). Features a Layer 7 HTTP Health Probe (`/`) for proactive node eviction and `enableTcpReset` to mitigate backend port exhaustion.

### 5. Isolated Data Tier
* **Public Boundary Elimination:** Azure SQL Database deployed with `publicNetworkAccess` set to `Disabled`.
* **Private Link Integration:** Database connectivity is routed exclusively via an internal Private Endpoint injected into the isolated Data Subnet (`10.2.1.0/24`).
* **Private DNS Architecture:** Integrated with a Private DNS Zone (`privatelink.database.windows.net`) linked to both Spoke networks, preventing TLS/SSL validation failures by ensuring secure internal name resolution.

### 6. CI/CD & State Automation
* **Passwordless Authentication:** GitHub Actions pipeline utilizing Workload Identity Federation via OpenID Connect (OIDC) against Microsoft Entra ID.
* **Continuous Integration (CI):** Automated Bicep linting (`az bicep build`) and subscription-level ARM `what-if` state simulations to validate infrastructure changes pre-deployment.
* **Continuous Delivery (CD):** Idempotent infrastructure provisioning driven by an externalized environment parameters file (`parameters.json`) combined with dynamic pipeline runtime overrides for sensitive parameters.



## 🗺️ Future Roadmap (AZ-104 Alignment & Enterprise Expansion)

To fully align with the **Microsoft Certified: Azure Administrator Associate (AZ-104)** enterprise standards and expand the architectural capabilities, the following enhancements are planned for the next development phases:

### 1. Hybrid Connectivity & On-Premise Integration
* **Virtual Network Gateway:** Deploy an Azure VPN Gateway (Site-to-Site / Point-to-Site) or ExpressRoute within the Hub network's `GatewaySubnet` to establish a secure, encrypted tunnel to the on-premise datacenter.
* **BGP Routing:** Implement Border Gateway Protocol (BGP) over the VPN/ExpressRoute for dynamic and stable route propagation between the cloud and on-premise environment.
* **Azure File Sync:** Deploy an on-premise Windows Server acting as a rapid cache for Azure Files, utilizing Cloud Tiering to reduce local storage costs while retaining 100% of the data centrally in Azure.

### 2. Advanced Storage & Disaster Recovery
* **Azure Storage Accounts:** Provision dedicated storage accounts for different workloads to prevent IOPS throttling and enforce strict data redundancy (e.g., ZRS/GRS).
* **Blob vs. File Shares:** Implement Azure Blob Storage with flat namespaces for unstructured, cloud-native application data, and Azure Files (SMB) for legacy lift-and-shift workloads.
* **Enterprise Backup Solutions:** Integrate **Azure Backup** (Recovery Services Vault) for scheduled VMSS and Database snapshots, ensuring point-in-time restore (PITR) capabilities.
* **Soft Delete & Snapshots:** Enforce Storage Account-level Soft Delete (with a 14-day retention limit for cost optimization) and automated incremental file share snapshots for robust ransomware protection.

### 3. Identity, Security & RBAC (Microsoft Entra ID)
* **Granular Role-Based Access Control (RBAC):** Transition from broad subscription-level management roles to precise Data-Plane role assignments (e.g., `Storage Blob Data Contributor`).
* **Managed Identities:** Implement System-Assigned Managed Identities for compute resources to securely authenticate to databases and Key Vaults without exposing or rotating plain-text credentials.

### 4. Advanced Traffic Management & Observability
* **Layer 7 Load Balancing:** Upgrade the ingress architecture with **Azure Application Gateway** (WAF v2 SKU) to handle SSL/TLS termination (offloading), URL path-based routing, and Cookie-based Session Affinity.
* **Global Load Balancing:** Evaluate **Azure Front Door** or **Traffic Manager** for multi-region disaster recovery and global DNS-based routing.
* **Telemetry & Diagnostics:** Integrate **Azure Monitor**, **Application Insights**, and **Log Analytics Workspaces** to build KQL-driven dashboards mapping application dependencies and diagnosing HTTP 500 errors in real time.

### 5. Cloud-Native Container Orchestration
* **Serverless Containers:** Migrate background jobs to isolated **Azure Container Instances (ACI)** groups, and transition event-driven microservices to **Azure Container Apps (ACA)** leveraging KEDA for Scale-to-Zero cost optimization.
* **Azure Kubernetes Service (AKS):** The ultimate evolution of the stateless compute tier, replacing raw VMSS nodes with a fully managed Kubernetes cluster for complex, long-running orchestration.