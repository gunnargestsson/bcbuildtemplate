# Build Template for Business Central
- Based on the HelloWorld sample from @freddydk 
- https://dev.azure.com/businesscentralapps/HelloWorld

# Getting Started
1.	Add Current.yml, NextMinor.yml, NextMinor.yml to your respository
2.	Add Variable Library for Build parameters
    - BuildVariables
        - CodeSignPfxFile
        - CodeSignPfxPassword
        - LicenseFile
        - TestLicenseFile
        - Password
    - InsiderBuilds
        - InsiderSasToken
3.	Create DevOps pipeline

# Service Connection
Create a service connection to GitHub and update the endpoint
-  https://docs.microsoft.com/en-us/azure/devops/pipelines/library/service-endpoints?view=azure-devops&tabs=yaml
-  Create service connection to your Azure Blob subscription.  Add Azure Blob Contributor Role to Service Principal.  Add Service connection Name as azureSubscription in Current.yml file.


# Build Agent
Build Agent must have Docker and Azure compatability
- Install-Module AZ


