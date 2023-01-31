# Build Template for Business Central
- Based on the HelloWorld sample from @freddydk 
- https://dev.azure.com/businesscentralapps/HelloWorld

# Getting Started
1.	Add Current.yml, NextMinor.yml, NextMinor.yml to your respository
2.	Add Variable Library for Build parameters
    - BuildVariables
        - CodeSignPfxFile (optional for signing the apps)
        - CodeSignPfxPassword (optional for signing the apps)
        - LicenseFile
        - TestLicenseFile (optional if unit tests require development license and build is using customer license)
        - Password
        - ClientId (optional for online tenant deployment)
        - ClientSecret (optional for online tenant deployment)
        - PowerShellUsername (optional for powershell deployment)
        - PowerShellPassword (optional for powershell deployment)
    - InsiderBuilds
        - InsiderSasToken
3.	Create DevOps pipeline

# Publish Sync-NAVApp Mode Parameter
To enable the option to choose if the deployment step in the CI pipeline should ForceSync or not. You need to add the below parameters to your yaml files. You will find an example in file **Current-template-syncmode.yml** in the template folder.
## Pipeline parameter
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
-  https://docs.microsoft.com/en-us/azure/devops/pipelines/library/service-endpoints?view=azure-devops&tabs=yaml

# Azure Blob
To upload artifacts to Azure Blob container
-  Create service connection to your Azure Blob subscription using Azure Resource Manager and recomended options.
-  Creates a service principal in Azure Active Directory based on DevOps organization, project and Azure Subscription Id.
-  Add Role Assignment "Storage Blob Data Contributor" to Azure Storage Account 
-  Add Service connection Name as azureSubscription in Current.yml file.
-  Add Storage Account and Container name to build-settings.json

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

