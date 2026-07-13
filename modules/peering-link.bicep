// modules/peering-link.bicep
// DRY (Don't Repeat Yourself) architecture approach for granular network mesh management
param localVnetName string
param remoteVnetId string
param peeringName string

// ============================================================================
// --- 1. VNET PEERING LINK (Software-Defined Mesh Topology) ---
// ============================================================================
// Provisioning a Virtual Network Peering link. 
// This creates a low-latency, high-bandwidth backbone connection using Microsoft's global network.
resource peering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-11-01' = {
  // Strict naming convention required by ARM: 'ParentVirtualNetworkName/SubResourceName'
  name: '${localVnetName}/${peeringName}' 
  properties: {
    remoteVirtualNetwork: {
      id: remoteVnetId // Target cross-referenced resource identifier
    }
    // Permitting full internal address space communication between clustered nodes
    allowVirtualNetworkAccess: true
    
    // [CRITICAL FOR HUB-AND-SPOKE ROUTING]: Enabling forwarded traffic transit.
    // This allows Spoke VNets to route outbound/inter-spoke traffic through the 
    // central Hub network security appliance (Azure Firewall), preventing asymmetric routing.
    allowForwardedTraffic: true
    
    // Defaulting gateway transit flags to false for standard isolated hub workloads
    allowGatewayTransit: false
    useRemoteGateways: false
  }
}

// Architectural Design Note (CI/CD Optimization):
// This module is intentionally kept flat and executed via a 'for' loop expression 
// within the root orchestrator ('main.bicep'). Iterating at the module invocation level 
// guarantees deployment granularity within the Azure Resource Manager engine. 
// It ensures that each individual peering link registers as a distinct deployment tracking state, 
// preventing opaque "black box" logging and streamlining pipeline troubleshooting.
