// modules/firewall-rules.bicep
param fwPolicyName string
param firewallPublicIp string

// ============================================================================
// --- 1. PARENT POLICY REFERENCE ---
// ============================================================================
// Referencing the previously deployed Firewall Policy to attach rule collections
resource fwPolicy 'Microsoft.Network/firewallPolicies@2024-01-01' existing = {
  name: fwPolicyName
}

// ============================================================================
// --- 2. RULE COLLECTION GROUP (Traffic Protection Rulesets) ---
// ============================================================================
// Structuring Security Rules into logical collections: Network (L3/L4), Application (L7), and DNAT.
// Enforcing strict Egress/Ingress traffic filtering for isolated microservices.
resource ruleCollectionGroup 'Microsoft.Network/firewallPolicies/ruleCollectionGroups@2024-01-01' = {
  parent: fwPolicy 
  name: 'DefaultNetworkRuleCollectionGroup'
  properties: {
    priority: 200
    ruleCollections: [
      // --- A. NETWORK RULES (L3/L4 Egress Traffic) ---
      {
        ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
        name: 'Network-Rules'
        priority: 100
        action: { type: 'Allow' }
        rules: [
          {
            ruleType: 'NetworkRule'
            name: 'Allow-DNS-Resolution'
            ipProtocols: [ 'UDP' ]
            // Whitelisting egress DNS queries from isolated Spoke VNets
            sourceAddresses: [ '10.1.0.0/16', '10.2.0.0/16' ]
            destinationAddresses: [ '*' ]
            destinationPorts: [ '53' ]
          }
        ]
      }
      // --- B. APPLICATION RULES (L7 Egress FQDN Filtering) ---
      {
        ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
        name: 'Application-Rules'
        priority: 200
        action: { type: 'Allow' }
        rules: [
          {
            ruleType: 'ApplicationRule'
            name: 'Allow-OS-Patching-And-Dependencies' 
            protocols: [
              { protocolType: 'Http', port: 80 }
              { protocolType: 'Https', port: 443 }
            ]
            // Enforcing Zero-Trust by explicitly whitelisting trusted FQDNs for OS updates
            targetFqdns: [ '*.ubuntu.com', '*.microsoft.com' ]
            sourceAddresses: [ '10.1.0.0/16', '10.2.0.0/16' ]
          }
        ]
      }
      // --- C. DNAT RULES (Ingress Traffic Routing) ---
      {
        ruleCollectionType: 'FirewallPolicyNatRuleCollection'
        name: 'DNAT-Rules'
        priority: 300
        action: { type: 'DNAT' }
        rules: [
          {
            ruleType: 'NatRule'
            name: 'Inbound-Web-To-ILB'
            ipProtocols: [ 'TCP' ]
            sourceAddresses: [ '*' ] // Unrestricted Public Internet Ingress
            destinationAddresses: [ firewallPublicIp ] // Edge Firewall Public IP
            destinationPorts: [ '80' ]
            // Securely forwarding ingress traffic to the Internal Load Balancer (ILB) frontend
            translatedAddress: '10.1.1.100' 
            translatedPort: '80'
          }
        ]
      }
    ]
  }
}
