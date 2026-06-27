// Sitos Azure infrastructure: Container Apps API + PostgreSQL + Key Vault + ACR.
// Deploy with:  az deployment group create -g <rg> -f infra/main.bicep -p @infra/main.parameters.json
@description('Azure region for all resources.')
param location string = resourceGroup().location

@description('Short prefix for resource names (lowercase, 3-12 chars).')
@minLength(3)
@maxLength(12)
param namePrefix string = 'sitos'

@description('Deployment environment. Drives resource names, tags, and scaling.')
@allowed([
  'staging'
  'prod'
])
param environment string = 'staging'

@description('PostgreSQL administrator login.')
param pgAdminLogin string = 'sitosadmin'

@description('PostgreSQL administrator password.')
@secure()
param pgAdminPassword string

@description('Container image for the API (e.g. <acr>.azurecr.io/sitos-api:<tag>). Defaults to a placeholder until first push.')
param apiImage string = 'mcr.microsoft.com/dotnet/samples:aspnetapp'

@description('Entra External ID authority URL. Leave empty to run without auth (not recommended in cloud).')
param entraAuthority string = ''

@description('Entra External ID API audience (app/client id).')
param entraAudience string = ''

// All resource names are environment-scoped so staging and prod stay fully isolated.
var baseName = '${namePrefix}-${environment}'
var pgServerName = '${baseName}-pg-${uniqueString(resourceGroup().id)}'
var dbName = 'sitos'
var acrName = toLower('${namePrefix}${environment}acr${uniqueString(resourceGroup().id)}')
var kvName = toLower('${namePrefix}${environment}kv${uniqueString(resourceGroup().id)}')
var commonTags = {
  app: 'sitos'
  environment: environment
}
// Production runs at least one warm replica; staging can scale to zero to save cost.
var minReplicas = environment == 'prod' ? 1 : 0

// ---------- Observability ----------
resource logs 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: '${baseName}-logs'
  location: location
  tags: commonTags
  properties: {
    sku: { name: 'PerGB2018' }
    retentionInDays: 30
  }
}

// ---------- Container Registry ----------
resource acr 'Microsoft.ContainerRegistry/registries@2023-11-01-preview' = {
  name: acrName
  location: location
  tags: commonTags
  sku: { name: 'Basic' }
  properties: { adminUserEnabled: true }
}

// ---------- PostgreSQL Flexible Server ----------
resource pg 'Microsoft.DBforPostgreSQL/flexibleServers@2024-08-01' = {
  name: pgServerName
  location: location
  tags: commonTags
  sku: { name: 'Standard_B1ms', tier: 'Burstable' }
  properties: {
    version: '16'
    administratorLogin: pgAdminLogin
    administratorLoginPassword: pgAdminPassword
    storage: { storageSizeGB: 32 }
    highAvailability: { mode: 'Disabled' }
    backup: { backupRetentionDays: 7, geoRedundantBackup: 'Disabled' }
  }

  resource database 'databases@2024-08-01' = {
    name: dbName
  }

  // Allow other Azure services (incl. Container Apps) to connect.
  resource allowAzure 'firewallRules@2024-08-01' = {
    name: 'AllowAllAzureServices'
    properties: { startIpAddress: '0.0.0.0', endIpAddress: '0.0.0.0' }
  }
}

var pgConnectionString = 'Host=${pg.properties.fullyQualifiedDomainName};Port=5432;Database=${dbName};Username=${pgAdminLogin};Password=${pgAdminPassword};SSL Mode=Require;Trust Server Certificate=true'

// ---------- Key Vault (secret store for future use) ----------
resource kv 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: kvName
  location: location
  tags: commonTags
  properties: {
    sku: { family: 'A', name: 'standard' }
    tenantId: subscription().tenantId
    enableRbacAuthorization: true
    enableSoftDelete: true
  }
}

// ---------- Container Apps environment ----------
resource caEnv 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: '${baseName}-env'
  location: location
  tags: commonTags
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logs.properties.customerId
        sharedKey: logs.listKeys().primarySharedKey
      }
    }
  }
}

// ---------- API Container App ----------
resource api 'Microsoft.App/containerApps@2024-03-01' = {
  name: '${baseName}-api'
  location: location
  tags: commonTags
  identity: { type: 'SystemAssigned' }
  properties: {
    managedEnvironmentId: caEnv.id
    configuration: {
      ingress: {
        external: true
        targetPort: 8080
        transport: 'auto'
      }
      registries: [
        {
          server: acr.properties.loginServer
          username: acr.listCredentials().username
          passwordSecretRef: 'acr-password'
        }
      ]
      secrets: [
        { name: 'acr-password', value: acr.listCredentials().passwords[0].value }
        { name: 'pg-connection', value: pgConnectionString }
      ]
    }
    template: {
      containers: [
        {
          name: 'api'
          image: apiImage
          resources: { cpu: json('0.5'), memory: '1Gi' }
          env: [
            { name: 'ConnectionStrings__Postgres', secretRef: 'pg-connection' }
            { name: 'EntraExternalId__Authority', value: entraAuthority }
            { name: 'EntraExternalId__Audience', value: entraAudience }
            { name: 'ASPNETCORE_ENVIRONMENT', value: 'Production' }
            { name: 'Sitos__Environment', value: environment }
          ]
        }
      ]
      scale: { minReplicas: minReplicas, maxReplicas: 3 }
    }
  }
}

output apiUrl string = 'https://${api.properties.configuration.ingress.fqdn}'
output acrLoginServer string = acr.properties.loginServer
output postgresFqdn string = pg.properties.fullyQualifiedDomainName
output keyVaultName string = kv.name
output environment string = environment
