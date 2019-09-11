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
  write "*****************************************************************"
  write "*"
  write "*      Function App Zip Deployment Script"
  write "*"
  write "*      Usage: ./$__base"
  write "*  "
  write "*  "
  write "*      Options:"
  write "*              -c | --confgiFile [config file path]  "
  write "*              -p | --prefix [resource group prefix] " 
  write "*              -s |--skipPrerequisiteChecks "
  write "*" 
  write "*      Example: Deploy the Function App to Azure for testing"
  write "*  "
  write "*      ./$__base -c ./config/development.settings.json -p debug2334 -s"
  write "*  "
  write "*  "
  write "*  "
  write "*****************************************************************"
  write
}

CONFIG_FILE=
RESOURCE_PREFIX=
SKIP_PREREQS=

# script arguments
while [ $# -gt 0 ]; do
  case $1 in
    -c|--configFile)
      shift
      CONFIG_FILE=$1
      ;;
    -p|--prefix)
      shift
      RESOURCE_PREFIX=$1
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

if [ -z "$CONFIG_FILE" ] || [ ! -f "$CONFIG_FILE" ] ; then
    echo "Configuration file issue"
    help
    exit
fi

if [ -z "$RESOURCE_PREFIX" ]; then
    echo "Prefix issue"
    help
    exit
fi

if [ -z "$SKIP_PREREQS" ]; then
  checkPrerequisites    
fi

# Default az command output to none (see az global arguments)
DEBUG_OUTPUT="none"

# Read configuration file content 
CONFIG=$(cat "$CONFIG_FILE")

# Set configuration values
CONFIGURATION=$(echo $CONFIG | jq -r '.Configuration')
FUNCTIONAPP_FOLDER=$(echo $CONFIG | jq -r '.FunctionAppFolder')
PUBLISH_FOLDER="${FUNCTIONAPP_FOLDER}/bin/${CONFIGURATION}/netcoreapp2.1/publish"
PUBLISH_ZIP=$(echo $CONFIG | jq -r '.PublishZip')

# clean the DIST folder as needed
clearDistFolder 

# Build and deploy source 
zipDeploy $CONFIGURATION $FUNCTIONAPP_FOLDER $PUBLISH_FOLDER $PUBLISH_ZIP $RESOURCE_PREFIX "${DEBUG_OUTPUT}" $__dir

