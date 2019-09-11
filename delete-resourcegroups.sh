#!/usr/bin/env bash

# helper functions
. ./_functions.sh

###
###
###  Script to delete Azure resource groups for development purposes
###
###
help() {
  write
  write " ****************************************************************"
  write " *"
  write " *    Resource Group Removal Script"
  write " *    Usage: ./delete-resourcegroups.sh [options]" 
  write " * "
  write " * "
  write " *    Options:"
  write " *          --help                         Output usage information"
  write " *          -p, --prefix [prefix]          Azure resource group prefix to filter AD Apps to delete, eg. 'debug'." 
  write " *          -y, --yes                      Do not prompt to confirm Azure subscription "
  write " *          -s, --skipPrerequisiteChecks   Confirm AD subscription from which Azure AD Appls will be removed. Defaults to (false)"
  write " * "
  write " * "
  write " *          ./delete-resourcegroups.sh -p debug "
  write " *"
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


deleteAzureResourceGroups() {
  #Use jq to get all app pricipals whose .displayName contains test
  resourceGroups=$(az group list --output json | jq -r '.[] | select(.name | startswith("'"$PREFIX"'")) | .name')
  for group in $resourceGroups; do       
      logMsg "\tDeleting Resource Group $group..."
      az group delete --name $group --yes --output none
      logSuccess "DONE"
  done
}

activeSubscriptionName=$(az account list --all --output json | jq '.[] | select(.isDefault==true) | .name')
if [ $CONFIRM ] ;then
  logInfo "Delete all Azure Resource Groups with prefix ${PREFIX} in  ${activeSubscriptionName} subscription? (y/n)"
  read answer
  if [ "$answer" != "${answer#[Yy]}" ] ;then
    deleteAzureResourceGroups   
  else 
    logError "Script stopped!"
    exit
  fi
else 
  logInfo "Deleting all Azure Resource Groups with prefix ${PREFIX} in  ${activeSubscriptionName} subscription."
  deleteAzureResourceGroups     
fi
