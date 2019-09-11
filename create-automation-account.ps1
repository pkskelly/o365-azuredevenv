#!/usr/local/bin/pwsh -File

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $configFile
)


$SHAREPOINT_CREDENTIAL_NAME="SharePointService"

<#
.SYNOPSIS
Install module function 

.DESCRIPTION
Function to install required modules for accessing common Azure and SharePoint Online 
services. Script waits for each module to install since there are dependencies on the 
Az modules.  The SharePointPnPPowerShellOnline module hs no dependencies so this is 
not waited on.  

.PARAMETER AutomationAccountName
Automation account to create 

.PARAMETER ResourceGroupName
Resource group to create automation account in

.PARAMETER ModuleName
Module to install 

.PARAMETER Wait
Wait for module installation (flag); defaults to false 
#>

function Install-AzModule {

    param(
        [Parameter(Mandatory = $true)]
        [string] $AutomationAccountName,

        [Parameter(Mandatory = $true)]
        [string] $ResourceGroupName, 
        
        [Parameter(Mandatory = $true)]
        [string] $ModuleName,

        [Parameter(Mandatory = $false)]
        [switch] $Wait

    )
    # Get the PowerShell module so we can add it to our modules.  
    # Wait untill import succeeds or fail
    $azModule = Find-Module -Name $ModuleName
    if ($null -ne $azModule) {

        $azPackageUri = $azModule.RepositorySourceLocation + "/package/$ModuleName"

        Write-Output "Adding $($ModuleName) module from $azPackageUri" 
        New-AzAutomationModule -Name $ModuleName `
            -AutomationAccountName $AutomationAccountName `
            -ResourceGroupName $ResourceGroupName `
            -ContentLink $azPackageUri

        if ($Wait)
        {
            Write-Output "Installing $ModuleName... "
            $counter = 0
            do {
                Start-Sleep 5
                $azModuleInstallStatus = Get-AzAutomationModule -AutomationAccountName $AutomationAccountName  -ResourceGroupName $ResourceGroupName | Where-Object {$_.Name -eq "$($ModuleName)"} | Select-Object  ProvisioningState
                Write-Host "$ModuleName status:  $($azModuleInstallStatus.ProvisioningState)"   
                $counter++
            }
            while (($counter -lt 40) -and ($azModuleInstallStatus.ProvisioningState -ne "Succeeded"))
            if ($counter -eq 40)
            {
                Write-Host "$ModuleName provisioning TIMEOUT!"
                exit
            }
        }
    }
}

$ErrorActionPreference = "Stop"

# Get configuration
Write-Host "Reading configuration file $($configFile)..." -ForegroundColor Yellow
$config = Get-Content $configFile | Out-String | ConvertFrom-Json

$context = Get-AzContext
if (($null -ne $context) -and ($context.Subscription.Id -eq $config.subscriptionId)) {
    Set-AzContext -Subscription $config.subscriptionId 
}
else {
    Write-Host "Please enter credentials for login..." -ForegroundColor Yellow
    $cred = Connect-AzAccount -Tenant $config.tenantId -SubscriptionId $config.subscriptionId
    Write-Host $cred
}


$resourceGroup = Get-AzResourceGroup -Name $config.resourceGroupName  -ErrorAction SilentlyContinue 
if ($null -eq $resourceGroup) {
    Write-Output "Creating Azure Resource Group '$($config.resourceGroupName)'"
    $resourceGroup = New-AzResourceGroup -Name $config.resourceGroupName -Location $config.resourceGroupLocation
    Write-Host "$($resourceGroup) created successfully."
}

$azureAutomationAccount = Get-AzAutomationAccount -Name $config.automationAccountName -ResourceGroupName $config.resourceGroupName -ErrorAction SilentlyContinue 
if ($null -eq $azureAutomationAccount) {
    Write-Output "Creating Azure Automation Account '$($config.automationAccountName)'"
    $azureAutomationAccount = New-AzAutomationAccount -Name $config.automationAccountName -ResourceGroupName $config.resourceGroupName -Location $resourceGroup.Location 
}    

# TODO: Replace this with a call in the actual Runbook to retrieve Pwd from KeyVault.  Need MSI, and other info to complete. For now, using Automation Credential 
$credSharePointService = Get-AzAutomationCredential -Name $SHAREPOINT_CREDENTIAL_NAME -AutomationAccountName $azureAutomationAccount -ResourceGroupName $resourceGroup -ErrorAction SilentlyContinue 
if ($null -eq $credSharePointService) {
    Write-Output "New Automation Credential: SharePointService"  
    $password = ConvertTo-SecureString $config.sharepointAdminPassword -AsPlainText -Force
    $credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $config.sharepointAdminAccount, $password
    New-AzAutomationCredential -Name $SHAREPOINT_CREDENTIAL_NAME `
        -AutomationAccountName $config.automationAccountName `
        -ResourceGroupName $config.resourceGroupName `
        -Description "User Account for creating SharePoint Site Collections" `
        -Value $credential
}
else {
    Write-Output "Exists Automation Credential: $SHAREPOINT_CREDENTIAL_NAME" 
}

# Install all of the required modules and wait as needed for dependencies 
Install-AzModule -ModuleName "Az.Accounts"  -AutomationAccountName $config.automationAccountName -ResourceGroupName $config.resourceGroupName -Wait 
Install-AzModule -ModuleName "Az.Storage"  -AutomationAccountName $config.automationAccountName -ResourceGroupName $config.resourceGroupName -Wait 
Install-AzModule -ModuleName "Az.KeyVault"  -AutomationAccountName $config.automationAccountName -ResourceGroupName $config.resourceGroupName -Wait 
Install-AzModule -ModuleName "Az.Profile"  -AutomationAccountName $config.automationAccountName -ResourceGroupName $config.resourceGroupName -Wait 
Install-AzModule -ModuleName "SharePointPnPPowerShellOnline"  -AutomationAccountName $config.automationAccountName -ResourceGroupName $config.resourceGroupName

$varSharePointUrl = Get-AzAutomationVariable -Name "SharePointUrl" -AutomationAccountName $config.automationAccountName -ResourceGroupName $config.resourceGroupName -ErrorAction SilentlyContinue
if ($null -eq $varSharePointUrl) {
    Write-Output "New Automation Variable: SharePointUrl"              
    New-AzAutomationVariable -Name "SharePointUrl" `
        -AutomationAccountName $config.automationAccountName `
        -ResourceGroupName $config.resourceGroupName `
        -Description "Root SharePoint Url that is used when configuring sites" `
        -Value $config.sharepointUrl `
        -Encrypted $false  
}
else {
    Write-Output "Automation Variable Exists: SharePointUrl"  
}

$varStorageAccountName = Get-AzAutomationVariable -Name "StorageAccountName" -AutomationAccountName $config.automationAccountName -ResourceGroupName $config.resourceGroupName -ErrorAction SilentlyContinue
if ($null -eq $varStorageAccountName) {
    Write-Output "New Automation Variable: StorageAccountName"              
    New-AzAutomationVariable -Name "StorageAccountName" `
        -AutomationAccountName $config.automationAccountName `
        -ResourceGroupName $config.resourceGroupName `
        -Description "Storage Account used for persisting output from PnP Provisioning" `
        -Value $config.storageAccountName `
        -Encrypted $false  
}
else {
    Write-Output "Automation Variable Exists: StorageAccountName"  
}

$varStorageAccountKey = Get-AzAutomationVariable -Name "StorageAccountKey" -AutomationAccountName $config.automationAccountName -ResourceGroupName $config.resourceGroupName -ErrorAction SilentlyContinue
if ($null -eq $varStorageAccountKey) {
    Write-Output "New Automation Variable: StorageAccountKey"
    New-AzAutomationVariable -Name "StorageAccountKey" `
        -AutomationAccountName $config.automationAccountName `
        -ResourceGroupName $config.resourceGroupName `
        -Description "Storage Account Key used for persisting output from PnP Provisioning" `
        -Value $config.storageAccountKey `
        -Encrypted $false  
}
else {
    Write-Output "Automation Variable Exists: StorageAccountKey"  
}


$varStorageQueue = Get-AzAutomationVariable -Name "ProgramsQueue" -AutomationAccountName $config.automationAccountName -ResourceGroupName $config.resourceGroupName -ErrorAction SilentlyContinue
if ($null -eq $varStorageQueue) {
    Write-Output "New Automation Variable: ProgramsQueue"
    New-AzAutomationVariable -Name "ProgramsQueue" `
        -AutomationAccountName $config.automationAccountName `
        -ResourceGroupName $config.resourceGroupName `
        -Description "Storage Queue name used for persisting output from PnP Provisioning" `
        -Value $config.programsQueue`
        -Encrypted $false  
}
else {
    Write-Output "Automation Variable Exists: ProgramsQueue"  
}

$varProvisioningAttempts = Get-AzAutomationVariable -Name "ProvisioningAttempts" -AutomationAccountName $config.automationAccountName -ResourceGroupName $config.resourceGroupName -ErrorAction SilentlyContinue
if ($null -eq $varProvisioningAttempts) {
    Write-Output "New Automation Variable: ProvisioningAttempts"
    New-AzAutomationVariable -Name "ProvisioningAttempts" `
        -AutomationAccountName $config.automationAccountName `
        -ResourceGroupName $config.resourceGroupName `
        -Description "Number of times to delay (for 1 min) to obtain the Team's SharePoint Site Url before attempting PnP Provisioning" `
        -Value $config.provisioningAttempts `
        -Encrypted $false  
}
else {
    Write-Output "Automation Variable Exists: ProvisioningAttempts"  
}

$varProgramPnPTemplateUrl = Get-AzAutomationVariable -Name "ProgramPnPTemplateUrl" -AutomationAccountName $config.automationAccountName -ResourceGroupName $config.resourceGroupName -ErrorAction SilentlyContinue
if ($null -eq $varProgramPnPTemplateUrl) {
    Write-Output "New Automation Variable: ProgramPnPTemplateUrl"
    New-AzAutomationVariable -Name "ProgramPnPTemplateUrl" `
        -AutomationAccountName $config.automationAccountName `
        -ResourceGroupName $config.resourceGroupName `
        -Description "PnP Provisioning template file" `
        -Value $config.pnpProvisioningTemplateUrl `
        -Encrypted $false  
}
else {
    Write-Output "Automation Variable Exists: ProvisioningAttempts"  
}

Write-Output "Importing Runbook '$($config.programRunbookName)' from path '$($config.programRunbookFilePath)'"  
Import-AzAutomationRunbook `
    -AutomationAccountName $config.automationAccountName `
    -Name $config.programRunbookName `
    -Description "Apply PnP Template to destination sites" `
    -Type PowerShell `
    -Path $config.programRunbookFilePath `
    -ResourceGroupName $config.resourceGroupName `
    -Published `
    -Force

Write-Output "Creating Webhbook '$($config.programWebhookName)'"  
$webhook = Get-AzAutomationWebhook -ResourceGroupName $config.resourceGroupName -AutomationAccountName $config.automationAccountName
if ($null -eq $webHook ) 
{
    $webhook = New-AzAutomationWebhook `
        -AutomationAccountName $config.automationAccountName `
        -Name $config.programRunbookName `
        -IsEnabled $True `
        -ExpiryTime "12/31/2025" `
        -RunbookName $config.programRunbookName `
        -ResourceGroup $config.resourceGroupName `
        -Force

    Write-Output "Created webhook: $($webhook.WebhookURI)"
} else {
    Write-Output "Webhook already existed: $($webhook.WebhookURI)"
}

# We need to add the Webhook Url to the function app's app settings
Write-Output "Adding webhook to appsettings." 
# Get current App Settings
$currentFuncApp = Get-AzWebApp -ResourceGroupName $config.resourceGroupName -Name $config.funcAppName
$currentAppSettings = $currentFuncApp.SiteConfig.AppSettings
$updatedSettings = @{}
ForEach ($kvp in $currentAppSettings) {
    $updatedSettings[$kvp.Name] = $kvp.Value
}
$updatedSettings["ProgramsWebhookUrl"] = "$($webhook.WebhookURI)"
Set-AzWebApp -ResourceGroupName $config.resourceGroupName -Name $config.funcAppName -AppSettings $updatedSettings
ForEach ($key in $updatedSettings.Keys) {    
    Write-host "   $key = $($updatedSettings[$key])"
}

Write-Host "DONE!" -ForegroundColor Yellow