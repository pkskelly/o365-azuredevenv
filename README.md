# Provision Office 365 Azure Development Resources

This is a series of scripts and supporting files to provision Azure resources needed for common Office, SharePoint and Teams prototyping and development scenarios.

These scripts are things that are often needed for creating prototyping environments in Azure for Azure Functions, SharePoint Provisioning projects, Teams, SPFx and Office Apps projects and more.  Common Azure resources that are needed for these solutions are created and some configuration applied to enable quick prototyping and proofs of concepts applications.

Feel free to clone, copy or use as needed.  If something does not work for you, if you have suggestions, or want something documented better, please log an issue and I will try to respond and update.   If there is interest, or feedback to expand, I would love to make this more of a community effort. PR's welcome!

#SharingIsCaring

## Getting Started

Clone (or fork) this repository.

```bash
git clone https://github.com/pkskelly/o365-azuredevenv.git
```

Copy [sample.settings.json](./config/sample.settings.json) a ```developer.settings.json``` file.

Update your ```developer.settings.json``` file to have your information for your development environment.  

Open a terminal and run the ```create-devenv.sh``` script.

```bash
./create-devenv.sh ./config/developer.settings.json
```

## Azure Subscription

The scripts assume an Azure Subscription and access to create all resources.  The subscription information must be updated in a ```*.settings.json``` file for use by the main [create-devenv.sh](./create-devenv.sh) script.

## Requirements

The scripts assume several tools are installed and functional.  These include the following.  The script will check for these and will provide link for reference and installation.

* [jq](https://stedolan.github.io/jq/) - jq is a lightweight and flexible command-line JSON processor 
* [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli?view=azure-cli-latest) - a command-line tool providing a great experience for managing Azure resources.
* [Azure Functions Core Tools](https://github.com/Azure/azure-functions-core-tools) - provides a local development experience for creating, developing, testing, running, and debugging Azure Functions.
* [Office 365 CLI](https://pnp.github.io/office365-cli/) - enables managing Microsoft Office 365 tenant and SharePoint Framework projects on any platform.
* [Self-Destruct Azure CLI Extension](https://github.com/noelbundick/azure-cli-extension-noelbundick) - a grab bag of Azure CLI goodies from [Noel Bundick](https://www.noelbundick.com/)
