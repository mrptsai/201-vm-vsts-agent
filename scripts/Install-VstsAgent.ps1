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
$PersonalAccessToken = $PersonalAccessToken | ConvertTo-SecureString -AsPlainText -Force
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
	$installedModules = Get-InstalledModule | Where-Object Name -like "$($Module.Name)*"
	Foreach ($installedModule in $installedModules)
	{
		Get-InstalledModule $installedModule.Name -AllVersions | Uninstall-Module -Verbose
	}

	if ($Module.Name -eq "AzureRM" -or ($Module.Name -notlike "AzureRM*" -and $Module.Name -notlike "Azure.*"))
	{ 
		Find-Module -Name $Module.Name -Repository Modules -Verbose | Install-Module -Force -Confirm:$false -SkipPublisherCheck -AllowClobber -Verbose
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
for ($i=0; $i -lt $AgentCount; $i++)
{
	$Agent = ($AgentName + "-" + $i)

	Write-Verbose "Configuring agent '$($Agent)'" -Verbose
	Install-VSTSAgent -Account $VSTSAccount -PAT $PersonalAccessToken -Name $Agent -Pool $PoolName -AgentDirectory "C:\Agents"
}
#endregion

# Uninstalling old Azure PowerShell Modules
$programName = "Microsoft Azure PowerShell"
$app = Get-WmiObject -Class Win32_Product -Filter "Name Like '$($programName)%'" -Verbose
$app.Uninstall()

Write-Verbose "Exiting InstallVSTSAgent.ps1" -Verbose
Restart-Computer -Force
#endregion