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

#region Functions
Function Invoke-FileDownLoad
{
	param
	(
		[Parameter(Mandatory=$true)]
		[string]$Name,

		[Parameter(Mandatory=$true)]
		[string]$Uri,

		[Parameter(Mandatory=$true)]
		[string]$TempFolderName
	)

	$retryCount = 3
	$retries = 1
	Write-Verbose "Downloading $Name files" -verbose

	do
	{
		try
		{
			Invoke-WebRequest -Uri $Uri -Method Get -OutFile "$($TempFolderName)\$($Name).zip"
			Write-Verbose "Downloaded $($Name) successfully on attempt $retries" -verbose
			break
		} catch
		{
			$exceptionText = ($_ | Out-String).Trim()
			Write-Verbose "Exception occured downloading $($Name).zip: $($exceptionText) in try number $($retries)" -verbose
			$retries++
			Start-Sleep -Seconds 30 
		}
	} while ($retries -le $retryCount)
}

Function Expand-ZipFile
{
	param
	(
		[Parameter(Mandatory=$true)]
		[string]$Name,

		[Parameter(Mandatory=$true)]
		[string]$Path,

		[Parameter(Mandatory=$true)]
		[string]$TempFolderName
	)

	Write-Verbose "Extracting the zip file for $($Name)" -Verbose
	$destShellFolder = (new-object -com shell.application).namespace("$($Path)")
	$destShellFolder.CopyHere((new-object -com shell.application).namespace("$($TempFolderName)\$($Name).zip").Items(),16)
}
#endregion

#region Variables
$currentLocation = Split-Path -parent $MyInvocation.MyCommand.Definition
$tempFolderName = Join-Path $env:temp ([System.IO.Path]::GetRandomFileName())
$serverUrl = "https://$($VSTSAccount).visualstudio.com"
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

#region VSTS Agent
Write-Verbose "Current folder: $($currentLocation)" -verbose

#Create a temporary directory where to download from VSTS the agent package (vsts-agent.zip) and then launch the configuration.
New-Item -ItemType Directory -Force -Path $tempFolderName
Write-Verbose "Temporary download folder: $($tempFolderName)" -verbose
Write-Verbose "Server URL: $($serverUrl)" -Verbose

Write-Verbose "Trying to get download URL for latest VSTS agent release..."
$latestRelease = Invoke-RestMethod -Uri "https://api.github.com/repos/Microsoft/vsts-agent/releases"
$latestRelease = $latestRelease.assets | Where-Object name -like "*win-x64*" | Sort-Object created_at -Descending | Select-Object -First 1
Invoke-FileDownLoad -Name "vsts-agent" -Uri $latestRelease.browser_download_url -TempFolderName $tempFolderName

for ($i=0; $i -lt $AgentCount; $i++)
{
	$Agent = ($AgentName + "-" + $i)

	# Construct the agent folder under the main (hardcoded) C: drive.
	$agentInstallationPath = Join-Path "C:\Agents" $Agent
	
	# Create the directory for this agent.
	New-Item -ItemType Directory -Force -Path $agentInstallationPath
	
	# Set the current directory to the agent dedicated one previously created.
	Push-Location -Path $agentInstallationPath
	
	# Extract Download File
	Expand-ZipFile -Name "vsts-agent" -Path $agentInstallationPath -TempFolderName $tempFolderName

	# Removing the ZoneIdentifier from files downloaded from the internet so the plugins can be loaded
	# Don't recurse down _work or _diag, those files are not blocked and cause the process to take much longer
	Write-Verbose "Unblocking files" -verbose
	Get-ChildItem -Recurse -Path $agentInstallationPath | Unblock-File | out-null

	# Retrieve the path to the config.cmd file.
	$agentConfigPath = [System.IO.Path]::Combine($agentInstallationPath, 'config.cmd')
	Write-Verbose "Agent Location = $agentConfigPath" -Verbose
	if (![System.IO.File]::Exists($agentConfigPath))
	{
		Write-Error "File not found: $agentConfigPath" -Verbose
		return
	}

	# Call the agent with the configure command and all the options (this creates the settings file) without prompting
	# the user or blocking the cmd execution
	Write-Verbose "Configuring agent '$($Agent)'" -Verbose		
	.\config.cmd --unattended --url $serverUrl --auth PAT --token $PersonalAccessToken --pool $PoolName --agent $Agent --runasservice
	
	Write-Verbose "Agent install output: $LASTEXITCODE" -Verbose
	
	Pop-Location
}
#endregion

#region Install Modules
$Modules = Find-Module -Repository Modules | Where-Object {$_.Name -eq "AzureRM" -or ($_.Name -notlike "AzureRM*" -and $_.Name -notlike "Azure.*")} 

# Installing Modules
Foreach ($Module in $Modules)
{	
	Install-Module -Name $Module.Name -Repository Modules -Scope AllUsers -Force -Confirm:$false -SkipPublisherCheck -AllowClobber -Verbose
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

# Uninstalling old Azure PowerShell Modules
$programName = "Microsoft Azure PowerShell"
$app = Get-WmiObject -Class Win32_Product -Filter "Name Like '$($programName)%'" -Verbose
$app.Uninstall()

Write-Verbose "Exiting InstallVSTSAgent.ps1" -Verbose
Restart-Computer -Force
#endregion
