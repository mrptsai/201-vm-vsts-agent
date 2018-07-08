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
	[string]$ModulesUri,

	[Parameter(Mandatory=$true)]
	[string]$PackagesUri
)

#region Variables
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
#endregion

#region Register Repositories, Install Chocolately
# Register Respositories
Register-PSRepository -Name Modules -SourceLocation $ModulesUri -InstallationPolicy Trusted
Register-PSRepository -Name Packages -SourceLocation $PackagesUri -InstallationPolicy Trusted

# Install and Upgrade Chocolatey
Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))
choco upgrade chocolatey
#endregion

#region Install Packages

$Packages = Find-Module -Repository Packages 
foreach ($Package in $Packages)
{
	choco install $Package.Name -s $PackagesUri --force -y
} 
#endregion

#region Install Modules
$Modules = Find-Module -Repository Modules

# Installing New Modules and Removing Old
Foreach ($Module in $Modules)
{	
	if ($Module.Name -eq "AzureRM" -or ($Module.Name -notlike "AzureRM*" -and $Module.Name -notlike "Azure.*"))
	{ 
		Install-Package -Name $Module.Name -Source $ModulesUri -ProviderName Nuget -Force -Confirm:$false -Verbose
	}
}

# Checking for multiple versions of modules 
$Mods = Get-InstalledModule

foreach ($Mod in $Mods)
{
  	$latest = Get-InstalledModule $Mod.Name -AllVersions | Select-Object -First 1
  	$specificMods = Get-InstalledModule $Mod.Name -AllVersions

	if ($specificMods.count -gt 1)
	{
		write-output "$($specificMods.count) versions of this module found [ $($Mod.Name) ]"
		foreach ($sm in $specificMods)
		{
			if ($sm.version -ne $latest.version)
			{ 
				write-output " $($sm.name) - $($sm.version) [highest installed is $($latest.version)]" 
				$sm | uninstall-module -force
			}
		}
	}
}

#region VSTS Agent
Import-Module VSTSAgent -Force -Verbose
for ($i=0; $i -lt $AgentCount; $i++)
{
	$Agent = ($AgentName + "-" + $i)
	if ($tmp = Get-VstsAgent -AgentDirectory "C:\Agents" -NameFilter $Agent)
	{
		Write-Verbose "Replacing agent '$($Agent)'" -Verbose
		Install-VSTSAgent -Account $VSTSAccount -PAT ($PersonalAccessToken | ConvertTo-SecureString -AsPlainText -Force) -Name $Agent -Pool $PoolName -AgentDirectory "C:\Agents" -Replace
	} else {
		Write-Verbose "Configuring agent '$($Agent)'" -Verbose
		Install-VSTSAgent -Account $VSTSAccount -PAT ($PersonalAccessToken | ConvertTo-SecureString -AsPlainText -Force) -Name $Agent -Pool $PoolName -AgentDirectory "C:\Agents"
	}	
}
#endregion

# Uninstalling old Azure PowerShell Modules
$programName = "Microsoft Azure PowerShell"
$app = Get-WmiObject -Class Win32_Product -Filter "Name Like '$($programName)%'" -Verbose
$app.Uninstall()

Write-Verbose "Exiting InstallVSTSAgent.ps1" -Verbose
Restart-Computer -Force
#endregion