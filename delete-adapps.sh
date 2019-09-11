#!/usr/bin/env bash

# helper functions
. ./_functions.sh

###
###
###  Script to delete AD app registrations for development purposes
###
###
help() {
  write
  write " *****************************************************************"
  write " *    Azure AD Application Removal Script"
  write " * "
  write " *    Usage: ./delete-adapps.sh [options]" 
  write " * "
  write " * "
  write " *    Options:"
  write " *         --help                        Output usage information"
  write " *         -p, --prefix [prefix]         Azure resource group prefix to filter AD Apps to remove." 
  write " *         -y, --yes                     Do not prompt to confirmation Azure subscription "
  write " *         -s, --skipPrerequisiteChecks  Confirm the Azure subscription to remove Azure AD Apps from - defaults to (false)"
  write " * "
  write " * "
  write " *        ./delete-adapps.sh -p debug "
  write " * "
  write " ****************************************************************"
  write
}

CONFIRM=true
SKIP_PREREQS=

# script arguments
while [ $# -gt 0 ]; do
  case $1 in
    -p|--prefix)
      shift
      PREFIX=$1
      ;;
    -y|--yes)
      CONFIRM=
      ;;
    -s|--skipPrerequisiteChecks)
      SKIP_PREREQS=true
      ;;
    -h|--help)
      help
      exit
      ;;
    *)
      logError "Invalid argument $1"
      help
      exit 1
  esac
  shift
done

if [ -z "$PREFIX" ]; then
    help
    exit
fi

if [ -z "$SKIP_PREREQS" ]; then
  checkPrerequisites    
fi

deleteAzureADApps() {
  # Use jq to get all app pricipals whose .displayName contains prefix
  # !!!!!!! FAILSAFE - if the PREFIX is BLANK then ALL AD APPLICATIONS WILL BE DELETED !!!!!!
  if [ ! -z "$PREFIX" ]; then  
    testApps=$(az ad app list --output json | jq -r '.[] | select(.displayName | startswith("'"$PREFIX"'")) | .appId')
    for app in $testApps; do               
        appName=$(az ad app show --id $app --output json | jq -r '.displayName')
        logMsg "\tDeleting App :  $appName..."
        az ad app delete --id $app
        logSuccess "DONE"
    done
  else 
    logError "AD Application prefix is BLANK. All Azure AD applications would be deleted! Script stopped!"
  fi
}

activeSubscriptionName=$(az account list --all --output json | jq '.[] | select(.isDefault==true) | .name')
if [ $CONFIRM ] ;then
  logInfo "Delete all AD Applications with prefix ${PREFIX} in  ${activeSubscriptionName} subscription? (y/n)"
  read answer
  if [ "$answer" != "${answer#[Yy]}" ] ;then
    deleteAzureADApps   
  else 
    logError "Script stopped!"
    exit
  fi
else 
  logInfo "Deleting all AD Applications with ${PREFIX} in  ${activeSubscriptionName} subscription."
  deleteAzureADApps
fi

