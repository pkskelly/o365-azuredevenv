PREREQS_VALDIATED=0

write() {  # prints in yellow with new line
  printf "\033[33m $1\033[0m\n"
}

logMsg() {  # prints in yellow but no new line
  printf "\033[33m -------> $1\033[0m"
}

logInfo() {  # prints in yellow with new line
  printf "\033[33m -------> $1\033[0m\n"
}

logError() {  # prints in red with new line
  printf "\033[31m -------> $1\033[0m\n"
}

logSuccess() {  # prints in green with new line
  printf "\033[92m $1\033[0m\n"
}

clearDistFolder() {

    # Remove the dist folder as needed
    if [ -d "./dist" ];  then
        logInfo "Removing  dist folder..."
        rm -rf ./dist
    fi 
}

# Deploy to FunctionApp via zip deployment.  
zipDeploy() {

  logInfo "    Configuration:  $1" 
  logInfo "Function App Path:  $2"
  logInfo "     Publish Path:  $3"
  logInfo "         Zip Path:  $4"
  logInfo "          AppName:  $5"
  logInfo "     Debug Output:  $6"
  logInfo "     Calling Path:  $7"

  # First create the "dist" folder
  logInfo "Creating ./dist as zip destination" 
  mkdir ./dist

  logInfo "Changing directory to $2 to begin zipping." 
  cd "$2"
  # Build and publish the requested CONFIGURATION type to publish folder
  dotnet publish -c $1 -o $3
  
  # CD into the publish folder and only zip the contents of the publish folder
  logInfo "Changing directory to $3 to zip build output." 
  cd $3
  logInfo "Zipping to $7/$4." 
  zip -q -r "$7/$4" .
  
  # deploy the zip file to the functionapp
  az functionapp deployment source config-zip -g $5-rg -n $5-funcapp --src "$7/$4" --output $6
  # return to calling path 
  cd $7
}


checkPrerequisites() {

  if [ $PREREQS_VALDIATED -eq 0 ] ;then
    # Prerequisites
    logInfo 'Checking script prerequisites...'
    set +e
    logMsg 'Checking for jq...'
    _=$(command -v jq);
    if [ "$?" != "0" ]; then
      logError 'ERROR \u274c\n'
      logError
      logError "You don't seem to have jq installed."
      logError "See https://stedolan.github.io/jq/ for installation and usage."
      exit 1
    fi;
    logSuccess '\u2713'

    logMsg 'Checking for Azure CLI...'
    _=$(command -v az);
    if [ "$?" != "0" ]; then
       logError 'ERROR \u274c\n'
      logError
      logError "You don't seem to have the Azure CLI installed."
      logError "See https://aka.ms/azure-cli for installation and usage."
      exit 1
    fi;
    logSuccess '\u2713'

    logMsg 'Checking for Azure Functions Core Tools...'
    _=$(command -v func);
    if [ "$?" != "0" ]; then
       logError 'ERROR \u274c\n'
      logError
      logError "You don't seem to have the Azure Functions Core Tools installed."
      logError "See https://docs.microsoft.com/en-us/azure/azure-functions/functions-run-local for installation and usage."
      exit 1
    fi;
    logSuccess '\u2713'

    logMsg 'Checking for CLI for Microsoft 365...'
      _=$(command -v m365);
      if [ "$?" != "0" ]; then
        logError 'ERROR \u274c\n'
        logError
        logError "You don't seem to have the CLI for Microsoft 365 installed."
        logError "See https://pnp.github.io/office365-cli/ for installation and usage."
        exit 1
      fi;
    logSuccess '\u2713'

    EXT_INSTALLED=$(az extension list --output json | jq '.[]| select(.name ==  "noelbundick") | .version')
    logMsg 'Checking self-destruct azure cli extension...'
    if [ -z "$EXT_INSTALLED" ]; then
      logError 'ERROR \u274c\n'
      logError "."
      logError "You don't seem to have Noel Bundicks Azure CLI Extension installed."
      logError "This script depends on this Azure CLI extension. You must install this extension to continue."
      logError "More information: https://github.com/noelbundick/azure-cli-extension-noelbundick"
      logError "."
      exit
    else 
      logSuccess '\u2713'
    fi;
    set -e
  fi
  PREREQS_VALDIATED=1
}


createKeyVaultSecret() {
  
  logInfo "    VaultName: $1"
  logInfo "    SecretName:  $2"
  logInfo "    SecretValue: $3"
  logInfo "    Description: $4"
  logInfo "    Subscription: $5"
  logInfo "    Debug Output: $6"

  az keyvault secret set --vault-name $1 --name $2 --value $3 --description "$4" --subscription $5 --output $6           

}