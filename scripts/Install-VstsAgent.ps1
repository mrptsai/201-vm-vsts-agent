# Downloads the Visual Studio Team Services Build Agent and installs on the new machine
# and registers with the Visual Studio Team Services account and build agent pool

# Enable -Verbose option
[CmdletBinding()]
Param
(
	[Parameter(Mandatory=$true)]
	[string]$VSTSAccount,

	[Parameter(Mandatory=$true)]
	[string]$PersonalAccessToken,

	[Parameter(Mandatory=$true)]
	[string]$AgentName,

	[Parameter(Mandatory=$true)]
	[string]$PoolName,

	[Parameter(Mandatory=$true)]
	[int]$AgentCount,

	[Parameter(Mandatory=$true)]
	[string]$AdminUser,

	[Parameter(Mandatory=$true)]
	[array]$Modules,

	[Parameter(Mandatory=$true)]
	[array]$Packages
)

#region Install Chocolately 
Get-PackageProvider -Name chocolatey -Force
#endregion

#region Install Packages
foreach ($Package in $Packages)
{
	Install-Package $Package.Name -RequiredVersion $Package.Version -Source chocolatey -Force
}
#endregion

#region Variables
$currentLocation = Split-Path -parent $MyInvocation.MyCommand.Definition
$tempFolderName = Join-Path $env:temp ([System.IO.Path]::GetRandomFileName())
$serverUrl = "https://$($VSTSAccount).visualstudio.com"
$modulesPath = "C:\Modules"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
#endregion

#region Modules
# Adding new Path to PSModulePath environment variable
$currentValue = [Environment]::GetEnvironmentVariable("PSModulePath", "Machine")
[Environment]::SetEnvironmentVariable("PSModulePath", $CurrentValue + ";$($modulesPath)", "Machine")
$newValue = [Environment]::GetEnvironmentVariable("PSModulePath", "Machine")
Write-Verbose "new Path is: $($newValue)" -verbose

# Creating new Path
if (Test-Path -Path $modulesPath -ErrorAction SilentlyContinue)
{	
	Remove-Item -Path $modulesPath -Recurse -Force -Confirm:$false -Verbose
	New-Item -ItemType Directory -Name Modules -Path C:\ -Verbose
} else
{
	New-Item -ItemType Directory -Name Modules -Path C:\ -Verbose
}

# Installing New Modules and Removing Old

Foreach ($Module in $Modules)
{	
	$installedModules = Get-InstalledModule | Where-Object Name -like "$($Module.Name)*"
	Foreach ($installedModule in $installedModules)
	{
		Get-InstalledModule $installedModule.Name -AllVersions | Uninstall-Module -Verbose
	}
	Find-Module -Name $Module.Name -RequiredVersion $Module.Version -Repository PSGallery -Verbose | Save-Module -Path $ModulesPath -Verbose 
	Install-Module -Name $Module.Name	
}

$DefaultModules = "PowerShellGet", "PackageManagement","Pester"

Foreach ($Module in $DefaultModules)
{
	if ($tmp = Get-Module $Module -ErrorAction SilentlyContinue) {	Remove-Module $Module -Force	}
	Find-Module -Name $Module -Repository PSGallery -Verbose | Install-Module -Force -Confirm:$false -SkipPublisherCheck -Verbose
}

#region VSTS Agent
for ($i=0; $i -lt $AgentCount; $i++)
{
	$Agent = ($AgentName + "-" + $i)

	Write-Verbose "Configuring agent '$($Agent)'" -Verbose
	$PersonalAccessToken = $PersonalAccessToken | ConvertTo-SecureString -AsPlainText -Force
	Install-VSTSAgent -Account $VSTSAccount -PAT $PersonalAccessToken -Name $Agent -Pool $PoolName
}
#endregion


# Uninstalling old Azure PowerShell Modules
$programName = "Microsoft Azure PowerShell"
$app = Get-WmiObject -Class Win32_Product -Filter "Name Like '$($programName)%'" -Verbose
$app.Uninstall()

Write-Verbose "Exiting InstallVSTSAgent.ps1" -Verbose
#endregion