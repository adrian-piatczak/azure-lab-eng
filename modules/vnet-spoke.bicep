// modules/vnet-spoke.bicep
// Orchestrator inputs required to establish macro-segmentation boundaries
param location string
param udrSpoke1Id string 
param udrSpoke2Id string 
param nsgAppId string

// ============================================================================
// --- 1. SPOKE 1: APPLICATION TIER (Compute & Microservices) ---
// ============================================================================
// Provisioning isolated Virtual Network strictly for stateless compute nodes (VMSS/AKS).
resource spoke1Vnet 'Microsoft.Network/virtualNetworks@2026-01-01' = {
  name: 'vnet-spoke1-prod-${location}-01' 
  location: location
  properties: { 
    addressSpace: { addressPrefixes: [ '10.1.0.0/16' ] } 
    subnets: [
      {
        name: 'snet-app' 
        properties: {
          addressPrefix: '10.1.1.0/24'
          // Enforcing Egress traffic inspection via Forced Tunneling to the Hub NVA
          routeTable: { id: udrSpoke1Id } 
          // Enforcing Ingress Zero-Trust boundary at the subnet level
          networkSecurityGroup: { id: nsgAppId } 
        }
      }
    ]
  }
}

// ============================================================================
// --- 2. SPOKE 2: DATA TIER (PaaS & Storage) ---
// ============================================================================
// Provisioning dedicated Virtual Network for the Data Tier. 
// Physical separation from the App Tier limits lateral movement in case of node compromise.
resource spoke2Vnet 'Microsoft.Network/virtualNetworks@2026-01-01' = {
  name: 'vnet-spoke2-data-${location}-01'
  location: location
  properties: {
    addressSpace: { addressPrefixes: [ '10.2.0.0/16' ] }
    subnets: [
      {
        name: 'snet-db'
        properties: {
          addressPrefix: '10.2.1.0/24'
          // Routing PaaS outbound traffic securely through the Central Hub
          routeTable: { id: udrSpoke2Id }
          // Note: NSG is omitted here because Azure SQL via Private Link inherently 
          // denies public access, acting as an implicit Zero-Trust boundary.
        }
      }
    ]
  }
}

// ============================================================================
// --- OUTPUTS FOR STATE ORCHESTRATION ---
// ============================================================================
// Exporting unique identifiers required for downstream dynamic provisioning 
// (e.g., establishing SDN mesh peerings, injecting ILB/VMSS NICs, and Private Endpoints).
output spoke1VnetName string = spoke1Vnet.name
output spoke1VnetId string = spoke1Vnet.id

output spoke2VnetName string = spoke2Vnet.name
output spoke2VnetId string = spoke2Vnet.id

output snetAppId string = spoke1Vnet.properties.subnets[0].id
output snetDbId string = spoke2Vnet.properties.subnets[0].id
