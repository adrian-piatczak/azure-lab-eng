// modules/firewall.bicep
param location string
param snetFWId string

// ============================================================================
// --- 1. INGRESS / EGRESS CONNECTIVITY (Public IP) ---
// ============================================================================
// Provisioning a static Public IP (PIP) for Azure Firewall to enable centralized 
// egress traffic protection (SNAT) and inbound DNAT capabilities.
resource pipFw 'Microsoft.Network/publicIPAddresses@2025-09-01' = {
  name: 'pip-fw-${location}-01'
  location: location
  sku: { 
    name: 'Standard' // Strict requirement for Azure Firewall architectures
  }
  properties: { 
    publicIPAllocationMethod: 'Static' 
  }
}

// ============================================================================
// --- 2. TRAFFIC PROTECTION POLICIES (Centralized Security Rules) ---
// ============================================================================
// Defining Azure Firewall Policy to decouple security rules from the firewall appliance.
// This allows centralized management of Threat Intelligence, Network, and Application rules 
// across the microservices architecture, complying with enterprise security standards.
resource fwPolicy 'Microsoft.Network/firewallPolicies@2024-01-01' = {
  name: 'fw-policy-01'
  location: location
  properties: {
    sku: {
      tier: 'Standard'
    }
    // Note: Threat Intelligence mode is inherently set to 'Alert and Deny' in Standard SKU
  }
}

// ============================================================================
// --- 3. AZURE FIREWALL APPLIANCE ---
// ============================================================================
// Deploying Azure Firewall (Standard SKU) as the central network security appliance 
// in the Hub VNet to inspect and filter all inter-VNet (East-West) and internet (North-South) traffic.
resource firewall 'Microsoft.Network/azureFirewalls@2024-01-01' = {
  name: 'fw-hub-${location}-01' 
  location: location
  properties: {
    sku: {
      name: 'AZFW_VNet'
      tier: 'Standard'
    }
    firewallPolicy: {
      id: fwPolicy.id // Attaching the centralized policy framework
    }
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            // Must be strictly attached to the designated 'AzureFirewallSubnet'
            id: snetFWId
          }
          publicIPAddress: {
            id: pipFw.id
          }
        }
      }
    ]
  }
}

// ============================================================================
// --- OUTPUTS FOR ROUTING & DEPENDENCY MANAGEMENT ---
// ============================================================================
// Exposing outputs for implicit dependency management and User Defined Route (UDR) propagation.
output firewallPrivateIp string = firewall.properties.ipConfigurations[0].properties.privateIPAddress
output firewallPublicIp string = pipFw.properties.ipAddress
output fwPolicyId string = fwPolicy.id
output fwPolicyName string = fwPolicy.name
