// modules/firewall-rules.bicep
param fwPolicyName string
param firewallPublicIp string

resource fwPolicy 'Microsoft.Network/firewallPolicies@2024-01-01' existing = {
  name: fwPolicyName
}

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
            sourceAddresses: [ '10.1.0.0/16', '10.2.0.0/16' ]
            destinationAddresses: [ '*' ]
            destinationPorts: [ '53' ]
          }
          // TUTA WSTAWIA SIĘ NOWE REGUŁY SIECIOWE L3/L4, JERRY!
          {
            ruleType: 'NetworkRule'
            name: 'Allow-SQL-Spoke1-to-Spoke2'
            ipProtocols: [ 'TCP' ]
            sourceAddresses: [ '10.1.0.0/16' ]
            destinationAddresses: [ '10.2.1.4' ]
            destinationPorts: [ '1433' ]
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
            sourceAddresses: [ '*' ] 
            destinationAddresses: [ firewallPublicIp ] 
            destinationPorts: [ '80' ]
            translatedAddress: '10.1.1.100' 
            translatedPort: '80'
          }
        ]
      }
    ]
  }
}
