function Update-LogsearchShipper
{
	<#

	.SYNOPSIS
	Copies logshipper package and updates existing installation

	.DESCRIPTION
	Copies package either from UNC or HTTP to local drive, stops existing service, backs up current files, unzips new files, starts new service.

	.PARAMETER Version
	The Version of the desired update eg. 42
	
	.PARAMETER DestinationPath
	The current install directory of the service eg . D:\Apps\Logshipper
	
	.PARAMETER SourceRootPath
	The Source of the update package, excluding the package name. Can be UNC or Http.
	eg. http://ci-logsearch-shipper.s3-website-eu-west-1.amazonaws.com
	eg. \\myserver\logshipperpackages

	.EXAMPLE
	Update to version 42 via http
	Update-LogsearchShipper -Version 42 -DestinationPath 'D:\Apps\LogShipper' -SourceRootPath 'http://ci-logsearch-shipper.s3-website-eu-west-1.amazonaws.com'
	
	.EXAMPLE
	Update to version 42 via unc
	Update-LogsearchShipper -Version 42 -DestinationPath 'D:\Apps\LogShipper' -SourceRootPath '\\myserver\logshipperpackages'

	.NOTES
	Requires established EDB Data context - New-EDBServiceContext
	
	#>
	param 
	(
		[Parameter(Position=0, Mandatory=$true)]
		[string]$Version,
		[Parameter(Position=1, Mandatory=$true)]
		[string]$DestinationPath,
		[Parameter(Position=2, Mandatory=$true)]
		[string]$SourceRootPath
	)
	
	# --- Check destination exists...
	if (!(Test-Path $DestinationPath))
	{
		throw "Unable to find specified DestinationPath '$($DestinationPath)'"
		exit 1
	}
	
	# --- Setup some variable for use
	$IsUNC = $false
	$DestinationDrive = $DestinationPath.Split(":")[0] + ":\"
	$TempPath = "$($DestinationDrive)\Temp"
	$BackupPath = "D:\__BACKUP_DIRECTORY\$(Get-Date -Format yyyyMMdd HH-mm-ss)"
	$ShipperExeName = "LogsearchShipper.Service.exe"
	$ShipperExePath = "$($DestinationPath)\$($ShipperExeName)"
	$DestinationPackagePath = "$($TempPath)\logsearch-shipper.NET.v-$($Version).zip"
	$SourcePackagePath = "$($SourceRootPath)\logsearch-shipper.NET.v-$($Version).zip"
	
	# --- Check there is an existing install
	if (!(Test-Path $ShipperExePath))
	{
		throw "It doesnt look like a logshipper is installed and therefore cannot be upgraded - '$($ShipperExePath)'"
		exit 1
	}
	
	# --- Check the source is available and figure out source type
	if ($Source.StartsWith("\") -and (!($Source.ToLower().Contains("http"))))
	{
		Write-Debug "Source path suggests UNC..."
		if (!(Test-Path $SourcePackagePath))
		{
			throw "Unable to locate source at specified path '$($Source)'"
			exit 2
		}
		$IsUNC = $true
		try
		{
			Copy-Item -Path $SourcePackagePath -Destination $TempPath
		}
		catch [Exception]
		{
			throw $_.Exception.Message
			exit 3
		}
	}
	else
	{
		Write-Debug "Source path suggests http..."
		$webClient = New-Object System.Net.WebClient
		try
		{
			$webclient.DownloadFile($SourcePackagePath.Replace("\", "/"), $DestinationPackagePath)
		}
		catch [Exception]
		{
			throw $_.Exception.Message
			exit 3
		}
	}
	
	# --- Source should now be local... crack on... after one last check
	if (!(Test-Path $DestinationPackagePath))
	{
		throw "Unable to find package in expected location '$($DestinationPackagePath)'"
		exit 3
	}
	
	# --- Stop the existing service...
	$StopProcess = Start-Process -Path $ShipperExePath -ArgumentList @("stop") -Wait
	if (!($StopProcess.ExitCode -eq 0))
	{
		throw "Attempting to stop existing process caused exit code '$($StopProcess.ExitCode)'. Terminating as this is unknown."
		exit 4
	}
	
	# --- Back it up just in case...
	if (!(Test-Path $BackupPath))
	{
		New-Item -Path $BackupPath -ItemType "Directory" | Out-Null
	}
	Copy-Item -Path $DestinationPath -Destination $BackupPath -Recurse -Container
	
	# --- Unzip the new build
	try
	{
		$Shell = New-Object -ComObject shell.application
		$Zip = $Shell.NameSpace($DestinationPackagePath)
		foreach($Item in $Zip.Items())
		{
			$Shell.Namespace($DestinationPath).copyhere($Item)
		}
	}
	catch [Exception]
	{
		throw "An error occured during unzip process, please restore back from '$($BackupPath)'"
		exit 5
	}
	
	# --- Start the service and test its running...
	$StartProcess = Start-Process -Path $ShipperExePath -ArgumentList @("start") -Wait
	if (!($StartProcess.ExitCode -eq 0))
	{
		throw "Attempting to start updated process caused exit code '$($StartProcess.ExitCode)'. Terminating as this is unknown."
		exit 6
	}
	
	# --- Tidy up
	Remove-Item $DestinationPackagePath
}