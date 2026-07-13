// modules/keyvault.bicep
param location string
param keyVaultName string // Globally unique name required for Azure Key Vault namespace
param tenantId string = subscription().tenantId

@secure() // Enforces encryption at rest during deployment, preventing plain-text values in ARM history
param adminPassword string

// ============================================================================
// --- 1. AZURE KEY VAULT RESOURCE (Secure Cryptographic Storage) ---
// ============================================================================
// Provisioning Azure Key Vault to centralize application secrets, keys, and certificates.
// This design strictly isolates infrastructure credentials from code repositories.
resource kv 'Microsoft.KeyVault/vaults@2026-02-01' = {
  name: keyVaultName
  location: location
  properties: {
    sku: {
      family: 'A'
      name: 'standard' // Standard SKU utilizes software-backed encryption, optimizing costs for Dev/Test workloads while maintaining strict compliance
    }
    tenantId: tenantId
    
    // [SECURITY BEST PRACTICE]: Enforcing Azure RBAC authorization model.
    // This decouples data-plane access control from legacy Vault Access Policies,
    // aligning with corporate governance and unified Microsoft Entra ID management.
    enableRbacAuthorization: true 
    
    // [RUNTIME INJECTION]: Permitting the Azure Resource Manager (ARM) engine 
    // to query and inject secrets dynamically during VMSS/App runtime orchestration.
    enabledForDeployment: true 
    enabledForTemplateDeployment: true 
  }
}

// ============================================================================
// --- 2. SECRET PROVISIONING (Compute Administrator Credentials) ---
// ============================================================================
// Storing the administrator password as a secure secret object within the vault.
resource secret 'Microsoft.KeyVault/vaults/secrets@2026-02-01' = {
  parent: kv // Direct containment linking the secret to the parent Key Vault instance
  name: 'vmAdminPassword'
  properties: {
    value: adminPassword // Injecting the parameter value provided securely via the CI/CD workflow
  }
}

// ============================================================================
// --- OUTPUTS FOR RESOURCE REFERENCING ---
// ============================================================================
output keyVaultName string = kv.name
output keyVaultId string = kv.id
// Security Best Practice: Never expose sensitive data values in deployment outputs; expose resource identifiers only.
