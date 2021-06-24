#!/usr/bin/env bash

# helper functions
. ./_functions.sh

###
###
###  Script to delete a Azure AD groups from development environment
###
###
help() {
  write
  write "*****************************************************************"
  write "*  "
  write "*     Azure AD Groups Removal Script"
  write "*  "
  write "*     Usage: ./delete-testgroups.sh [options]" 
  write "*  "
  write "*  "
  write "*     Options:"
  write "*          --help                        Output usage information"
  write "*          -f, --filter [filter]         Prefix filter for deleting Azure AD unified groups.  e.g. 'debug'." 
  write "*          -y, --yes                     Do not prompt to confirmation Azure subscription "
  write "*          -s, --skipPrerequisiteChecks  Confirm the Azure subscription to remove Azure AD Apps from - defaults to (false)"
  write "*  "
  write "*  "
  write "*         ./delete-testgroups.sh -f Test-"
  write "*  "
  write "*****************************************************************"
  write
}

CONFIRM=true
SKIP_PREREQS=

# script arguments
while [ $# -gt 0 ]; do
  case $1 in
    -f|--filter)
      shift
      FILTER=$1
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

if [ -z "$FILTER" ]; then
  help
  exit 1
fi

if [ -z "$SKIP_PREREQS" ]; then
  checkPrerequisites    
fi

deleteO365Groups() {
      #Get all of the groups to remove using cli to create tmp file with the groups
      #BUG in VorpalJS used by the Office 365 CLI does not like a pure piping of large 
      #    result sets
      m365 aad o365group list --output json > groups.tmp 
      
      #Get the groups from file created by the CLI call
      groupIds=$(cat groups.tmp | jq -r '.[] | select(.displayName | contains("'"$1"'")) | .id')

      #clean up the tmp file
      rm groups.tmp

      for groupId in $groupIds; do
          logMsg "Removing group $groupId ..."
          m365 aad o365group remove --id $groupId --confirm
          logSuccess "DONE"
      done
}

#output current connnection 
loggedIn=$(m365 status) 
if [ "$loggedIn" == "Logged out" ]; then
    logError "You must login to Office 365 CLI!"
    exit
fi

loggedIn=$(m365 status --output json | jq -r '.connectedAs')
if [ $CONFIRM ]; then  
  logMsg "Logged into Office 365 CLI as ${loggedIn}. Continue using this connection? (y/n)?"
  read answer
  if [ "$answer" != "${answer#[Yy]}" ] ;then
    deleteO365Groups $FILTER
  else
      echo "Script exited!"
  fi
else 
    logInfo "Logged into Office 365 CLI as ${loggedIn}. Deleting Groups filtered by ${FILTER}."
    
    # ALWAYS MAKE SURE YOU KNOW WHICH TENANT YOU ARE CONNECTED TO!!!!
    # By providing a confirmation --yes you are DELETING O365 Groups.
    # If you delete a group inadvertantly quickly get the output id's 
    # and restore from Exchange Admin Center or by using the command
    # "o365 aad o365group restore --id [guid of group]"   
    deleteO365Groups $FILTER
fi
