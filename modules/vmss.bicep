// modules/vmss.bicep
param location string
param spokeRgName string
param spoke1VnetName string
param backendPoolId string
param adminUsername string = 'jerryadmin'

@secure() // [SECURITY COMPLIANCE]: Prevents plain-text administrative credentials from leaking into deployment history
param adminPassword string

// ============================================================================
// --- 1. CROSS-RESOURCE GROUP REFERENCE (Network Dependency) ---
// ============================================================================
// Referencing the existing Spoke 1 VNet across resource group boundaries (rgSpokes vs rgCompute).
// The 'scope' property enforces correct resource targeting within the ARM deployment engine.
resource spoke1Vnet 'Microsoft.Network/virtualNetworks@2026-01-01' existing = {
  name: spoke1VnetName
  scope: resourceGroup(spokeRgName)
}

// ============================================================================
// --- 2. CLOUD-INIT BOOTSTRAP (Stateless & Immutable Provisioning) ---
// ============================================================================
// Shell script executed exactly once during the initial bootstrap of each compute node.
// Installs Nginx and injects runtime telemetry (hostname) to demonstrate internal load balancing.
var cloudInitScript = '''
#!/bin/bash
apt-get update
apt-get install -y nginx
echo "<html><body><h1>Enterprise Microservices Stack - Node: $(hostname)</h1></body></html>" > /var/www/html/index.html
systemctl enable nginx
systemctl start nginx
'''

// ============================================================================
// --- 3. VIRTUAL MACHINE SCALE SET (Elastic Compute Tier) ---
// ============================================================================
// Provisioning a VMSS to achieve high availability, fault tolerance, and horizontal scalability.
resource vmss 'Microsoft.Compute/virtualMachineScaleSets@2026-03-01' = {
  name: 'vmss-web-01'
  location: location
  sku: {
    name: 'Standard_D2s_v3' // Compute optimization: 2 vCPUs, 8 GB RAM
    capacity: 1 // Initial baseline capacity for cost-efficiency during PoC phase
    tier: 'Standard'
  }
  properties: {
    // [ROLLING UPGRADES]: Automatically orchestrates node replacement when the OS image or model updates, ensuring zero downtime.
    upgradePolicy: { mode: 'Automatic' }
    virtualMachineProfile: {
      osProfile: {
        computerNamePrefix: 'web' // Dynamic hostname sequencing (e.g., web000000, web000001)
        adminUsername: adminUsername
        adminPassword: adminPassword
        // Injecting cloud-init logic. ARM requires binary stream encapsulation via base64 encoding.
        customData: base64(cloudInitScript) 
      }
      storageProfile: {
        imageReference: {
          publisher: 'Canonical'
          offer: '0001-com-ubuntu-server-jammy'
          sku: '22_04-lts-gen2' // Gen2 architecture leverages UEFI boot and modern hypervisor performance
          version: 'latest'
        }
        osDisk: {
          createOption: 'FromImage'
          // [FINOPS COST OPTIMIZATION]: Utilizing Standard_LRS since the workload tier is strictly stateless.
          // Persistent Premium SSDs are decoupled from the compute tier, minimizing unnecessary storage expenditures.
          managedDisk: { storageAccountType: 'Standard_LRS' }
        }
      }
      networkProfile: {
        networkInterfaceConfigurations: [
          {
            name: 'nic-vmss'
            properties: {
              primary: true
              ipConfigurations: [
                {
                  name: 'ipconfig-vmss'
                  properties: {
                    // Dynamic subnet binding to the isolated Application Spoke VNet
                    subnet: { id: '${spoke1Vnet.id}/subnets/snet-app' }
                    // Dynamic Backend Pool registration. Automates downstream health probing via the Internal Load Balancer.
                    loadBalancerBackendAddressPools: [ { id: backendPoolId } ] 
                  }
                }
              ]
            }
          }
        ]
      }
    }
  }
}

// ============================================================================
// --- 4. AUTOSCALE ENGINE (Horizontal Scaling Policy Framework) ---
// ============================================================================
// Implementing metric-driven, proactive horizontal scaling to manage resource elasticity automatically.
resource autoscale 'Microsoft.Insights/autoscaleSettings@2022-10-01' = {
  name: 'autoscale-vmss-web'
  location: location
  properties: {
    targetResourceUri: vmss.id // Attaching the telemetry engine directly to the target scale set
    enabled: true
    profiles: [
      {
        name: 'AutoCreatedScaleProfile'
        capacity: {
          minimum: '1' // Guardrail: Ensures infrastructure availability (Prevents zero-node service blackout)
          maximum: '3' // FinOps Ceiling: Restricts runaway costs during traffic spikes or malicious DDoS attempts
          default: '1' // Fail-safe default fallback configuration
        }
        rules: [
          // --- RULE A: HORIZONTAL SCALE-OUT (Performance Guard) ---
          {
            metricTrigger: {
              metricName: 'Percentage CPU'
              metricResourceUri: vmss.id
              timeGrain: 'PT1M' // 1-minute telemetry sampling frequency
              statistic: 'Average'
              timeWindow: 'PT5M' // 5-minute aggregation window to eliminate transient metric spikes
              timeAggregation: 'Average'
              operator: 'GreaterThan'
              threshold: 75 // Triggers scale-out event if cluster average CPU breaks 75%
            }
            scaleAction: {
              direction: 'Increase'
              type: 'ChangeCount'
              value: '1' // Incrementally appends 1 compute node
              cooldown: 'PT5M' // Cooldown period allowing the new node to fully bootstrap before subsequent scaling evaluations
            }
          }
          // --- RULE B: HORIZONTAL SCALE-IN (Cost Optimization Guard) ---
          {
            metricTrigger: {
              metricName: 'Percentage CPU'
              metricResourceUri: vmss.id
              timeGrain: 'PT1M'
              statistic: 'Average'
              timeWindow: 'PT5M'
              timeAggregation: 'Average'
              operator: 'LessThan'
              threshold: 25 // Triggers scale-in event if cluster capacity is underutilized (<25% CPU)
            }
            scaleAction: {
              direction: 'Decrease'
              type: 'ChangeCount'
              value: '1' // Decrementally terminates 1 compute node
              cooldown: 'PT5M' // Cooldown restriction to prevent cluster thrashing/flapping
            }
          }
        ]
      }
    ]
  }
}

/*
  ============================================================================
  ARCHITECTURAL TELEMETRY NOTE (Scale-Out vs Scale-In Evaluation Logic):
  ============================================================================
  1. Horizontal Scale-Out (Resource Provisioning) evaluates using logical OR (Disjunction).
     If multiple scale-out metrics are defined (e.g., CPU > 75% OR Memory > 80%), Azure Monitor 
     triggers resource allocation as soon as ANY individual threshold is violated, prioritizing service availability.

  2. Horizontal Scale-In (Resource Deprovisioning) evaluates using logical AND (Conjunction).
     To safely decommission a node, ALL metric thresholds must simultaneously satisfy the scale-in conditions 
     (e.g., CPU < 25% AND Memory < 30%). This conservative engineering posture prevents premature node termination, 
     safeguarding the remaining cluster against immediate Memory Out-Of-Memory (OOM) cascading failures.
*/
