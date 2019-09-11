<#     
    .SYNOPSIS
    Sample runbook script that creates a list using PnP PowerShell based on the provided parameters, or via provisioned webhook

    .DESCRIPTION
    Simple Runbook to run commands for Office 365 scenarios.  Sample  
    Inspired by internal efforts and https://mmsharepoint.wordpress.com/2019/04/05/provision-microsoft-teams-with-azure-automation-part-ii/

    .NOTES
    - Dependencies: 
        Az.* dependencies installed via provisioning scipt (these are NOT automatically available 
        inside runbook in Azure). SharePointPnPPowerShellOnline cmdlets, v3.8.1904.0 or higher (Apr 2019)
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]    
    [object]$WebhookData,
  
    [Parameter(Mandatory = $false)]
    [string]$siteUrl,

    [Parameter(Mandatory = $false)]
    [string]$listName    
)
$ErrorActionPreference = "Stop"
# Enable tracing for PnP 
Set-PnPTraceLog -On -Level Debug

# global variables populated and used in script for Office 365 / PnP commands
# Created during "create-automation-account.ps1"  
$global:SHAREPOINT_SERVICE = "SharePointService"
$global:credentials = $null

if ($WebhookData) {
    Write-Output ("Starting runbook from webhook")
    # Collect properties of WebhookData
    $WebhookName = $WebHookData.WebhookName
    $WebhookHeaders = $WebHookData.RequestHeader
    $WebhookBody = $WebHookData.RequestBody

    # Collect individual headers. Input converted from JSON.
    $From = $WebhookHeaders.From
    $InputBody = (ConvertFrom-Json -InputObject $WebhookBody)
    Write-Verbose "WebhookBody: $InputBody"

    $siteUrl = $InputBody.siteUrl
    $listName = $InputBody.listName
    Write-Output -InputObject ('Runbook started from webhook {0} by {1}.' -f $WebhookName, $From)
}
else {
    Write-Output ("Starting runbook manually")
}
  
function Add-LogMessage() {
    [CmdletBinding()]
    param($message) 
    Write-Output $message
}

try 
{    
    # get credentials
    $cred = Get-AutomationPSCredential -Name $global:SHAREPOINT_SERVICE
    $userName = $cred.UserName
    $securePassword = $cred.Password
    $global:credentials = New-Object System.Management.Automation.PSCredential ($userName, $securePassword)

    Add-LogMessage "Processing Program Request for Group ID $($groupId)"

    $storageAccountName = Get-AutomationVariable -Name "StorageAccountName"
    $storageAccountKey = Get-AutomationVariable -Name "StorageAccountKey"
    $queueName = Get-AutomationVariable -Name "ProgramsQueue"
    # note used in sample script, but showing as an example
    $sharePointUrl = Get-AutomationVariable -Name "SharePointUrl"

    $context = New-AzStorageContext -StorageAccountName "$($storageAccountName)" -StorageAccountKey "$($storageAccountKey)"

    Add-LogMessage $context

    # get a storage queue
    $queue = $context | Get-AzStorageQueue -Name $queueName

    # Connect to PnP Online and apply the template 
    Connect-PnPOnline -Url $siteUrl -Credentials $global:credentials

    # Simple creation of a new list as an example
    New-PnPList -Title $listName -Template Announcements

    # This "here" string must have the closing portion left aligned or it THROWS an exception 
    $json = @"
    {
    "siteUrl": "$($siteUrl)",
    "status": "Complete",
    "message": "Created $($listName) List"
    }
"@
        
        Add-LogMessage $json.ToString()
        
        # Create a new message using a constructor of the CloudQueueMessage class
        $queueMessage = New-Object -TypeName "Microsoft.Azure.Storage.Queue.CloudQueueMessage,$($queue.CloudQueue.GetType().Assembly.FullName)" -ArgumentList $json

        # Add a new message to the queue for ruther processes 
        $queue.CloudQueue.AddMessageAsync($queueMessage)
        Add-LogMessage "Queued message for next step."       
        Add-LogMessage "Completed processing PnP commands for $($listName)"
   
}
catch {
    Add-LogMessage  "(Get-Date -Format u) $($_.Exception.Message)"
    Add-LogMessage  "(Get-Date -Format u) $($_.Exception.StackTrace)"  
}
finally {
    Add-LogMessage  "$(Get-Date -Format u) WebHook Provisioning done!"
    Set-PnPTraceLog -Off 
}   