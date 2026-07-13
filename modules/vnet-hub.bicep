// modules/vnet-hub.bicep
param location string

// ============================================================================
// --- 1. CENTRAL TRANSIT HUB (Network Topology Foundation) ---
// ============================================================================
// Provisioning the Central Hub Virtual Network. 
// This acts as the primary point of ingress/egress, transit routing, 
// and centralized security inspection for all downstream microservice Spoke VNets.
resource hubVnet 'Microsoft.Network/virtualNetworks@2026-01-01' = {
  name: 'vnet-hub-${location}-01'
  location: location
  properties: {
    // Allocating a wide /16 CIDR block to accommodate future infrastructure scaling 
    // and multiple managed appliance subnets.
    addressSpace: { addressPrefixes: [ '10.0.0.0/16' ] } 
    subnets: [ 
      // --- A. EDGE SECURITY (Azure Firewall) ---
      // Dedicated subnet for Azure Firewall. Strict naming convention mandated by ARM.
      // /26 CIDR allocated to support automated scale-out of firewall compute nodes under heavy traffic.
      { name: 'AzureFirewallSubnet', properties: { addressPrefix: '10.0.1.0/26' } }
      
      // --- B. HYBRID CONNECTIVITY (Virtual Network Gateway) ---
      // Dedicated subnet reserved for ExpressRoute or IPsec Site-to-Site (S2S) / Point-to-Site (P2S) VPNs.
      // Pre-provisioning this subnet ensures seamless future integration with on-premise environments.
      { name: 'GatewaySubnet', properties: { addressPrefix: '10.0.2.0/27' } } 
      
      // --- C. SECURE OUT-OF-BAND MANAGEMENT (Azure Bastion) ---
      // Dedicated subnet for Azure Bastion. Requires a minimum /26 CIDR for Standard SKU 
      // to support dynamic host scaling for secure administrative tunneling.
      { name: 'AzureBastionSubnet', properties: { addressPrefix: '10.0.3.0/26' } } 
    ]
  }
}

// ============================================================================
// --- OUTPUTS FOR ROUTING & TOPOLOGY ORCHESTRATION ---
// ============================================================================
// Exposing resource identifiers to dynamically establish VNet Peering transit links 
// and inject appliance NICs during the root orchestrator execution.
output hubVnetName string = hubVnet.name
output hubVnetId string = hubVnet.id
output snetFWId string = hubVnet.properties.subnets[0].id
output snetGatewayId string = hubVnet.properties.subnets[1].id
output snetBastionId string = hubVnet.properties.subnets[2].id
