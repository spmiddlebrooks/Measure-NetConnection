<#
.SYNOPSIS
.DESCRIPTION
.PARAMETER
.EXAMPLE
.NOTES
	Version: 1.0
	Updated: 7/12/2017
	Author : Scott Middlebrooks
.LINK
#>
#Requires -Version 3.0

param (
[Parameter(Mandatory=$False,Position=0)]
		[string[]] $Uris #= @("https://webdir.online.lync.com","https://outlook.office365.com","https://www.google.com","sipfed.online.lync.com:443","sipdir.online.lync.com:443","global.tr.skype.com:443"),
[Parameter(Mandatory=$False,Position=1)]
		[ValidateScript({
			if ( Test-Path (Split-Path -Parent $_) ) {$True}
			else {Throw 'Invalid path'}
		})]		
		[string] $Path #= '.\Test.csv'
)

function Initialize-CsvFile {
param (
	[string] $Path
)

	$Header = 'DateTime,Method,TotalMilliseconds,Result,Notes'
	
	if (-Not (Test-Path $Path)) {
		Set-Content -Path $Path -Value $Header
	}
}

function Write-CsvFile {
param (
	[object] $Content,
	[string] $Path
)
	$Content | Export-Csv -NoTypeInformation -Append -Path $Path
}

function Test-TcpConnect {
[cmdletbinding ()]
param(
	[string] $Server,
	[int] $Port,
	[int] $Timeout = 3000 #Milliseconds
)

	$ErrorActionPreference = "SilentlyContinue"
	
	# Create TCP Client
	$tcpclient = new-Object system.Net.Sockets.TcpClient
	
	# Tell TCP Client to connect to machine on Port
	$iar = $tcpclient.BeginConnect($Server,$Port,$null,$null)
	
	# Set the wait time
	$wait = $iar.AsyncWaitHandle.WaitOne($Timeout,$false)
	
	# Check to see if the connection is done
	if(-Not $wait) {
		# Close the connection and report timeout
		$tcpclient.Close()
		Write-Verbose "Connection Timeout"
		Return $false
	}
	else {
		# Close the connection and report the error if there is one
		$error.Clear()
		$tcpclient.EndConnect($iar) | Out-Null
		if(-Not $?){
			Write-Verbose $error[0]
			$failed = $true
		}
		$tcpclient.Close()
	}
	
	# Return $true if connection Establish else $False
	if($failed) {
		return $false
	}
	else {
		return $true
	}	
}

function Measure-TcpConnect {
param (
	[string] $Server,
	[int] $Port,
	[int] $Timeout = 3000 #Milliseconds
)
	$DateTime = Get-Date -Format s
	
	if (Test-TcpConnect -Server $Server -Port $Port -Timeout $Timeout) {
		$Output = Measure-Command {Test-TcpConnect -Server $Server -Port $Port -Timeout $Timeout} | Select-Object TotalMilliseconds
		$Output | Add-Member -MemberType NoteProperty -Name 'DateTime' -Value $DateTime
		$Output | Add-Member -MemberType NoteProperty -Name 'Method' -Value 'TcpConnect'
		$Output | Add-Member -MemberType NoteProperty -Name 'Result' -Value "Success"
		$Output | Add-Member -MemberType NoteProperty -Name 'Notes' -Value "$($Server):$($Port)"
	}
	else {
		$Output = [PsCustomObject] @{
			DateTime = $DateTime
			Method = 'TcpConnect'
			TotalMilliseconds = 'N/A'
			Result = 'Error'
			Notes = "Could not connect to $($Server):$($Port)"
		}
	}

	return $Output
}

function Measure-WebRequest {
param (
	[string] $Uri,
	[int] $Timeout = 3 #Seconds
)
	$DateTime = Get-Date -Format s
	
	try {
		$Output = Measure-Command {$Request = Invoke-WebRequest -UseBasicParsing -Method GET -Uri $Uri -TimeoutSec $Timeout} | Select-Object TotalMilliseconds
		$Output | Add-Member -MemberType NoteProperty -Name 'DateTime' -Value $DateTime
		$Output | Add-Member -MemberType NoteProperty -Name 'Method' -Value 'WebRequest'
		$Output | Add-Member -MemberType NoteProperty -Name 'Result' -Value "Success"
		$Output | Add-Member -MemberType NoteProperty -Name 'Notes' -Value "HTTP Status Code: $($Request.StatusCode); GET $Uri"
	}
	catch {
		$Output = [PsCustomObject] @{
			DateTime = $DateTime
			Method = 'WebRequest'
			TotalMilliseconds = 'N/A'
			Result = "Error"
			Notes = "HTTP Status Code: $($_.Exception.Response.StatusCode.Value__); Could not GET $Uri"
		}
	}

	return $Output
}

##########################################################################################################################################################

Initialize-CsvFile -Path $Path

Foreach ($Uri in $Uris) {
	If ([System.Uri]::IsWellFormedUriString($Uri,[System.UriKind]::Absolute) -AND $Uri -match '^(https)?://.+') {
		$Data = Measure-WebRequest -Uri $Uri
		Write-CsvFile -Content $Data -Path $Path

		$Port = ([System.Uri]$Uri).Port
		$Uri = ([System.Uri]$Uri).Host
		$Data = Measure-TcpConnect -Server $Uri -Port $Port
		Write-CsvFile -Content $Data -Path $Path
	}
	Else {
		If ($Uri -Match ":\d+") {
			$Uri,$Port = $Uri.Split(":")
		}
		Else {
			$Port = 80
		}
		$Data = Measure-TcpConnect -Server $Uri -Port $Port -Path $Path
		Write-CsvFile -Content $Data -Path $Path
	}
}
