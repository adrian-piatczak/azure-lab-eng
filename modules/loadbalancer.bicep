// modules/loadbalancer.bicep
param location string
param snetAppId string

// ============================================================================
// --- 1. INTERNAL LOAD BALANCER (Resilient Microservices Ingress) ---
// ============================================================================
// Deploying Standard Internal Load Balancer (ILB) to isolate compute workloads 
// from the public internet, routing traffic exclusively via the Hub Firewall.
resource lb 'Microsoft.Network/loadBalancers@2026-01-01' = {
  name: 'ilb-web-${location}-01'
  location: location
  sku: { 
    name: 'Standard' // Enforces secure-by-default posture and enables Availability Zone (AZ) redundancy for 99.99% SLA.
  }
  properties: {
    // --- A. FRONTEND IP CONFIGURATION ---
    frontendIPConfigurations: [
      {
        name: 'PrivateFrontend'
        properties: {
          subnet: { id: snetAppId }
          privateIPAllocationMethod: 'Static'
          // Static internal IP ensuring deterministic DNAT routing from the Edge Firewall
          privateIPAddress: '10.1.1.100' 
        }
      }
    ]
    
    // --- B. BACKEND ADDRESS POOL ---
    // Logical abstraction for dynamic compute nodes. 
    // The VMSS instances will dynamically register their NICs here during scale-out operations.
    backendAddressPools: [ 
      { name: 'WebBackendPool' } 
    ]

    // --- C. HEALTH PROBES (Self-Healing Mechanisms) ---
    probes: [
      {
        name: 'HttpHealthProbe'
        properties: { 
          protocol: 'Http' // Layer 7 probing ensures the actual application daemon is responsive, not just the TCP stack
          port: 80 
          // Architectural Note: In mature microservices, this should target a dedicated deep health check 
          // endpoint (e.g., '/healthz') that validates database connectivity and memory availability.
          requestPath: '/' 
          intervalInSeconds: 15 
          numberOfProbes: 2 
        }
      }
    ]
    
    // --- D. LOAD BALANCING RULES ---
    loadBalancingRules: [
      {
        name: 'HttpLBRule'
        properties: {
          frontendIPConfiguration: { id: resourceId('Microsoft.Network/loadBalancers/frontendIPConfigurations', 'ilb-web-${location}-01', 'PrivateFrontend') }
          backendAddressPool: { id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', 'ilb-web-${location}-01', 'WebBackendPool') }
          probe: { id: resourceId('Microsoft.Network/loadBalancers/probes', 'ilb-web-${location}-01', 'HttpHealthProbe') }
          protocol: 'Tcp'
          frontendPort: 80 
          backendPort: 80 
          // Immediately drops dead client connections upon timeout, preventing TCP port exhaustion on backend nodes
          enableTcpReset: true 
        }
      }
    ]
  }
}

// ============================================================================
// --- OUTPUTS FOR COMPUTE TIER ASSOCIATION ---
// ============================================================================
// Exposing the Backend Pool ID to dynamically inject VMSS network interfaces during provisioning.
output lbBackendPoolId string = lb.properties.backendAddressPools[0].id
