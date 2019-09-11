#!/usr/bin/env bash

# helper functions
. ./_functions.sh


# Set magic variables for current file & dir
__dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
__file="${__dir}/$(basename "${BASH_SOURCE[0]}")"
__base="$(basename ${__file} .sh)"
__root="$(cd "$(dirname "${__dir}")" && pwd)"


help() {
  write
  write " ****************************************************************"
  write " **  Create Azure Development Resource Group "
  write " **  "
  write " **  Script to create resources for common Office 365"  
  write " **  development scenarios which 'self-destructs' and "
  write " **  removes all resources from a single resource group." 
  write " **  "
  write " **      Usage: ./${__base} {configuration file path}"
  write " **  " 
  write " **    Example: Provision a development resources in Azure for dev/test"
  write " **         ./${__base} ../config/sample.settings.json"
  write " **  "
  write " ** "
  write " ****************************************************************"
}

if [ -z "$1" ] || [ ! -f "$1" ] ; then
    help
    exit
fi

# Default az command output to none (see az global arguments)
DEBUG_OUTPUT="none"

# Read configuration file content 
CONFIG=$(cat "$1")

# Set all configuration values
CONFIGURATION=$(echo $CONFIG | jq -r '.Configuration')
SELF_DESTRUCT_TIMER=$(echo $CONFIG | jq -r '.SelfDestructTimer')
APP_TEMP="$CONFIGURATION$RANDOM"
APP_NAME=${APP_TEMP,,}
APP_SVC_SUFFIX=$(echo $CONFIG | jq -r '.AppServicePlan')
APP_INSIGHTS_SUFFIX=$(echo $CONFIG | jq -r '.AppInsightsSuffix')
RESOURCE_GRP_SUFFIX=$(echo $CONFIG | jq -r '.ResourceGroupSuffix')
KEYVAULT_SUFFIX=$(echo $CONFIG | jq -r '.KeyVaultSuffix')
RESOURCE_LOCATION=$(echo $CONFIG | jq -r '.ResourceLocation')
FUNCTIONAPP_FOLDER=$(echo $CONFIG | jq -r '.FunctionAppFolder')
PUBLISH_FOLDER="${FUNCTIONAPP_FOLDER}/bin/${CONFIGURATION}/netcoreapp2.1/publish"
PUBLISH_ZIP=$(echo $CONFIG | jq -r '.PublishZip')
FUNC_APP_SUFFIX=$(echo $CONFIG | jq -r '.FunctionAppSuffix')
FUNC_APP_ROLES_FILE=$(echo $CONFIG | jq -r '.FunctionAppRoles')
FUNC_REQUIRED_RESOURCES_FILE=$(echo $CONFIG | jq -r '.FunctionRequiredResources')
FUNC_APP_ROLES=$(cat $__dir/$FUNC_APP_ROLES_FILE)
FUNC_REQUIRED_RESOURCES=$(cat $__dir/$FUNC_REQUIRED_RESOURCES_FILE)
FLOW_APP_SUFFIX=$(echo $CONFIG | jq -r '.FlowAppSuffix')
STORAGE_SUFFIX=$(echo $CONFIG | jq -r '.StorageSuffix')
PROGRAM_REQUEST_QUEUE=$(echo $CONFIG | jq -r '.ProgramRequestQueue')
SHAREPOINT_TENANT_NAME=$(echo $CONFIG | jq -r '.SharePointTenantName')
SHAREPOINT_CORS_DOMAIN=$(echo $CONFIG | jq -r '.SharePointCorsDomain')
SHAREPOINT_ADMIN_ACCOUNT=$(echo $CONFIG | jq -r '.SharePointAdminAccount')
SHAREPOINT_ADMIN_PASSWORD=$(echo $CONFIG | jq -r '.SharePointAdminPassword')
AUTOMATION_ACCOUNT_SUFFIX=$(echo $CONFIG | jq -r '.AutomationAccountSuffix')
PROVISIONING_ATTEMPTS=$(echo $CONFIG | jq -r '.ProvisioningAttempts')
PROVISIONING_TEMPLATE_URL=$(echo $CONFIG | jq -r '.PnPProvisioningTemplateUrl')
PROGRAM_RUNBOOK_NAME=$(echo $CONFIG | jq -r '.ProgramRunbookName')
PROGRAM_RUNBOOK_FILEPATH=$(echo $CONFIG | jq -r '.ProgramRunbookFilePath')
PROGRAM_WEBHOOK_NAME=$(echo $CONFIG | jq -r '.ProgramRequestWebhookName')

logInfo "AppName $APP_NAME"
logInfo "Base: $__base"
logInfo "File: $__file"
logInfo "Dir : $__dir"
logInfo "Root: $__root"

# Prerequisites
checkPrerequisites

# Retreive the tenant Id of current default subscription 
tenantId=$(az account list --all --output json | jq -r '.[] | select(.isDefault == true) | .tenantId')
activeSubscriptionName=$(az account list --all --output json | jq '.[] | select(.isDefault==true) | .name')
subscriptionId=$(az account list --all --output json | jq -r '.[] | select(.isDefault==true) | .id')

# Create a resource group and use the "self-destruct" extension to delete - can use 1d, 6h, 2h30m etc
logInfo "Creating ${APP_NAME}${RESOURCE_GRP_SUFFIX} resource group in subscription ${activeSubscriptionName}"
az group create -n "${APP_NAME}${RESOURCE_GRP_SUFFIX}"  \
                  --location $RESOURCE_LOCATION \
                  --tags "Resource.Owner=${SHAREPOINT_ADMIN_ACCOUNT}" \
                  --output ${DEBUG_OUTPUT} \
                  --self-destruct ${SELF_DESTRUCT_TIMER} 

  # Create a storage account in the resource group
  logInfo "Creating ${APP_NAME}${RESOURCE_GRP_SUFFIX} storage account."
  az storage account create -n "${APP_NAME}${STORAGE_SUFFIX}" \
                            -l $RESOURCE_LOCATION \
                            -g "${APP_NAME}${RESOURCE_GRP_SUFFIX}" \
                            --sku Standard_LRS \
                            --tags "Resource.Owner=${SHAREPOINT_ADMIN_ACCOUNT}" \
                            --output ${DEBUG_OUTPUT}

  # Get the connection string and create a queue for the program requests 
  connectionString=$(az storage account show-connection-string -n "${APP_NAME}${STORAGE_SUFFIX}" -g "${APP_NAME}${RESOURCE_GRP_SUFFIX}" --query connectionString -o tsv)
  logInfo "Creating ${PROGRAM_REQUEST_QUEUE} storage queue."
  az storage queue create -n $PROGRAM_REQUEST_QUEUE --connection-string $connectionString --output ${DEBUG_OUTPUT}

  # Get the storage account key for the automation account creation (output into config file)
  storageAccountKey=$(az storage account keys list --resource-group "${APP_NAME}${RESOURCE_GRP_SUFFIX}" --account-name "${APP_NAME}${STORAGE_SUFFIX}" --output json | jq -r '.[0]| .value')

  # Create an app service plan in the resource group
  logInfo "Creating ${APP_NAME}${APP_SVC_SUFFIX} app service plan."
  az appservice plan create -n "${APP_NAME}${APP_SVC_SUFFIX}" \
                            -g "${APP_NAME}${RESOURCE_GRP_SUFFIX}" \
                            -l $RESOURCE_LOCATION \
                            --tags "Resource.Owner=${SHAREPOINT_ADMIN_ACCOUNT}" \
                            --output ${DEBUG_OUTPUT} 

  # Create App Insights
  logInfo "Creating ${APP_NAME}${APP_INSIGHTS_SUFFIX} app insights instance."
  az resource create -n "${APP_NAME}${APP_INSIGHTS_SUFFIX}" \
                    -g "${APP_NAME}${RESOURCE_GRP_SUFFIX}" \
                    --resource-type "Microsoft.Insights/components" \
                    --properties '{"Application_Type":"web"}' \
                    --output ${DEBUG_OUTPUT} 

  # Get the App Insights instrumentation key
  APPINSIGHTS_KEY=$(az resource show -g "${APP_NAME}${RESOURCE_GRP_SUFFIX}" \
                                    -n "${APP_NAME}${APP_INSIGHTS_SUFFIX}" \
                                    --resource-type "Microsoft.Insights/components" \
                                    --query "properties.InstrumentationKey" -o tsv)

  # Create a function app in the resource group, using the storage account and in the created plan 
  logInfo "Creating ${APP_NAME}${FUNC_APP_SUFFIX} function app."
  az functionapp create -n "${APP_NAME}${FUNC_APP_SUFFIX}"  \
                        -g ${APP_NAME}${RESOURCE_GRP_SUFFIX} \
                        --storage-account "${APP_NAME}${STORAGE_SUFFIX}" \
                        --runtime  dotnet \
                        -p "${APP_NAME}${APP_SVC_SUFFIX}" \
                        --app-insights "${APP_NAME}${APP_INSIGHTS_SUFFIX}" \
                        --app-insights-key $APPINSIGHTS_KEY \
                        --tags "Resource.Owner=${SHAREPOINT_ADMIN_ACCOUNT}" \
                        --output ${DEBUG_OUTPUT} 

  # Register an App Principal to be used for Azure Function App Authentication 
  logInfo "Registering App Principal for Function App ${APP_NAME}${FUNC_APP_SUFFIX}."
  funcAppClientSecret=$(openssl rand -base64 44)
  az ad app create --display-name "${APP_NAME}${FUNC_APP_SUFFIX}" \
                  --password $funcAppClientSecret \
                  --identifier-uris "https://${APP_NAME}${FUNC_APP_SUFFIX}.azurewebsites.net" \
                  --reply-urls "https://${APP_NAME}${FUNC_APP_SUFFIX}.azurewebsites.net/.auth/login/aad/callback" \
                  --required-resource-accesses "$FUNC_REQUIRED_RESOURCES" \
                  --output ${DEBUG_OUTPUT} 

  # Retrieve the clientId for the Azure Function App post creation
  funcAppClientId=$(az ad app list --output json | jq -r --arg appname "${APP_NAME}${FUNC_APP_SUFFIX}" '.[]| select(.displayName==$appname) |.appId')

  # Create app roles for the application 
  logInfo "Adding roles for App Principal for Function App."
  az ad app update --id $funcAppClientId --app-roles "$FUNC_APP_ROLES" --output ${DEBUG_OUTPUT}

  # Grant consent the Azure AD Func app 
  logInfo "Granting consent for scopes to Azure AD Function App "
  az ad app permission admin-consent --id $funcAppClientId --output ${DEBUG_OUTPUT}
  
  # Create application settings for the function app - delayed to here since we need the AppID and Secret of the Function App
  logInfo "Applying Function app settings"
  az functionapp config appsettings set -n "${APP_NAME}${FUNC_APP_SUFFIX}" \
                                        -g "${APP_NAME}${RESOURCE_GRP_SUFFIX}"  \
                                        --settings "WEB_SITE_RUN_FROM_PACKAGE=1" \
                                         "APPINSIGHTS_INSTRUMENTATIONKEY=${APPINSIGHTS_KEY}" \
                                         "TenantId=${tenantId}" \
                                         "TenantName=${SHAREPOINT_TENANT_NAME}" \
                                         "AppId=${funcAppClientId}" \
                                         "AppSecret=${funcAppClientSecret}" \
                                         --output ${DEBUG_OUTPUT}
  
  #Configure CORS for the Function App - enable SharePoint tenant name
  az functionapp cors add -n "${APP_NAME}${FUNC_APP_SUFFIX}" -g "${APP_NAME}${RESOURCE_GRP_SUFFIX}" --allowed-origins "${SHAREPOINT_CORS_DOMAIN}" --output ${DEBUG_OUTPUT}

  # Register an App Principal to be used for the Flow App Authentication 
  logInfo "Registering App Principal for Flow App ${APP_NAME}${FLOW_APP_SUFFIX}."
  flowAppClientSecret=$(openssl rand -base64 44)
  az ad app create --display-name "${APP_NAME}${FLOW_APP_SUFFIX}" \
                  --password $flowAppClientSecret \
                  --identifier-uris "https://${APP_NAME}${FLOW_APP_SUFFIX}.azurewebsites.net" \
                  --reply-urls "https://msmanaged-na.consent.azure-apim.net/redirect" "https://global.consent.azure-apim.net/redirect" \
                  --output ${DEBUG_OUTPUT}

  # Retrieve the clientId for the Azure Function App post creation
  flowAppClientId=$(az ad app list --output json | jq -r --arg appname "${APP_NAME}${FLOW_APP_SUFFIX}" '.[]| select(.displayName==$appname) |.appId')
 
  logInfo "Configuring Azure AD Auth for the Flow App "
  # Configure the AZure AD Authentication 
  az webapp auth update --action LoginWithAzureActiveDirectory \
                        --aad-allowed-token-audiences https://${APP_NAME}${FLOW_APP_SUFFIX}.azurewebsites.net/.auth/login/aad/callback \
                        --aad-client-id ${funcAppClientId} \
                        --aad-client-secret ${funcAppClientSecret} \
                        --aad-token-issuer-url https://sts.windows.net/${tenantId}/ \
                        --action LoginWithAzureActiveDirectory \
                        --name "${APP_NAME}${FUNC_APP_SUFFIX}" \
                        --resource-group ${APP_NAME}${RESOURCE_GRP_SUFFIX} \
                        --enabled true \
                        --output ${DEBUG_OUTPUT}

    # Create the KeyVault for storing secrets
    logInfo "Creating Key Vault"
    az keyvault create --subscription $subscriptionId \
                       --location $RESOURCE_LOCATION \
                       --sku standard \
                       --resource-group "${APP_NAME}${RESOURCE_GRP_SUFFIX}" \
                       --name "${APP_NAME}${KEYVAULT_SUFFIX}" \
                        --tags "Resource.Owner=${SHAREPOINT_ADMIN_ACCOUNT}" \
                        --output ${DEBUG_OUTPUT} 

    # Create the Administrator account name  
    createKeyVaultSecret "${APP_NAME}${KEYVAULT_SUFFIX}" "AdminAccount" "${SHAREPOINT_ADMIN_ACCOUNT}" "SharePoint Admin Account" "$subscriptionId" "${DEBUG_OUTPUT}"

    # Create the Administrator password secret 
    createKeyVaultSecret "${APP_NAME}${KEYVAULT_SUFFIX}" "AdminPassword" "somethingsecret" "password" "$subscriptionId" "${DEBUG_OUTPUT}"

    # clean the DIST folder 
    clearDistFolder 

    # Build and deploy source 
    zipDeploy $CONFIGURATION $FUNCTIONAPP_FOLDER $PUBLISH_FOLDER $PUBLISH_ZIP $APP_NAME "${DEBUG_OUTPUT}" $__dir

    # Echo all the config info for final configuration in Dev
    logSuccess "             Func App Client ID:  $funcAppClientId"  
    logSuccess "         Func App Client Secret:  $funcAppClientSecret"
    logSuccess "             Func App Tenant ID:  $tenantId"
    logSuccess "         "
    logSuccess "         "
    logSuccess "             Flow App Client ID:  $flowAppClientId"  
    logSuccess "         Flow App Client Secret:  $flowAppClientSecret"
    logSuccess "             Flow App Tenant ID:  $tenantId"

    # Redirect a json object as the configuration for PowerShell to configure the Automation Account 
    # Redirect a json object as the configuration for PowerShell to configure the Automation Account 
    configJson=$(jq -n \
                    --arg tenantId "$tenantId" \
                    --arg subId ${subscriptionId} \
                    --arg appName "${APP_NAME}" \
                    --arg funcName "${APP_NAME}${FUNC_APP_SUFFIX}" \
                    --arg resGrpName "${APP_NAME}${RESOURCE_GRP_SUFFIX}" \
                    --arg resGrpLoc "$RESOURCE_LOCATION" \
                    --arg storeAcct "${APP_NAME}${STORAGE_SUFFIX}" \
                    --arg storeKey "${storageAccountKey}" \
                    --arg progReqQueue "$PROGRAM_REQUEST_QUEUE" \
                    --arg autoAcctName "${APP_NAME}${AUTOMATION_ACCOUNT_SUFFIX}" \
                    --arg progBookName "$PROGRAM_RUNBOOK_NAME" \
                    --arg progBookPath "$PROGRAM_RUNBOOK_FILEPATH" \
                    --arg progWebhookName "$PROGRAM_WEBHOOK_NAME" \
                    --arg provAttempts "$PROVISIONING_ATTEMPTS" \
                    --arg funcAppId "$funcAppClientId" \
                    --arg funcAppSecret "$funcAppClientSecret" \
                    --arg flowAppId "$flowAppClientId" \
                    --arg flowAppSecret "$flowAppClientSecret" \
                    --arg spUrl "${SHAREPOINT_TENANT_NAME}" \
                    --arg spAcct "${SHAREPOINT_ADMIN_ACCOUNT}" \
                    --arg spPwd "${SHAREPOINT_ADMIN_PASSWORD}" \
                    --arg pnpUrl "${PROVISIONING_TEMPLATE_URL}" \
                    '{appName: $appName, funcAppName: $funcName, tenantId: $tenantId, subscriptionId: $subId, resourceGroupName: $resGrpName, resourceGroupLocation: $resGrpLoc, automationAccountName: $autoAcctName, programRunbookName: $progBookName, programRunbookFilePath: $progBookPath, programWebhookName: $progWebhookName, storageAccountName: $storeAcct, storageAccountKey: $storeKey, programsQueue: $progReqQueue, provisioningAttempts: $provAttempts, funcAppClientId: $funcAppId, funcAppClientSecret: $funcAppSecret, flowAppClientId: $flowAppId, flowAppClientSecret: $flowAppSecret, sharepointUrl: $spUrl, sharepointAdminAccount: $spAcct, sharepointAdminPassword: $spPwd, pnpProvisioningTemplateUrl: $pnpUrl}')    
    
    # Make sure we are in the config directory and then write the config info
    logInfo "*******   Generating config file for Automation Account **********"
    cd $__dir/config
    echo $configJson > automation-config.json
    logInfo "*******   Generated config file for Automation Account **********"
    cd $__dir
    # now call the create-automation-account.ps1 script 
    ./create-automation-account.ps1 $__dir/config/automation-config.json
    # remove temp configuration file 
    rm $__dir/config/automation-config.json

    # Now move to the TeamsFunctions project and configure local settings for local function development
    cd $FUNCTIONAPP_FOLDER
    func azure functionapp fetch-app-settings "${APP_NAME}${FUNC_APP_SUFFIX}"
    #change back to root folder
    cd $__dir

