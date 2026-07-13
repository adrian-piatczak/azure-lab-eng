// modules/sql.bicep
param location string
param sqlServerName string
param sqlDatabaseName string = 'appdb'
param adminUsername string = 'jerryadmin'

@secure() // Enforcing credential protection in ARM deployment history
param adminPassword string

param spoke2VnetId string
param snetDbId string
param spoke1VnetId string // App VNet reference for Private DNS resolution

// ============================================================================
// --- 1. AZURE SQL LOGICAL SERVER (Zero-Trust Data Plane) ---
// ============================================================================
resource sqlServer 'Microsoft.Sql/servers@2025-01-01' = {
  name: sqlServerName
  location: location
  properties: {
    administratorLogin: adminUsername
    administratorLoginPassword: adminPassword
    version: '12.0'
    // [SECURITY COMPLIANCE]: Disabling public network access.
    // Enforces Zero-Trust architecture by dropping all external ingress attempts at the Azure edge.
    publicNetworkAccess: 'Disabled' 
  }
}

// ============================================================================
// --- 2. AZURE SQL DATABASE (Cost-Optimized PaaS) ---
// ============================================================================
resource sqlDb 'Microsoft.Sql/servers/databases@2025-01-01' = {
  parent: sqlServer
  name: sqlDatabaseName
  location: location
  sku: {
    // Utilizing Basic DTU model for aggressive cost optimization during Dev/Test phases.
    // Easily scalable to vCore models for production workloads without downtime.
    name: 'Basic' 
    tier: 'Basic'
  }
  properties: {
    collation: 'SQL_Latin1_General_CP1_CI_AS'
    maxSizeBytes: 2147483648 // 2 GB limit to enforce storage quotas
  }
}

// ============================================================================
// --- 3. PRIVATE ENDPOINT (Network Isolation & Anti-Exfiltration) ---
// ============================================================================
// Injecting a virtual Network Interface (vNIC) directly into the isolated Spoke 2 Data Subnet.
// This ensures all PaaS traffic remains exclusively on the Azure backbone network.
resource privateEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: 'pe-${sqlServerName}'
  location: location
  properties: {
    subnet: { id: snetDbId } 
    privateLinkServiceConnections: [
      {
        name: 'plsc-${sqlServerName}'
        properties: {
          privateLinkServiceId: sqlServer.id
          // Strict mapping to the SQL sub-resource to prevent Data Exfiltration
          groupIds: [ 'sqlServer' ] 
        }
      }
    ]
  }
}

// ============================================================================
// --- 4. PRIVATE DNS ZONE (Internal Name Resolution) ---
// ============================================================================
// Mandatory for Private Link integration to prevent TLS/SSL certificate validation failures 
// by preserving the original database FQDN while resolving to a private IP.
resource privateDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: 'privatelink.database.windows.net' 
  location: 'global'
}

// ============================================================================
// --- 5. VIRTUAL NETWORK LINKS (DNS Topology) ---
// ============================================================================
// Attaching the Private DNS Zone to both App (Spoke 1) and Data (Spoke 2) VNets.
// Without this, compute nodes will query public root hints and fail to resolve the private IP.
resource dnsLinkSpoke1 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: privateDnsZone
  name: 'link-to-spoke1-app'
  location: 'global'
  properties: {
    virtualNetwork: { id: spoke1VnetId }
    registrationEnabled: false
  }
}

resource dnsLinkSpoke2 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: privateDnsZone
  name: 'link-to-spoke2-data'
  location: 'global'
  properties: {
    virtualNetwork: { id: spoke2VnetId }
    registrationEnabled: false
  }
}

// ============================================================================
// --- 6. DNS ZONE GROUP (Automated Record Management) ---
// ============================================================================
// Automatically registers the Private Endpoint's dynamically assigned IP as an 'A' record 
// in the Private DNS Zone, ensuring lifecycle synchronization.
resource dnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = {
  parent: privateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'config1'
        properties: {
          privateDnsZoneId: privateDnsZone.id
        }
      }
    ]
  }
}

// Outputs for orchestrator routing
output sqlServerFqdn string = sqlServer.properties.fullyQualifiedDomainName
