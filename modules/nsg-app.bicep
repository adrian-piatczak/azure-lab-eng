// modules/nsg-app.bicep
param location string

// ============================================================================
// --- 1. NETWORK SECURITY GROUP (Zero-Trust Subnet Boundary) ---
// ============================================================================
// Provisioning NSG to enforce strict Layer 4 network isolation for the Compute Tier.
resource nsgApp 'Microsoft.Network/networkSecurityGroups@2026-01-01' = {
  name: 'nsg-spoke1-app-${location}-01'
  location: location
  properties: {
    securityRules: [
      // --- A. INFRASTRUCTURE HEALTH PROBES ---
      {
        name: 'Allow-AzureLoadBalancer-Inbound'
        properties: {
          priority: 100 // Highest priority to prevent false-positive node evictions
          access: 'Allow'
          direction: 'Inbound'
          protocol: '*'
          // Utilizing built-in Service Tag. Required for ILB to perform Health Probes.
          sourceAddressPrefix: 'AzureLoadBalancer' 
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '80' 
        }
      }
      // --- B. INGRESS DATA PLANE (DNAT TRAFFIC) ---
      {
        name: 'Allow-Firewall-DNAT-Inbound'
        properties: {
          priority: 110
          access: 'Allow'
          direction: 'Inbound'
          protocol: 'Tcp'
          // Source is '*' because Azure Firewall preserves the original Client IP during DNAT routing.
          // Restricting this to Firewall IP would break the ingress flow!
          sourceAddressPrefix: '*' 
          sourcePortRange: '*'
          // Target boundary isolated strictly to the App Subnet CIDR
          destinationAddressPrefix: '10.1.1.0/24' 
          destinationPortRange: '80'
        }
      }
      // --- C. EXPLICIT DENY-ALL (Observability & Compliance) ---
      {
        name: 'Deny-All-Inbound-Explicit'
        properties: {
          priority: 4096
          access: 'Deny'
          direction: 'Inbound'
          protocol: '*'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
          // Architectural Note: While Azure has a default DenyAll (Priority 65500), 
          // explicitly creating it allows NSG Flow Logs and Azure Traffic Analytics 
          // to properly tag, track, and export dropped packets to the SIEM/SOC workspace.
        }
      }
    ]
  }
}

// ============================================================================
// --- OUTPUTS FOR SUBNET ASSOCIATION ---
// ============================================================================
output nsgId string = nsgApp.id

// Roadmap / Scaling Note:
// For large-scale microservices deployments, securityRules should be decoupled 
// into a separate Bicep module ('Microsoft.Network/networkSecurityGroups/securityRules') 
// to prevent ARM state-locking during concurrent CI/CD pipeline executions.
