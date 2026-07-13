// modules/udr.bicep
param location string
param firewallPrivateIp string 

// ============================================================================
// --- 1. USER DEFINED ROUTES (Forced Tunneling for App Tier) ---
// ============================================================================
// Provisioning a dedicated Route Table for the Spoke 1 (App) Subnet.
// Decoupling routing boundaries per workload tier minimizes the blast radius 
// and allows granular, independent route modifications in the future.
resource udrSpoke1 'Microsoft.Network/routeTables@2026-01-01' = {
  name: 'rt-spoke1-to-hub'
  location: location
  properties: {
    // Architectural Note: Set to 'true' in environments with ExpressRoute/VPN 
    // to prevent on-premise BGP routes from hijacking the default 0.0.0.0/0 route.
    disableBgpRoutePropagation: false 
    routes: [
      { 
        name: 'Force-Default-Traffic-To-Hub-Firewall'
        properties: {
          // Catch-all route (Default Route) intercepting all outbound traffic
          addressPrefix: '0.0.0.0/0' 
          // Enforcing traffic inspection through the Network Virtual Appliance (NVA)
          nextHopType: 'VirtualAppliance' 
          nextHopIpAddress: firewallPrivateIp 
        }
      }
    ]
  }
}

// ============================================================================
// --- 2. USER DEFINED ROUTES (Forced Tunneling for Data Tier) ---
// ============================================================================
// Dedicated Route Table for Spoke 2 (Data) Subnet.
// Maintains strict isolation and routing independence for the PaaS Database layer.
resource udrSpoke2 'Microsoft.Network/routeTables@2026-01-01' = {
  name: 'rt-spoke2-to-hub'
  location: location
  properties: {
    disableBgpRoutePropagation: false
    routes: [
      {
        name: 'Force-Default-Traffic-To-Hub-Firewall'
        properties: {
          addressPrefix: '0.0.0.0/0'
          nextHopType: 'VirtualAppliance'
          nextHopIpAddress: firewallPrivateIp
        }
      }
    ]
  }
}

// ============================================================================
// --- OUTPUTS FOR SUBNET ASSOCIATION ---
// ============================================================================
// Exporting Resource IDs to dynamically bind Route Tables to VNets during provisioning.
output udrSpoke1Id string = udrSpoke1.id
output udrSpoke2Id string = udrSpoke2.id
