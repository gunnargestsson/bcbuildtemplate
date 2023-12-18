# Build Template for Business Central

- Based on the HelloWorld sample from @freddydk 
- https://dev.azure.com/businesscentralapps/HelloWorld

# Getting Started

1. Add Current.yml, NextMinor.yml, NextMinor.yml to your respository
2. Add Variable Library for Build parameters
   - BuildVariables
     - CodeSignPfxFile (optional for signing the apps)
     - CodeSignPfxPassword (optional for signing the apps)
     - LicenseFile (optional - will use Cronus license if not specified)
     - TestLicenseFile (optional if unit tests require development license and build is using customer license)
     - Password (optional - will create random password if not specified)
     - ClientId (optional for online tenant deployment)
     - ClientSecret (optional for online tenant deployment)
     - PowerShellUsername (optional for powershell deployment)
     - PowerShellPassword (optional for powershell deployment)
     - Access a private storage account for license, certificates and app dependencies
       - AzStorageTenantId, Azure tenantid where the storage container is located
       - AzStorageClientId, App Registration Client Id
       - AzStorageClientSecret, App Registration Client Secret
   - InsiderBuilds
     - InsiderSasToken
   - Application Insights
     - InstrumentationKey     
3. Create DevOps pipeline

# Build Settings (build-settings-template.json)

## deployments

There are 3 types of deployment types:

* host

* onlineTenant

* container

Examples:

### host

```
{
    "branch": "refs/heads/main",
    "DeploymentType": "host",  
    "DeployToName": "myVirtualMacine",
    "DeployToInstance": "<blank for default incance>",
    "DeployToTenants": [
        "<blank for all tenants>"
    ],
    "reason": [
        "Schedule",
        "Manual",
        "PullRequest"
    ],
    "InstallNewApps": false
}
```

### onlineTenant

```
{
    "branch": "refs/heads/main",
    "DeploymentType": "onlineTenant",  
    "DeployToName": "Sandbox",
    "DeployToTenants": [
        "24bc1e4f-1a1b-40f8-8987-cd9988f90b4d"
    ]
}
```

### container

```
{
    "branch": "refs/heads/main",
    "DeploymentType": "container",  
    "DeployToName": "myContainer",
    "DeployToTenants": [
        "<blank for all tenants>"
    ]
}
```

### branch
When a pipeline run is triggered the run is marked with a source branch, this setting pecifies what source branch this deployment applies to, in the examples above the deployments will trigger if the run was triggered via the *refs/heads/main* branch.

### DeploymentType
| DeploymentType | Description                                 |
| -------------- | --------------------------------------------|
| onlineTenant   | Deploy to a SaaS enviroment                 |
| container      | Deploy to a Docker container.               |
| host           | Deploy to a Virtual Machine or Server host. |

### DeployToTenants
TenantId/s or tenant name/s in which you want to publish the Per Tenant Extension Apps.

Depending on Deployment Type this setting is used differently.

| DeploymentType | Description                                                                                                                                                                           |
| -------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| onlineTenant   | TenantId/s in the SaaS environment in which you want to publish the Per Tenant Extension Apps.                                                                                        |
| container      | TenantId name/s in the container in which you want to publish the Per Tenant Extension Apps.<br/>If left empty deployment will apply to all tenants in the Server Instance.           |
| host           | Tenant name/s the environment on your Host in which you want to publish the Per Tenant Extension Apps.<br/>If left empty deployment will apply to all tenants in the Server Instance. |

You can specify multiple tenants by using a JSON Array litteral.

Examples:

```
// Single tenant for host and container deployment
"DeployToTenants": [
    "Tenant1"
],

// Multiple tenants for host and conainter deployment
"DeployToTenants": [
    "Tenant1",
    "Tenant2"
],

// All tenants for host and conainter deployment
"DeployToTenants": [],

// Single tenant for onlineTenant deployment
"DeployToTenants": [
    "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
], 

// Multiple tenants for onlineTenant deployment
"DeployToTenants": [
    "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
    "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
],
```
### DeployToName
Depending on Deployment Type this setting is used differently.

| DeploymentType | Description                                                                                          |
| -------------- | ---------------------------------------------------------------------------------------------------- |
| onlineTenant   | Name of the environment inside the tenant in which you want to publish the Per Tenant Extension Apps |
| container      | Name of the conatiner in which you want to publish the Per Tenant Extension Apps                     |
| host           | Name of the Host (VM, server etc.) in which you want to publish the Per Tenant Extension Apps        |

### DeployToInstance
Only applies to Deployment Type **host**. Specifies in which ServerInstance you want to publish the Per Tenant Extension Apps. If left empty the pipeline will try to use the default serverinstance on the host.

### Reason
You can filter your deployment by specifying reasons as a JSON Array litteral. The events that are reported by DevOps can be found here [[Predefined variables - Azure Pipelines | Microsoft Learn](https://learn.microsoft.com/en-us/azure/devops/pipelines/build/variables?view=azure-devops&tabs=yaml#build-variables-devops-services)](https://learn.microsoft.com/en-us/azure/devops/pipelines/build/variables?view=azure-devops&tabs=yaml#build-variables-devops-services).

If left empty or if you omit reasons the pipeline will deploy no mather what reason triggered the run.

### InstallNewApps
Only applies to Deployment Type **host.**
Default value is false.
If specified and the app is not already installed in the tenant or Server Instance, the pipline will try to install the app after succsefully publishing the app.
# Publish Sync-NAVApp Mode Parameter
To enable the option to choose if the deployment step in the CI pipeline should ForceSync or not. You need to add the below parameters to your yaml files. You will find an example in file **Current-template-syncmode.yml** in the template folder.
## Parameters

Add the following to the top of your yaml file where you would like to enable the option.

```
parameters:
- name: SyncAppMode
  displayName: Publish Sync-NAVApp Mode
  type: string
  default: Add
  values:
  - Add
  - ForceSync
```
Add the below parameter to the CI.yml extension at the bottom of the yaml file.
```
SyncAppMode: ${{ parameters.SyncAppMode }}
```
This will give you the option to specify whether your manually triggered deploy will be forced or not.
# Service Connection
Create a service connection to GitHub and update the endpoint

- https://docs.microsoft.com/en-us/azure/devops/pipelines/library/service-endpoints?view=azure-devops&tabs=yaml

# Azure Blob

To upload artifacts to Azure Blob container

- Create service connection to your Azure Blob subscription using Azure Resource Manager and Service Principal.
- Creates a service principal in Azure Active Directory based on DevOps organization, project and Azure Subscription Id.
- Add Role Assignment "Storage Blob Data Contributor" to Azure Storage Account 
- Add Service connection Name as azureSubscription in Current.yml file.
- Add Storage Account and Container name to build-settings.json

# Build Agent

Build Agent must have Docker and Azure compatibility

- Install-Module AZ

# Update AzCopy.exe

- $AzCopyLocation = Get-ChildItem -Path $env:SystemDrive -Filter azcopy.exe -Recurse -ErrorAction SilentlyContinue| Select-Object -First 1
- Invoke-WebRequest -Uri https://aka.ms/downloadazcopy-v10-windows -OutFile ~\Downloads\azcopy.zip
- Unblock-File ~\Downloads\azcopy.zip
- Expand-Archive ~\Downloads\azcopy.zip -DestinationPath ~\Downloads\azcopy -Force
- Copy-Item ~\Downloads\azcopy\*\azcopy.exe $AzCopyLocation -Force
- Remove-Item ~\Downloads\azcopy -Recurse -Force

# alDoc

- https://learn.microsoft.com/en-us/dynamics365/business-central/dev-itpro/help/help-aldoc-generate-help
- Copy the docfx.exe files from $env:USERPROFILE\.dotnet\tools to a folder on the build server
- Extract the ALLanguage.vsix from a new container bchelper extensions folder to a folder on the build server
- Initialize the aldoc folder using aldoc.exe init
- Populate the alDoc section in the build-settings.json 
    "alDoc": {
        "branch": "develop",
        "docFxPath": "F:\\aldoc\\bin\\docfx.exe",
        "alDocPath": "F:\\aldoc\\bin\\extension\\bin\\aldoc.exe",
        "alDocRoot": "F:\\aldoc", 
        "alDocHostName": "kappi.is",
        "alDocPort": 8080
    },