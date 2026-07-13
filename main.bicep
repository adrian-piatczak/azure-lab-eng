// main.bicep
targetScope = 'subscription'
param location string

@secure()
param vmPassword string 

// ============================================================================
// --- 1. RESOURCE GROUPS (Logical Isolation & RBAC Boundaries) ---
// ============================================================================
resource rgHub 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: 'rg-network-hub-prod'
  location: location
}
resource rgSpokes 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: 'rg-network-spokes-prod'
  location: location
}
resource rgCompute 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: 'rg-compute-prod'
  location: location
}

// ============================================================================
// --- 2. NETWORKING & ROUTING (Hub-and-Spoke Topology) ---
// ============================================================================
module udr 'modules/udr.bicep' = {
  scope: rgSpokes // Deploying User Defined Routes (UDR) to enforce traffic inspection via Hub Firewall
  name: 'deploy-udr'
  params: { 
    location: location 
    firewallPrivateIp: firewall.outputs.firewallPrivateIp
  }
}

module vnetHub 'modules/vnet-hub.bicep' = {
  scope: rgHub 
  name: 'deploy-vnet-hub'
  params: { location: location }
}

module nsgapp 'modules/nsg-app.bicep' = {
  scope: rgSpokes 
  name: 'deploy-nsg-app'
  params: { location: location }
}

module vnetSpokes 'modules/vnet-spoke.bicep' = {
  scope: rgSpokes 
  name: 'deploy-vnet-spokes'
  params: {
    location: location
    udrSpoke1Id: udr.outputs.udrSpoke1Id
    udrSpoke2Id: udr.outputs.udrSpoke2Id
    nsgAppId: nsgapp.outputs.nsgId
  }
}

// ============================================================================
// --- 3. SECURITY: AZURE FIREWALL (Traffic Protection & Egress Filtering) ---
// ============================================================================
module firewall 'modules/firewall.bicep' = {
  scope: rgHub // Provisioning centralized Firewall in Hub VNet to align with security best practices
  name: 'deploy-firewall'
  params: {
    location: location
    snetFWId: vnetHub.outputs.snetFWId
  }
}

// --- 4. FIREWALL POLICIES & RULES ---
module firewallRules 'modules/firewall-rules.bicep' = {
  scope: rgHub
  name: 'deploy-firewall-rules'
  params: {
    fwPolicyName: firewall.outputs.fwPolicyName
    firewallPublicIp: firewall.outputs.firewallPublicIp
  }
}

// ============================================================================
// --- 5. VNET PEERING AUTOMATION (Microservices Communication) ---
// ============================================================================

// 1. STATIC ARRAY DEFINITION (Compile-time evaluation for predictable deployments)
var spokes = [
  {
    // Pre-defining Spoke 1 (App Tier) properties:
    name: 'vnet-spoke1-prod-${location}-01'
    // Utilizing resourceId() for deterministic identifier generation:
    id: resourceId(subscription().subscriptionId, rgSpokes.name, 'Microsoft.Network/virtualNetworks', 'vnet-spoke1-prod-${location}-01')
    peerName: 'spoke1-prod'
  }
  {
    name: 'vnet-spoke2-data-${location}-01'
    id: resourceId(subscription().subscriptionId, rgSpokes.name, 'Microsoft.Network/virtualNetworks', 'vnet-spoke2-data-${location}-01')
    peerName: 'spoke2-data'
  }
]

// 2. HUB-TO-SPOKE PEERING LOOP
// Batch provisioning of peerings from Central Hub to isolated microservices environments
module peerHubToSpokes 'modules/peering-link.bicep' = [for spoke in spokes: {
  scope: rgHub 
  name: 'deploy-peer-hub-to-${spoke.peerName}'
  dependsOn:[
    vnetHub
    vnetSpokes
  ]
  params: {
    localVnetName: vnetHub.outputs.hubVnetName 
    remoteVnetId: spoke.id 
    peeringName: 'to-${spoke.peerName}' 
  }
}]

// 3. SPOKE-TO-HUB PEERING LOOP
module peerSpokesToHub 'modules/peering-link.bicep' = [for spoke in spokes: {
  scope: rgSpokes 
  name: 'deploy-peer-${spoke.peerName}-to-hub'
  dependsOn:[
    vnetHub
    vnetSpokes
  ]
  params: {
    localVnetName: spoke.name 
    remoteVnetId: vnetHub.outputs.hubVnetId 
    peeringName: 'to-hub' 
  }
}]

// ============================================================================
// --- 6. SECURE SECRET MANAGEMENT (AZURE KEY VAULT) ---
// ============================================================================
module keyvault 'modules/keyvault.bicep' = {
  scope: rgCompute 
  name: 'deploy-keyvault'
  params: {
    location: location
    keyVaultName: 'kv-${uniqueString(rgCompute.id, location)}'
    adminPassword: vmPassword
  }
}

// [DEPENDENCY MANAGEMENT]: Creating a reference to the provisioned vault 
// to enforce implicit dependency and allow runtime secret retrieval.
resource kvRef 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  scope: rgCompute
  name: keyvault.outputs.keyVaultName
}

// ============================================================================
// --- 7. RESILIENT COMPUTE TIER (LB + VMSS for Scalability) ---
// ============================================================================
module alb 'modules/loadbalancer.bicep' = {
  scope: rgCompute
  name: 'deploy-ilb'
  params: {
    location: location
    snetAppId: vnetSpokes.outputs.snetAppId
  }
}

module vmss 'modules/vmss.bicep' = {
  scope: rgCompute
  name: 'deploy-vmss'
  params: {
    location: location
    spoke1VnetName: vnetSpokes.outputs.spoke1VnetName
    spokeRgName: rgSpokes.name
    backendPoolId: alb.outputs.lbBackendPoolId
    // Dynamic secret injection via KeyVaultSecretReference. 
    // Credentials never touch deployment logs or disks, ensuring compliance with Zero-Trust practices.
    adminPassword: kvRef.getSecret('vmAdminPassword')
  }
}

output websiteUrl string = 'http://${firewall.outputs.firewallPublicIp}'

// ============================================================================
// --- 8. SECURE ADMINISTRATIVE ACCESS (AZURE BASTION) ---
// ============================================================================
module bastion 'modules/bastion.bicep' = {
  scope: rgHub 
  name: 'deploy-bastion'
  params: {
    location: location
    snetBastionId: vnetHub.outputs.snetBastionId
  }
}

// ============================================================================
// --- 9. CLOUD-NATIVE DATA TIER (AZURE SQL PAAS + PRIVATE LINK) ---
// ============================================================================
module sql 'modules/sql.bicep' = {
  scope: rgSpokes // Provisioning Database in Spoke environment with public network access strictly disabled
  name: 'deploy-sql-database'
  params: {
    location: location
    // Generating globally unique, deterministic SQL Server name:
    sqlServerName: 'sql-${uniqueString(rgSpokes.id, location)}'
    
    // Securely pulling admin password from Key Vault (No hardcoded credentials allowed)
    adminPassword: kvRef.getSecret('vmAdminPassword')
    
    spoke2VnetId: vnetSpokes.outputs.spoke2VnetId
    snetDbId: vnetSpokes.outputs.snetDbId
    spoke1VnetId: vnetSpokes.outputs.spoke1VnetId // Injecting App VNet ID for Private DNS Zone integration
  }
}
