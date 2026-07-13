// modules/bastion.bicep
param location string
param snetBastionId string

// ============================================================================
// --- 1. INGRESS CONNECTIVITY (Bastion Public IP) ---
// ============================================================================
// Provisioning a dedicated Public IP Address for Azure Bastion ingress traffic.
// Note: Azure architecture strictly mandates the Standard SKU for Bastion PIPs.
resource pipBastion 'Microsoft.Network/publicIPAddresses@2026-01-01' = {
  name: 'pip-bastion-${location}-01'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

// ============================================================================
// --- 2. SECURE ADMINISTRATIVE ACCESS (Azure Bastion PaaS) ---
// ============================================================================
// Deploying Azure Bastion PaaS to enforce secure, Zero-Trust administrative 
// access to microservices and VMs, eliminating the need for public IPs on workloads.
resource bastion 'Microsoft.Network/bastionHosts@2026-01-01' = {
  name: 'bastion-hub-${location}-01'
  location: location
  sku: {
    name: 'Standard' // Enforcing Standard SKU for enterprise capabilities and scaling
  }
  properties: {
    // Enabling native client support (IP-based tunneling).
    // Critical for developers accessing private PaaS (Azure SQL) via local SSMS/DBeaver.
    enableTunneling: true 
    ipConfigurations: [
      {
        name: 'IpConf'
        properties: {
          subnet: {
            id: snetBastionId 
          }
          publicIPAddress: {
            id: pipBastion.id
          }
        }
      }
    ]
  }
}

// Architectural Note (Hub-and-Spoke Topology):
// Bastion is deployed centrally within the Hub VNet. To provide secure transit 
// connectivity to isolated Spoke VNets, VNet Peering must be configured with 
// 'allowVirtualNetworkAccess: true' on both ends of the peering link.
