<# Copyright 2016 Skytap Inc.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
#>

if ($PSBoundParameters['Debug']) {
	$DebugPreference = 'Continue'
}

if ($PSVersionTable.PSVersion.major -lt 4) {
	write-host "This module requires Powershell Version 4" -foregroundcolor "magenta"
	return
}

# use TLS 1.2 rather than powershell default of 1.0
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function LogWrite ([string]$logthis) {              # logwrite INFO This is Info   -- logwrite DEBUG this is debuggin
	$d = get-date -f o
	#$loglevel = $logString.split(" ")[0]
	#$logstring = $d + $logthis.replace($loglevel,'')
	$logstring = $d + '  ' + $logthis
	add-content -Path $logfile -Value $logstring
}	
	

function Set-Authorization ([string]$tokenfile='user_token', [string]$user, [string]$pwd) {
<#
    .SYNOPSIS
      Creates authorization headers from file or parameters
    .SYNTAX
       Add-ConfigurationToProject EnvironmentId ProjectId
    .EXAMPLE
      Add-ConfigurationToProject 12345 54321
#>
	  if ($user) {    #use params instead of file 
		  $username = $user
		  $password = $pwd
	  } else {
		  if (Test-Path $tokenfile) {
			Get-Content $tokenfile | Foreach-Object{
			   $var = $_.Split('=')
			   Set-Variable -Name $var[0] -Value $var[1]
				}
		  } else {
				Write-host "The user_token file $tokenfile was not found" -foregroundcolor "magenta"
		  		return -1 }
		
		
	  }
	Write-host "Skytap user is $username"
	$auth = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $username,$password)))
	$global:headers = @{"Accept" = "application/json"; Authorization=("Basic {0}" -f $auth)}
	$global:logfile = $logfile
	$global:account = $account
	return 0
}

Set-Authorization
$global:url = "https://cloud.skytap.com"
$global:tOffset = 0
$global:errorResponse = ''

function Show-RequestFailure  {
	$ex = $global:errorResponse
	if ($ex.gettype().fullname -eq 'System.Net.WebException') {
		$nob = New-Object -TypeName psobject -Property @{
		requestResultCode = [int]$ex.HResult
		eDescription = $ex.gettype()
		eMessage = $ex.Message
		method = $ex.Source
		}
		
       }else{
		$eresp = $ex.response 
		$errorResponse = $eresp.GetResponseStream()
		$reader = New-Object System.IO.StreamReader($errorResponse)
		$reader.BaseStream.Position = 0
		$reader.DiscardBufferedData()
		$responseBody = $reader.ReadToEnd();
		$nob = New-Object -TypeName psobject -Property @{
			requestResultCode = [int]$eresp.StatusCode
			eDescription = $eresp.StatusDescription
			eMessage = $responseBody
			method = $eresp.Method
		}
	}
	$global:errorResponse = ''
	return $nob
}
	
function Show-WebRequestFailure ($theException){
	#write-host $theException
           if ($theException){
               if($theException.Response) {
                   $createResultStatus = $theException.Response.StatusCode.value__
                   $createResultStatusDescription = $theException.Response.StatusDescription
               }
               else {
                   $createResultStatus = "-1"
                   $createResultStatusDescription = $theException.Message
               }
           }
	$nob = New-Object -TypeName psobject -Property @{
		requestResultCode = $createResultStatus
		eDescription = $createResultStatusDescription
	}
	return $nob
}	


function Add-ConfigurationToProject ([string]$configId, [string]$projectId ){
 <#
    .SYNOPSIS
      Adds an environment to a project
    .SYNTAX
       Add-ConfigurationToProject EnvironmentId ProjectId
    .EXAMPLE
      Add-ConfigurationToProject 12345 54321
  #>
	try {
		$uri = "$url/projects/$projectId/configurations/$configId"
		$result = Invoke-RestMethod -Uri $uri -Method POST -ContentType "application/json" -Headers $headers 
		$result | Add-member -MemberType NoteProperty -name requestResultCode -value 0
			} catch { 
				$global:errorResponse = $_.Exception
				$result = Show-RequestFailure
				return $result
		}
		return $result
	}
	
function Copy-Configuration ([string]$configId, [string]$vlist ){
 <#
    .SYNOPSIS
     Copy a configuration or copy selected vms in a configuration
    .SYNTAX
       Copy-Configuration EnvironmentId $vlist
    .EXAMPLE
      Copy-Configuration 12345
      or
      $vlist = @("22222","33333")
      Copy-Configuration 12345 $vlist
  #>

	try {
		if ($vlist) {
				
			$body = @{
					configuration_id = $configId
					vm_ids = @($vlist)
				}
		    } else {
		    	$body = @{
		    		    configuration_id = $configId
		    	}
		    }
		write-host $body.keys
		write-host $body.values

		$uri =  "$url/configurations"
		$result = Invoke-RestMethod -Uri $uri -Method POST -Body (ConvertTo-Json $body) -ContentType "application/json" -Headers $headers 
		$result | Add-member -MemberType NoteProperty -name requestResultCode -value 0
			} catch { 
				$global:errorResponse = $_.Exception
				$result = Show-RequestFailure
				return $result
		}
		return $result
	}

function Edit-Configuration ( [string]$configId, $configAttributes ){
<#
    .SYNOPSIS
      Change environment attributes
    .SYNTAX
       Edit-Configuration  ConfigId Attribute-Hash
    .EXAMPLE
      Edit-Configuration 12345 @{name='config 1234'; description='windows v10'}
      
      Or
      
      $Attrib = @{name='config 1234'; description='windows v10'}
      Edit-Configuration 12345 $Attrib
  #>
	try {
		$uri = "$url/configurations/$configId"
		
		$body = $configAttributes
		$result = Invoke-RestMethod -Uri $uri -Method PUT -Body (ConvertTo-Json $body)  -ContentType "application/json" -Headers $headers 
		$result | Add-member -MemberType NoteProperty -name requestResultCode -value 0
			} catch { 
				$global:errorResponse = $_.Exception
				$result = Show-RequestFailure
				return $result
		}
	return $result
	}
	
Set-Alias Edit-Environment Edit-Configuration 

function Edit-VM ( [string]$configId, $vmid, $vmAttributes ){
<#
     .SYNOPSIS
      Change VM attributes
    .SYNTAX
       Edit-VM  ConfigId VMId Attribute-Hash
    .EXAMPLE
      Edit-VM 12345 54321 @{name='my vm'; description='windows v10'}
      
      Or
      
      $Attrib = @{name='my vm'; description='windows v10'}
      Edit-Configuration 12345 54321 $Attrib
      
  #>
	try {
		$uri = "$url/configurations/$configId/vms/$vmid/"
		
		$body = $vmAttributes
		$result = Invoke-RestMethod -Uri $uri -Method PUT -Body (ConvertTo-Json $body)  -ContentType "application/json" -Headers $headers 
		$result | Add-member -MemberType NoteProperty -name requestResultCode -value 0
			} catch { 
				$global:errorResponse = $_.Exception
				$result = Show-RequestFailure
				return $result
		}
	return $result
	}
	
function Add-NetworkAdapter([string]$configId, $vmid, [string]$nicType="default"){
<#
     .SYNOPSIS
      Change network interface attributes
    .SYNTAX
       Add-NetworkAdapter  ConfigId VMId NIC-TYPE
       For x86 VMs, one of: default, e1000, pcnet32, vmxnet, vmxnet3, or e1000e.
       For Power VMs, must be default.
    .EXAMPLE
      Add-NetworkAdapter 12345 54321 vmxnet3
 #>
	try {
		$uri = "$url/configurations/$configId/vms/$vmid/interfaces/$interfaceId"
		
		$body = @{nic_type = $nicType }

		$result = Invoke-RestMethod -Uri $uri -Method Post -Body (ConvertTo-Json $body)  -ContentType "application/json" -Headers $headers 
		$result | Add-member -MemberType NoteProperty -name requestResultCode -value 0
			} catch { 
				$global:errorResponse = $_.Exception
				$result = Show-RequestFailure
				return $result
		}
	return $result
	}
	
Set-Alias Add-Adapter Add-NetworkAdapter	
	
function Edit-NetworkAdapter ( [string]$configId, $vmid, $interfaceId, $interfaceAttributes ){
<#
     .SYNOPSIS
      Change network interface attributes
    .SYNTAX
       Edit-NetworkAdapter  ConfigId VMId interfaceId Attribute-Hash
    .EXAMPLE
      Edit-NetworkAdapter 12345 54321 44444 @{hostname='my vm'; ip='10.10.1.1'}
      
      Or
      
      $Attrib = @{hostname='my vm';  ip='10.10.1.1'}
      Edit-NetworkAdapter 12345 54321 44444 $Attrib
      
  #>
	try {
		$uri = "$url/configurations/$configId/vms/$vmid/interfaces/$interfaceId"
		
		$body = $interfaceAttributes
		$result = Invoke-RestMethod -Uri $uri -Method PUT -Body (ConvertTo-Json $body)  -ContentType "application/json" -Headers $headers 
		$result | Add-member -MemberType NoteProperty -name requestResultCode -value 0
			} catch { 
				$global:errorResponse = $_.Exception
				$result = Show-RequestFailure
				return $result
		}
	return $result
	}
	
Set-Alias Edit-Adapter Edit-NetworkAdapter

function Edit-VMUserdata ( [string]$configId, $vmid, $userdata ){
<#
    .SYNOPSIS
      Change userdata 
    .SYNTAX
       Edit-VMUserdata ConfigId VMid Contents
       {
	"contents": "Text you want saved in the user data field"
	}
    .EXAMPLE
      Edit-VMUserdata 12345  54321 @{contents="text for userdata field"}
      Or
      $userdata = @{"contents"="This machine does not conform"}
      Edit-VMUserdata 12345 54321 $userdata
      
  #>
	try {
		$uri = "$url/configurations/$configId/vms/$vmid/user_data"
		
		$body = $userdata
		$result = Invoke-RestMethod -Uri $uri -Method PUT -Body (ConvertTo-Json $body)  -ContentType "application/json" -Headers $headers 
		$result | Add-member -MemberType NoteProperty -name requestResultCode -value 0
			} catch { 
				$global:errorResponse = $_.Exception
				$result = Show-RequestFailure
				return $result
		}
	return $result
	}
	
		
	
function Update-RunState ( [string]$configId, [string]$newstate, [string]$vmId ){
<#
    .SYNOPSIS
      Change and environments runstate
    .SYNTAX
       Update-RunState ConfigId State
    .EXAMPLE
      Update-RunState 12345 running
  #>
	try {
		if ($vmId){
			$uri = "$url/configurations/$configId/vms/$vmId"
		}else{
			$uri = "$url/configurations/$configId"
		}
		
		$body = @{
			runstate = $newstate
		}
		$result = Invoke-RestMethod -Uri $uri -Method PUT -Body (ConvertTo-Json $body)  -ContentType "application/json" -Headers $headers 
		$result | Add-member -MemberType NoteProperty -name requestResultCode -value 0
			} catch { 
				$global:errorResponse = $_.Exception
				$result = Show-RequestFailure
				return $result
		}
	return $result
	}

function Connect-Network ([string]$sourceNetwork, [string]$destinationNetwork){
<#
    .SYNOPSIS
      Connect two networks
    .SYNTAX
       Connect-Network Source-Network Destination-Network
    .EXAMPLE
      Connect-Network 78901 10987
  #>
	try {
		$uri = "$url/tunnels"
		$body = @{
				source_network_id = $sourceNetwork
				target_network_id = $destinationNetwork
			}
		$result = Invoke-RestMethod -Uri $uri -Method POST -Body (ConvertTo-Json $body) -ContentType "application/json" -Headers $headers 
		$result | Add-member -MemberType NoteProperty -name requestResultCode -value 0
			} catch {
				$global:errorResponse = $_.Exception
				$result = Show-RequestFailure
				return $result
		}
	return $result
	}

function Remove-Network ([string]$tunnel){
<#
    .SYNOPSIS
      Remove ICNR Tunnel
    .SYNTAX
       Remove-Network TunnelId
    .EXAMPLE
      Remove-Network tunnel-123456-789012
  #>
	try {
		$uri = "$url/tunnels/$tunnel"

		$result = Invoke-RestMethod -Uri $uri -Method DELETE -ContentType "application/json" -Headers $headers 
		$result | Add-member -MemberType NoteProperty -name requestResultCode -value 0
			} catch {
				$global:errorResponse = $_.Exception
				$result = Show-RequestFailure
				return $result
		}
	return $result
	}	

function New-EnvironmentfromTemplate ( [string]$templateId ){
<#
    .SYNOPSIS
      Create a new environment from a template
    .SYNTAX
       New-EnvironmentfromTemplate templateId
       Returns new environment ID
    .EXAMPLE
      New-EnvironmentfromTemplate 12345
  #>
	try {
		$uri = "$global:url/configurations"
		$body = @{
				template_id = $templateId 
				}
		$result = Invoke-RestMethod -Uri $uri -Method POST -Body (ConvertTo-Json $body) -ContentType "application/json" -Headers $global:headers 
		$result | Add-member -MemberType NoteProperty -name requestResultCode -value 0

			} catch { 
				$global:errorResponse = $_.Exception
				$result = Show-RequestFailure
				return $result
			}
		return $result
	
	}

function New-Project( [string]$projectName="New Project", [string]$projectDescription=" " ){
<#
    .SYNOPSIS
      Create a new project
    .SYNTAX
       New-Project Name [Description]
       Returns new project ID
    .EXAMPLE
      New-Project "Global Training"  "This is a training project"
      ---
      New-Project -projectName "Global Training" -projectDescription "A project for global training"
  #>
	if ($projectName -eq 'New Project' ) {
		write-host 'please supply a project name'
		$result = [psobject] @{ eMessage  = 'Please supply a project name'; requestResultCode = '-1' }
		return result
	}
	try {
		$uri = "$global:url/projects"
		$body = @{
				name = $projectName
				summary = $projectDescription
				}
		$result = Invoke-RestMethod -Uri $uri -Method POST -Body (ConvertTo-Json $body) -ContentType "application/json" -Headers $global:headers 
		$result | Add-member -MemberType NoteProperty -name requestResultCode -value 0

			} catch { 
				$global:errorResponse = $_.Exception
				$result = Show-RequestFailure
				return $result
			}
		return $result
	
	}

function Publish-URL ([string]$configId, [string]$ptype, [string]$pname,[Boolean]$sso=$False) { 
<#
    .SYNOPSIS
      Create a published url for an environment 
    .SYNTAX
       Publish-URL configId [type] [name]
       Returns new URL ID
    .EXAMPLE
      Publish-URL 12345 multiple_url "Class 123"
  #>
		try {
			$uri = "$global:url/configurations/$configId/publish_sets"
			if ($ptype) {
				$type = $ptype
			} else {
				$type = "single_url"
					}
			if ($pname) {
				$name = $pname 
			} else {
				$name = "Published set - $type" 
					}
			if ($sso) {
				$body = @{
						name = $name
						publish_set_type = $type
						sso_required = $sso
						}
				}else{
					$body = @{
						name = $name
						publish_set_type = $type
						}
					}
					
			$result = Invoke-RestMethod -Uri $uri -Method POST -Body (ConvertTo-Json $body) -ContentType "application/json" -Headers $global:headers 
			$result | Add-member -MemberType NoteProperty -name requestResultCode -value 0
				} catch { 
					$global:errorResponse = $_.Exception
					$result = Show-RequestFailure
					return $result
				}
			return $result
			}
			
function Edit-PublishSet ( [string]$configId, [string]$publishSetId, $configAttributes ){
<#
    .SYNOPSIS
      Change Publish Set attributes
    .SYNTAX
       Edit-PublishSet ConfigId PublishSetId Attribute-Hash
    .EXAMPLE
      Edit-PublishSet 12345 12345 @{name='config 1234'; password='secret'}
  #>
	try {
		$uri = "$url/configurations/$configId/publish_sets/$publishSetId"
		
		$body = $configAttributes
		$result = Invoke-RestMethod -Uri $uri -Method PUT -Body (ConvertTo-Json $body)  -ContentType "application/json" -Headers $headers 
		$result | Add-member -MemberType NoteProperty -name requestResultCode -value 0
			} catch { 
				$global:errorResponse = $_.Exception
				$result = Show-RequestFailure
				return $result
		}
	return $result
	}

function Save-ConfigurationToTemplate ([string]$configId, [string]$selectedVMs, [string]$selectedNetworks="none", [string]$tname) {
<#
    .SYNOPSIS
      Save an environment as a template
    .SYNTAX
       Save-ConfigurationToTemplate configId selectedVMs selectedNetworks tname
       Returns template ID
    .EXAMPLE
      Save-ConfigurationToTemplate -configId 12345 -selectedVMs 686868
  #>
	try {
			$uri = "$url/templates"
			$body = @{
				configuration_id = $configId
				
			}
			if ($tname) {
				$name = $tname 
				$body += @{
					name = $name
				}
			}
			if ($selectedVMs) {
				$vms = @($selectedVMs)
				$body += @{
					vm_instance_multiselect = $vms
				}
			}

			if ($selectedNetworks) { 
				if ($selectedNetworks = 'none') {
					$networks = @()
				}else{
					$networks = @($selectedNetworks)
				}
				$body += @{
					network_multiselect = $networks
				}
			}
			write-host (convertto-json $body)
			$result = Invoke-RestMethod -Uri $uri -Method POST -Body (ConvertTo-Json $body) -ContentType "application/json" -Headers $headers 
			$result | Add-member -MemberType NoteProperty -name requestResultCode -value 0
				} catch { 
					$global:errorResponse = $_.Exception
					$result = Show-RequestFailure
					return $result
			}
			return $result
		}
Set-Alias  Save-EnvironmentToTemplate Save-ConfigurationToTemplate
		
function Remove-Configuration ([string]$configId) {
<#
    .SYNOPSIS
      Remove (DELETE) an environment
    .SYNTAX
       Remove-Configuration
    .EXAMPLE
      Remove-Configuration 12345 
  #>
	try {
			$uri = "$url/configurations/$configId"
			
			$result = Invoke-RestMethod -Uri $uri -Method DELETE -ContentType "application/json" -Headers $headers 
			$result | Add-member -MemberType NoteProperty -name requestResultCode -value 0
				} catch { 
					$global:errorResponse = $_.Exception
					$result = Show-RequestFailure
					return $result
			}
			return $result
		}
Set-Alias  Remove-Environment Remove-Configuration
		
function Remove-Template ([string]$templateId) {
<#
    .SYNOPSIS
      Remove (DELETE) a template
    .SYNTAX
       Remove-Template
    .EXAMPLE
      Remove-Template 12345 
  #>
	try {
			$uri = "$url/templates/$templateId"
			write-host $uri
			$result = Invoke-RestMethod -Uri $uri -Method DELETE -ContentType "application/json" -Headers $headers 
			$result | Add-member -MemberType NoteProperty -name requestResultCode -value 0
				} catch { 
					$global:errorResponse = $_.Exception
					$result = Show-RequestFailure
					return $result
			}
			return $result
		}


function Remove-Tag ([string]$configId, [string]$tagId) {
<#
    .SYNOPSIS
      Remove (DELETE) tag
    .SYNTAX
       Remove-Tag $tag_id 
    .EXAMPLE
      Remove-Tag -configId 5456555 -tagId 12345 
      Remove-Tag 5456555 12345
      Remove-Tag 5456555 ALL
  #>

	$uri = "$url/configurations/$configId/tags/$tagId"
	if ($tagId -eq "All") {
		$oldTags = get-tags $configId
		 foreach ($tag in $oldTags) {
		 	 try {
				$result = Invoke-RestMethod -Uri $uri -Method DELETE -ContentType "application/json" -Headers $headers 
				$result | Add-member -MemberType NoteProperty -name requestResultCode -value 0
				} catch { 
					$global:errorResponse = $_.Exception
					$result = Show-RequestFailure
					return $result
				}
			}					
	} else {
		try {
			$result = Invoke-RestMethod -Uri $uri -Method DELETE -ContentType "application/json" -Headers $headers 
			$result | Add-member -MemberType NoteProperty -name requestResultCode -value 0
			} catch { 
				$global:errorResponse = $_.Exception
				$result = Show-RequestFailure
				return $result
		}
	}	
	return $result
}		


function Remove-Project ([string]$projectId) {
<#
    .SYNOPSIS
      Remove (DELETE) a project
    .SYNTAX
       Remove-Project
    .EXAMPLE
      Remove-Project 12345 
  #>
	try {
			$uri = "$url/Projects/$projectId"
			
			$result = Invoke-RestMethod -Uri $uri -Method DELETE -ContentType "application/json" -Headers $headers 
			$result | Add-member -MemberType NoteProperty -name requestResultCode -value 0
				} catch { 
					$global:errorResponse = $_.Exception
					$result = Show-RequestFailure
					return $result
			}
			return $result
		}

function Add-TemplateToProject ([string]$projectId, [string]$templateId) {
<#
    .SYNOPSIS
      Adds an template to a project
    .SYNTAX
       Add-TemplateToProject TemplateId ProjectId
    .EXAMPLE
      Add-TemplateToProject  12345 54321
  #>
		try {
		$uri = "$url/projects/$projectId/templates/$templateId"
		$result = Invoke-RestMethod -Uri $uri -Method POST -ContentType "application/json" -Headers $headers 
		$result | Add-member -MemberType NoteProperty -name requestResultCode -value 0
			} catch { 
				$global:errorResponse = $_.Exception
				$result = Show-RequestFailure
				return $result
		}
		return $result
	}

function Add-TemplateToConfiguration ([string]$configId, [string]$templateId) {
<#
    .SYNOPSIS
      Adds an template to an environment
    .SYNTAX
       Add-TemplateToConfiguration EnvironmentId TemplateId 
    .EXAMPLE
      Add-TemplateToConfiguration  12345 54321
  #>
	try {
		$uri = "$global:url/configurations/$configId"
		$body = @{
				template_id = $templateId 
				}
		$result = Invoke-RestMethod -Uri $uri -Method PUT -Body (ConvertTo-Json $body) -ContentType "application/json" -Headers $global:headers 
		$result | Add-member -MemberType NoteProperty -name requestResultCode -value 0

			} catch { 
				$global:errorResponse = $_.Exception
				$result = Show-RequestFailure
				return $result
			}
		return $result
	
	}
Set-Alias  Add-TemplateToEnvironment Add-TemplateToConfiguration
	
function Add-User ([string]$loginName,[string]$firstName, [string]$lastName,[string]$email,[string]$accountRole="restricted_user",[boolean]$can_import=$False,[string]$can_export=$False,[string]$time_zone='Pacific Time (US & Canada)',[string]$region='US-West') {
<#
    .SYNOPSIS
      Adds a new user
    .SYNTAX
       Add-User Login-name First-name Last-Name Email-Address Account-Role
    .EXAMPLE
      Add-User mmeasel mike measel mmeasel@skytap.com admin
  #>
	try {
		$uri = "$global:url/v1/users"
		$body = @{
				login_name = $loginName
				email = $email
				first_name = $firstName
				last_name = $lastName
				account_role = $accountRole
				time_zone = $time_zone
				can_import = $can_import
				can_export = $can_export
				default_region = $region
				}
		$str = $body | out-string
		write-host $str
		$result = Invoke-RestMethod -Uri $uri -Method POST -Body (ConvertTo-Json $body) -ContentType "application/json" -Headers $global:headers 
		$result | Add-member -MemberType NoteProperty -name requestResultCode -value 0

			} catch { 
				$global:errorResponse = $_.Exception
				$result = Show-RequestFailure
				return $result
			}
		return $result
	
	}
	
function Add-Group ([string]$groupName,[string]$description) {
<#
    .SYNOPSIS
      Adds a new group
    .SYNTAX
       Add-Group Name Description
    .EXAMPLE
      Add-Group EastUsers "Users in east region"
  #>
	try {
		$uri = "$global:url/groups"
		$body = @{
				name = $groupName
				description = $description
				}
		$result = Invoke-RestMethod -Uri $uri -Method POST -Body (ConvertTo-Json $body) -ContentType "application/json" -Headers $global:headers 
		$result | Add-member -MemberType NoteProperty -name requestResultCode -value 0

			} catch { 
				$global:errorResponse = $_.Exception
				$result = Show-RequestFailure
				return $result
			}
		return $result
	
	}
function Add-Department ([string]$deptName,[string]$description) {
<#
    .SYNOPSIS
      Adds a new department
    .SYNTAX
       Add-Department Name Description
    .EXAMPLE
      Add-Department Accounting "Users in east region"
  #>
	try {
		$uri = "$global:url/departments"
		$body = @{
				name = $deptName
				description = $description
				}
		$result = Invoke-RestMethod -Uri $uri -Method POST -Body (ConvertTo-Json $body) -ContentType "application/json" -Headers $global:headers 
		$result | Add-member -MemberType NoteProperty -name requestResultCode -value 0

			} catch { 
				$global:errorResponse = $_.Exception
				$result = Show-RequestFailure
				return $result
			}
		return $result
	
	}
		
function Publish-Service ([string]$configId, [string]$vmId, [string]$interfaceId, [string]$serviceId, [string]$port) {
<#
    .SYNOPSIS
      Create a published service for an environment 
    .SYNTAX
       Publish-Service configId vmId interfaceId serviceId port_Number
       Returns new service url
    .EXAMPLE
      Publish-Service 12345 54321 11111 22222 8080
  #>
			try {
			$uri = "$global:url/configurations/$configId/vms/$vmId/interfaces/$interfaceId/services/$serviceId"
			
			$body = @{
					port = $port
					}
			$result = Invoke-RestMethod -Uri $uri -Method POST -Body (ConvertTo-Json $body) -ContentType "application/json" -Headers $global:headers 
			$result | Add-member -MemberType NoteProperty -name requestResultCode -value 0
				} catch { 
					$global:errorResponse = $_.Exception
					$result = Show-RequestFailure
					return $result
				}
			return $result
			}

function Get-PublishedURLs ([string]$configId) {
<#
    .SYNOPSIS
      Get published URLs for an environment 
    .SYNTAX
       Get-PublishedURLs configId 
       Returns list of URLs
    .EXAMPLE
      Get-PublishedURLs 12345 
  #>
		try {
			$uri = "$global:url/configurations/$configId/publish_sets"
			$result = Invoke-RestMethod -Uri $uri -Method GET -ContentType "application/json" -Headers $global:headers 
			$result | Add-member -MemberType NoteProperty -name requestResultCode -value 0
				} catch { 
					$global:errorResponse = $_.Exception
					$result = Show-RequestFailure
					return $result
				}
			return $result
			}
			
function Get-PublishedURLDetails ([string]$url) {
<#
    .SYNOPSIS
      Get published URL details
    .SYNTAX
       Get-PublishedURLDetails url
       Returns published url objects
    .EXAMPLE
      Get-PublishedURLDetails https://cloud.skytap.com/configurations/3125360/publish_sets/878322 
  #>
		try {
			$uri = $url
			$result = Invoke-RestMethod -Uri $uri -Method GET -ContentType "application/json" -Headers $global:headers 
			$result | Add-member -MemberType NoteProperty -name requestResultCode -value 0
				} catch { 
					$global:errorResponse = $_.Exception
					$result = Show-RequestFailure
					return $result
				}
			return $result
			}

function Get-PublishedServices ([string]$configId, [string]$vmId, [string]$interfaceId){
<#
    .SYNOPSIS
      Get published services for an environment 
    .SYNTAX
       Get-PublishedServices configId vmId interfaceId
       Returns service(s) list object
    .EXAMPLE
      Get-PublishedURLs 12345 
  #>
			try {
			$uri = "$global:url/configurations/$configId/vms/$vmId/interfaces/$interfaceId/services"
			$result = Invoke-RestMethod -Uri $uri -Method GET -ContentType "application/json" -Headers $global:headers 
			$result | Add-member -MemberType NoteProperty -name requestResultCode -value 0
				} catch { 
					$global:errorResponse = $_.Exception
					$result = Show-RequestFailure
					return $result
				}
			return $result
			}

function Get-VMs ([string]$configId, [string]$vm) {
<#
    .SYNOPSIS
      Get VMs for an environment 
    .SYNTAX
       Get-VMs configId [vmId]
       Returns vm(s) list object
    .EXAMPLE
    	  All VMs in an environment
      Get-VMs 12345 
        Only specific VM details
      Get-VMs 12345 54321 
  #>
			try {
				if ($vm){
					$uri = "$global:url/configurations/$configId/vms/$vm"
				}else{
					$uri = "$global:url/configurations/$configId/vms"
				}
				$result = Invoke-RestMethod -Uri $uri -Method GET -ContentType "application/json" -Headers $global:headers 
				$result | Add-member -MemberType NoteProperty -name requestResultCode -value 0
					} catch { 
						$global:errorResponse = $_.Exception
						$result = Show-RequestFailure
						return $result
					}
				return $result
				}
				
function Get-VMUserData ([string]$configId, [string]$vm) {
<#
    .SYNOPSIS
      Get VM userdata ( part of metadata )
    .SYNTAX
       Get-VM configId vmId
       Returns vm userdata
    .EXAMPLE
      Get-VMUserdata 12345 54321 
  #>
			try {				
				$uri = "$global:url/configurations/$configId/vms/$vm/user_data"
				$result = Invoke-RestMethod -Uri $uri -Method GET -ContentType "application/json" -Headers $global:headers 
				$result | Add-member -MemberType NoteProperty -name requestResultCode -value 0
					} catch { 
						$global:errorResponse = $_.Exception
						$result = Show-RequestFailure
						return $result
					}
				return $result
				}

function Get-Projects ([string]$projectId,[string]$attributes,[string]$v2="T",[int]$startCount="100",[string]$qscope="company") {
<#
    .SYNOPSIS
      Get projects
    .SYNTAX
        Get-Projects
       Returns service(s) list object
    .EXAMPLE
       Get-Projects
  #>
   $more_records = $True
  		if ($v2 -eq 'T') {
				While ($more_records) {
  					try {
						if ($attributes){
							$uri = $global:url + '/v2/projects?scope=' + $qscope + '&count=' + $startCount + '&offset=' + $global:tOffset + '&query=' + $attributes
						}else{
							if ($projectId){	
								$uri = $global:url + '/v2/projects/' + $projectId
							}else{
								$uri = $global:url + '/v2/projects?scope=' + $qscope + '&count=' + $startCount + '&offset=' + $global:tOffset
								}
							}
						write-host $uri
						$result = Invoke-WebRequest -Uri $uri -Method GET -ContentType 'application/json' -Headers $global:headers  	-UseBasicParsing									
							} catch { 
								$result = Show-WebRequestFailure($_.Exception)
								return $result
							}												
						$hold_result = $hold_result + (ConvertFrom-Json $result.Content)
						$hdr = $result.headers['Content-Range']
						#write-host "header" $hdr
						if ($hdr.length -gt 0) {
							$hcounters = $hdr.Split('-')[1]
							[Int]$lastItem,[int]$itemTotal = $hcounters.Split('/')
							write-host "counts " $lastItem $itemTotal
							if (($lastItem + 1)  -lt ($itemTotal)){                                         
								$global:tOffset = $lastItem + 1
							}
							else 
							{
								$more_records = $False
							}
						}
						else 
						{
							$more_records = $False
						}
					}
					$result =  $hold_result
					$result | Add-member -MemberType NoteProperty -name requestResultCode -value 0
					$global:tOffset = 0
					return $result
					
				} else {
					try {
					if ($projectId){
						$uri = "$global:url/projects/$projectId"
					}else{
						$uri = "$global:url/projects"
					}
					$result = Invoke-RestMethod -Uri $uri -Method GET -ContentType "application/json" -Headers $global:headers 
					$result | Add-member -MemberType NoteProperty -name requestResultCode -value 0
						} catch { 
							$global:errorResponse = $_.Exception
							$result = Show-RequestFailure			
						}
						if ($result.StatusCode -ne 200) {
							write-host $result.StatusCode
							write-host $result.StatusDescription
							return $result
									}
				return $result
				}
}

function Get-ProjectEnvironments ([string]$projectId){
<#
    .SYNOPSIS
      Get all environments for a project
    .SYNTAX
        Get-ProjectEnvironments projectId
       Returns Environment(s) list object
    .EXAMPLE
       Get-ProjectConfiguration 654321
  #>
 			try { 
				$uri = "$global:url/projects/$projectId/configurations"
	
				$result = Invoke-RestMethod -Uri $uri -Method GET -ContentType "application/json" -Headers $global:headers 
				$result | Add-member -MemberType NoteProperty -name requestResultCode -value 0
					} catch { 
						$global:errorResponse = $_.Exception
						$result = Show-RequestFailure
						return $result
					}
				return $result
				}
				
function Get-DepartmentQuotas ([string]$deptId) {
<#
    .SYNOPSIS
      Get DepartmentQuotas 
    .EXAMPLE
      Get-DepartmentQuotas 12345 
  #>
			try {				
				$uri = "$global:url/departments/$deptId/quotas"
				$result = Invoke-RestMethod -Uri $uri -Method GET -ContentType "application/json" -Headers $global:headers 
				$result | Add-member -MemberType NoteProperty -name requestResultCode -value 0
					} catch { 
						$global:errorResponse = $_.Exception
						$result = Show-RequestFailure
						return $result
					}
				return $result
				}

function Get-Departments ([string]$departmentId,[string]$attributes,[string]$v2="T",[int]$startCount="100",[string]$qscope="company")  {
<#
    .SYNOPSIS
      Get all Departments
    .SYNTAX
        Get-Departments
       Returns Departments list object
    .EXAMPLE
       Get-Departments
  #>
   $more_records = $True
  		if ($v2 -eq 'T') {
				While ($more_records) {
  					try {
						if ($attributes){
							$uri = $global:url + '/v2/departments?scope=' + $qscope + '&count=' + $startCount + '&offset=' + $global:tOffset + '&query=' + $attributes
						}else{
							if ($departmentId){	
								$uri = $global:url + '/v2/departments/' + $departmentId
							}else{
								$uri = $global:url + '/v2/departments?scope=' + $qscope + '&count=' + $startCount + '&offset=' + $global:tOffset
								}
							}
						write-host $uri
						$result = Invoke-WebRequest -Uri $uri -Method GET -ContentType 'application/json' -Headers $global:headers 	-UseBasicParsing								
							} catch { 
								$result = Show-WebRequestFailure($_.Exception)
								return $result
							}						
						$hold_result = $hold_result + (ConvertFrom-Json $result.Content)
						$hdr = $result.headers['Content-Range']
						#write-host "header" $hdr
						if ($hdr.length -gt 0) {
							$hcounters = $hdr.Split('-')[1]
							[Int]$lastItem,[int]$itemTotal = $hcounters.Split('/')
							write-host "counts " $lastItem $itemTotal
							if (($lastItem + 1)  -lt ($itemTotal)){                                         
								$global:tOffset = $lastItem + 1
							}
							else 
							{
								$more_records = $False
							}
						}
						else 
						{
							$more_records = $False
						}
					}
					$result =  $hold_result
					$result | Add-member -MemberType NoteProperty -name requestResultCode -value 0
					$global:tOffset = 0
					return $result
		}else{
			try {
				if ($departmentId){
					$uri = "$global:url/departments/$departmentId"
				}else{
					$uri = "$global:url/departments"
				}
				$result = Invoke-RestMethod -Uri $uri -Method GET -ContentType "application/json" -Headers $global:headers 
				$result | Add-member -MemberType NoteProperty -name requestResultCode -value 0
					} catch { 
						$global:errorResponse = $_.Exception
						$result = Show-RequestFailure
						return $result
					}
				if ($result.StatusCode -ne 200) {
							write-host $result.StatusCode
							write-host $result.StatusDescription
							$result.requestResultCode = $result.StatusCode
							return $result
							}
				return $result
				}
		}

		
function Get-Users ([string]$userId,[string]$attributes,[string]$v2="T",[int]$startCount="100",[string]$qscope="company")  {
<#
    .SYNOPSIS
      Get all users
    .SYNTAX
        Get-Users
       Returns users list object
    .EXAMPLE
       Get-Users
  #>
   $more_records = $True
  		if ($v2 -eq 'T') {
				While ($more_records) {
  					try {
						if ($attributes){
							$uri = $global:url + '/v2/users?scope=' + $qscope + '&count=' + $startCount + '&offset=' + $global:tOffset + '&query=' + $attributes
						}else{
							if ($userId){	
								$uri = $global:url + '/v2/users/' + $userId
							}else{
								$uri = $global:url + '/v2/users?scope=' + $qscope + '&count=' + $startCount + '&offset=' + $global:tOffset
								}
							}
						write-host $uri
						$result = Invoke-WebRequest -Uri $uri -Method GET -ContentType 'application/json' -Headers $global:headers 	-UseBasicParsing							
							} catch { 
								$result = Show-WebRequestFailure($_.Exception)
								return $result
							}			
						$hold_result = $hold_result + (ConvertFrom-Json $result.Content)
						$hdr = $result.headers['Content-Range']
						#write-host "header" $hdr
						if ($hdr.length -gt 0) {
							$hcounters = $hdr.Split('-')[1]
							[Int]$lastItem,[int]$itemTotal = $hcounters.Split('/')
							write-host "counts " $lastItem $itemTotal
							if (($lastItem + 1)  -lt ($itemTotal)){                                         
								$global:tOffset = $lastItem + 1
							}
							else 
							{
								$more_records = $False
							}
						}
						else 
						{
							$more_records = $False
						}
					}
					$result =  $hold_result
					$result | Add-member -MemberType NoteProperty -name requestResultCode -value 0
					$global:tOffset = 0
					return $result
		}else{
			try {
				if ($userId){
					$uri = "$global:url/users/$userId"
				}else{
					$uri = "$global:url/users"
				}
				$result = Invoke-RestMethod -Uri $uri -Method GET -ContentType "application/json" -Headers $global:headers 
				$result | Add-member -MemberType NoteProperty -name requestResultCode -value 0
					} catch { 
						$global:errorResponse = $_.Exception
						$result = Show-RequestFailure
						return $result
					}
					if ($result.StatusCode -ne 200) {
						write-host $result.StatusCode
						write-host $result.StatusDescription
						return $result
						}
				return $result
				}
		}
		
Set-Alias Get-User Get-Users
				
function Get-Configurations ([string]$configId, [string]$attributes,[string]$v2="T",[int]$startCount="100",[string]$qscope="company") {
<#
    .SYNOPSIS
      Get environment(s)
    .SYNTAX
       Get-Configurations [configId]
       Returns environment(s) list object
    .EXAMPLE
    	  All environments
      Get-Configurations
        Only specific environment details
      Get-Configurations 12345
  #>
  $more_records = $True
  		if ($v2 -eq 'T') {
				While ($more_records) {
  					try {
						if ($attributes){
							$uri = $global:url + '/v2/configurations?scope=' + $qscope + '&count=' + $startCount + '&offset=' + $global:tOffset + '&query=' + $attributes
						}else{
							if ($configId){	
								$uri = $global:url + '/v2/configurations/' + $configId
							}else{
								$uri = $global:url + '/v2/configurations?scope=' + $qscope + '&count=' + $startCount + '&offset=' + $global:tOffset
								}
							}
						write-host $uri
						$result = Invoke-WebRequest -Uri $uri -Method GET -ContentType 'application/json' -Headers $global:headers -UseBasicParsing  							
							} catch { 
								$result = Show-WebRequestFailure($_.Exception)
								return $result
							}						
						$hold_result = $hold_result + (ConvertFrom-Json $result.Content)
						$hdr = $result.headers['Content-Range']
						#write-host "header" $hdr
						if ($hdr.length -gt 0) {
							$hcounters = $hdr.Split('-')[1]
							[Int]$lastItem,[int]$itemTotal = $hcounters.Split('/')
							write-host "counts " $lastItem $itemTotal
							if (($lastItem + 1)  -lt ($itemTotal)){                                         
								$global:tOffset = $lastItem + 1
							}
							else 
							{
								$more_records = $False
							}
						}
						else 
						{
							$more_records = $False
						}
					}
					$result =  $hold_result
					$result | Add-member -MemberType NoteProperty -name requestResultCode -value 0
					$global:tOffset = 0
					return $result
					
				} else {					
					try {
					if ($configId){
						$uri = "$global:url/configurations/$configId"
					}else{
						$uri = "$global:url/configurations"
					}
					$result = Invoke-RestMethod -Uri $uri -Method GET -ContentType "application/json" -Headers $global:headers 
					$result | Add-member -MemberType NoteProperty -name requestResultCode -value 0
						} catch { 
							$global:errorResponse = $_.Exception
							$result = Show-RequestFailure			
						}
						if ($result.StatusCode -ne 200) {
							write-host $result.StatusCode
							write-host $result.StatusDescription
							return $result
									}
					return $result
				}
			}
Set-Alias Get-Environments Get-Configurations
Set-Alias Get-Environment Get-Configurations
Set-Alias Get-Configuration Get-Configurations
				
function Get-Templates ([string]$templateId, [string]$attributes,[string]$v2='T',[int]$startCount="100",[string]$qscope='company') {
<#
    .SYNOPSIS
      Get template(s) optionally filter by attributes
    .SYNTAX
      Get-Templates [templateId] [attribute value pairs]
       Returns template(s) list object
    .EXAMPLE
    	  All templates
    	  	Get-Templates
    	  	
         Only templates that are non-public in US-West
         	Get-Templates -attributes "public=False,region=USWest"
         	
        Only specific template details
        	Get-Templates 12345
  #>
  		$more_records = $True
  		if ($v2 -eq 'T') {
				While ($more_records) {
  					try {
						if ($attributes){
							$uri = $global:url + '/v2/templates?scope=' + $qscope + '&count=' + $startCount + '&offset=' + $global:tOffset + '&query=' + $attributes
						}else{
							if ($templateId){	
								$uri = $global:url + '/v2/templates/' + $templateId
							}else{
								$uri = $global:url + '/v2/templates?scope=' + $qscope + '&count=' + $startCount + '&offset=' + $global:tOffset
								}
							}
						write-host $uri
						$result = Invoke-WebRequest -Uri $uri -Method GET -ContentType 'application/json' -Headers $global:headers -UseBasicParsing								
							} catch { 
								$result = Show-WebRequestFailure($_.Exception)
								return $result
							}
						$hold_result = $hold_result + (ConvertFrom-Json $result.Content)
	
						$hdr = $result.headers['Content-Range']
						
						if ($hdr.length -gt 0) {
							$hcounters = $hdr.Split('-')[1]
							[Int]$lastItem,[int]$itemTotal = $hcounters.Split('/')
							
							if (($lastItem + 1)  -lt ($itemTotal)){                                         
								$global:tOffset = $lastItem + 1
							}
							else 
							{
								$more_records = $False
							}
						}
						else 
						{
							$more_records = $False
						}
					}
					write-host $hold_result.count
					$result =  $hold_result
					$result | Add-member -MemberType NoteProperty -name requestResultCode -value 0
					$global:tOffset = 0
					return $result
					
				} else {
					try {
						if ($templateId){	
							$uri = "$global:url/templates/$templateId"
						}else{
							$uri = "$global:url/templates"
							}
					$result = Invoke-RestMethod -Uri $uri -Method GET -ContentType "application/json" -Headers $global:headers 
					$result | Add-member -MemberType NoteProperty -name requestResultCode -value 0
						} catch { 
							$global:errorResponse = $_.Exception
							$result = Show-RequestFailure			
						}
						if ($result.StatusCode -ne 200) {
							write-host $result.StatusCode
							write-host $result.StatusDescription
							return $result
									}
					return $result
					}
			}
Set-Alias Get-Template Get-Templates

function Add-Schedule ([string]$stype="config",[string]$objectId, [string]$title, $scheduleActions,[string]$startAt,$recurringDays,[string]$endAt,[string]$timezone="Pacific Time (US & Canada)",[string]$deleteAtEnd,[string]$newConfigName) {
<#
    .SYNOPSIS
      Create a schedule
    .SYNTAX
      Add-Schedule $stype $objectId $title $scheduleActions $startAt $recurringDays $endAt $timezone $deleteAtEnd $newConfigName
       Returns schedule object
    .EXAMPLE
    	   Add-Schedule -objectId <template or environment Id> -title "Eight to Five" -scheduleActions [action hash] -startAt "2013/09/09 09:00" -endAt "2013/10/09 0900" -timezone "Central Time (US & Canada)" -deleteAtEnd $True
#>    
   	
		$uri = "$global:url/schedules"
			
			$body = @{
					title = $title					
					start_at = $startAt
					time_zone = $timezone
					actions = @( $scheduleActions )
					}
							
			if ($stype -eq 'config') { 
				$body.add("configuration_id",$objectId)
			}else{
				$body.add("template_id",$objectId)
			}
			if ($endAt) { $body.add("end_at",$endAt) }
			if ($recurringDays) { $body.add("recurring_days",$recurringDays) }
			if ($deleteAtEnd) { $body.add("delete_at_end",$True) }
		#write-host (ConvertTo-Json $body)
		try {
		$result = Invoke-RestMethod -Uri $uri -Method POST -Body (ConvertTo-Json $body) -ContentType "application/json" -Headers $global:headers 
		$result | Add-member -MemberType NoteProperty -name requestResultCode -value 0

			} catch { 
				$global:errorResponse = $_.Exception
				$result = Show-RequestFailure
				return $result
			}
		return $result
	
	}
	
function Get-Usage ([string]$rid='0', [string]$startAt,[string]$endAt,[string]$resource="svms",[string]$region="all",[string]$agg="month",[string]$groupby="user",[string]$format="csv") {
<#
    .SYNOPSIS
      Create Usage Report
    .SYNTAX
      Get-Usage  $stype $objectId $title $scheduleActions $startAt $recurringDays $endAt $timezone $deleteAtEnd $newConfigName
       Returns schedule object
    .EXAMPLE
    	   Get-Usage  -rid <report Id>  -startAt "2013/09/09 09:00" -endAt "2013/10/09 0900" -timezone "Central Time (US & Canada)" -deleteAtEnd $True
 #>    
			if ($rid -eq '0') { 
				$uri = "$global:url/reports"
				$body = @{
					start_date = $startAt
					end_date = $endAt
					resource_type = $resource
					region = $region
					group_by = $groupby
					aggregate_by = $agg
					results_format = $format
					utc = $True
					notify_by_email = $False
					}
					#write-host (ConvertTo-Json $body)
					try {
						$result = Invoke-RestMethod -Uri $uri -Method POST -Body (ConvertTo-Json $body) -ContentType "application/json" -Headers $global:headers 
						$result | Add-member -MemberType NoteProperty -name requestResultCode -value 0

					} catch { 
						$global:errorResponse = $_.Exception
						$result = Show-RequestFailure
						return $result
					}
					return $result
			}else{
				
				$uri = "$global:url/reports/" + $rid 
				
				try {
					$result = Invoke-RestMethod -Uri $uri -Method GET  -ContentType "application/json" -Headers $global:headers 
					$result | Add-member -MemberType NoteProperty -name requestResultCode -value 0
		
					} catch { 
						$global:errorResponse = $_.Exception
						$result = Show-RequestFailure			
					}
					if ($result.ready -eq $True) {
						$uri = "$global:url/reports/" + $rid + '.csv'
						try {
							$result = Invoke-RestMethod -Uri $uri -Method GET  -ContentType "text/csv" -Headers $global:headers 
							$result | Add-member -MemberType NoteProperty -name requestResultCode -value 0
					
								} catch { 
									$global:errorResponse = $_.Exception
									$result = Show-RequestFailure			
								}
					}
					return $result
			}
	
	}
	
## get audit report
function Get-AuditReport ([string]$rid='0', [string]$startAt,[string]$endAt,[string]$region="all",[string]$activity) {
<#
    .SYNOPSIS
      Create Audit Report
    .SYNTAX
      Get-AuditReport  $stype $objectId $title $scheduleActions $startAt $recurringDays $endAt $timezone $deleteAtEnd $newConfigName
       Returns report object
    .EXAMPLE
    	   Get-Audit  -rid <report Id>   -startAt "2016 09 09 09 00" -endAt "2016 10 09 09 00" 
 #>    
			if ($rid -eq '0') { 
				$uri = "$global:url/auditing/exports"
				$yy,$mm,$dd,$hr,$min = $startAt.split()
				$dstart = @{
					year = $yy
					month = $mm
					day = $dd
					hour = $hr
					minute = $min
				}
				$yy,$mm,$dd,$hr,$min = $endAt.split()
				$dend = @{
					year = $yy
					month = $mm
					day = $dd
					hour = $hr
					minute = $min
				}	
				$body = @{
					date_start = $dstart
					date_end = $dend
					activity = $activity
					#region = $region
					#utc = $True
					notify_by_email = $False
					}
					#write-host (ConvertTo-Json $body)
					try {
						$result = Invoke-RestMethod -Uri $uri -Method POST -Body (ConvertTo-Json $body) -ContentType "application/json" -Headers $global:headers 
						$result | Add-member -MemberType NoteProperty -name requestResultCode -value 0

					} catch { 
						$global:errorResponse = $_.Exception
						$result = Show-RequestFailure
						return $result
					}
					return $result
			}else{
				
				$uri = "$global:url/auditing/exports/" + $rid 
				
				try {
					$result = Invoke-RestMethod -Uri $uri -Method GET  -ContentType "application/json" -Headers $global:headers 
					$result | Add-member -MemberType NoteProperty -name requestResultCode -value 0
		
					} catch { 
						$global:errorResponse = $_.Exception
						$result = Show-RequestFailure			
					}
					if ($result.ready -eq $True) {
						$uri = "$global:url/auditing/exports/" + $rid + '.csv'
						try {
							$result = Invoke-RestMethod -Uri $uri -Method GET  -ContentType "text/csv" -Headers $global:headers 
							$result | Add-member -MemberType NoteProperty -name requestResultCode -value 0
					
								} catch { 
									$global:errorResponse = $_.Exception
									$result = Show-RequestFailure			
								}
					}
					return $result
			}
	
	}
	
	
	
function Get-PublicIPs ([string]$configId) {
<#
    .SYNOPSIS
      Get Public IP table
    .SYNTAX
       Get-PublicIPs
       Returns list of IPs
    .EXAMPLE
      Get-PublicIPs
  #>
		try {
			$uri = "$global:url/ips"
			$result = Invoke-RestMethod -Uri $uri -Method GET -ContentType "application/json" -Headers $global:headers 
			$result | Add-member -MemberType NoteProperty -name requestResultCode -value 0
				} catch { 
					$global:errorResponse = $_.Exception
					$result = Show-RequestFailure
					return $result
				}
			return $result
	}
	
function Get-Schedules ([string]$scheduleId, [string]$attributes,[string]$v2='T',[int]$startCount="100",[string]$qscope='admin') {
<#
    .SYNOPSIS
      Get Schedules
    .SYNTAX
       Get-Schedules
       Returns list of Schedules
    .EXAMPLE
      Get-Schedules
      Get-Schedule 1234
  #>
   $more_records = $True
  		if ($v2 -eq 'T') {
				While ($more_records) {
  					try {
						if ($attributes){
							$uri = $global:url + '/v2/schedules?scope=' + $qscope + '&count=' + $startCount + '&offset=' + $global:tOffset + '&query=' + $attributes
						}else{
							if ($configId){	
								$uri = $global:url + '/v2/schedules/' + $scheduleId
							}else{
								$uri = $global:url + '/v2/schedules?scope=' + $qscope + '&count=' + $startCount + '&offset=' + $global:tOffset
								}
							}
						write-host $uri
						$result = Invoke-WebRequest -Uri $uri -Method GET -ContentType 'application/json' -Headers $global:headers  -UseBasicParsing
										
							} catch { 
								$result = Show-WebRequestFailure($_.Exception)
								return $result
							}		
						$hold_result = $hold_result + (ConvertFrom-Json $result.Content)
						$hdr = $result.headers['Content-Range']
						#write-host "header" $hdr
						if ($hdr.length -gt 0) {
							$hcounters = $hdr.Split('-')[1]
							[Int]$lastItem,[int]$itemTotal = $hcounters.Split('/')
							write-host "counts " $lastItem $itemTotal
							if (($lastItem + 1)  -lt ($itemTotal)){                                         
								$global:tOffset = $lastItem + 1
							}
							else 
							{
								$more_records = $False
							}
						}
						else 
						{
							$more_records = $False
						}
					}
					$result =  $hold_result
					$result | Add-member -MemberType NoteProperty -name requestResultCode -value 0
					$global:tOffset = 0
					return $result
				} else {
					try {
						if ($scheduleId) {
							$uri = "$global:url/schedules/" + $scheduleId 
						} else {
						$uri = "$global:url/schedules" }
						$result = Invoke-RestMethod -Uri $uri -Method GET -ContentType "application/json" -Headers $global:headers 
						$result | Add-member -MemberType NoteProperty -name requestResultCode -value 0
							} catch { 
								$global:errorResponse = $_.Exception
								$result = Show-RequestFailure			
							}
							if ($result.StatusCode -ne 200) {
								write-host $result.StatusCode
								write-host $result.StatusDescription
								return $result
									}
						return $result
	}
}
Set-Alias Get-Schedule Get-Schedules
	
function Connect-PublicIP ([string]$vmId, [string]$interfaceId,[string]$publicIP){
<#
    .SYNOPSIS
      Connect Public IP to network
    .SYNTAX
       Connect-PublicIP vmID interfaceID publicIP
    .EXAMPLE
      Connect-PublicIP 789012 nic-11856481-23685181-0 185.18.0.3
  #>
  write-host $publicIP
	try {
		$uri = "$global:url/vms/$vmId/interfaces/$interfaceId/ips"
		write-host $uri
		$body = @{
				ip = $publicIP
			}
		$result = Invoke-RestMethod -Uri $uri -Method POST -Body (ConvertTo-Json $body) -ContentType "application/json" -Headers $headers 
		$result | Add-member -MemberType NoteProperty -name requestResultCode -value 0
			} catch {
				$global:errorResponse = $_.Exception
				$result = Show-RequestFailure
				return $result
		}
	return $result
	}

function Rename-Environment( [string]$configId, [string]$newName ){
<#
   .SYNOPSIS
     Change an environment's name
   .SYNTAX
      Rename-Environment ConfigId "new environment name"
   .EXAMPLE
     Rename-Environment 12345 "hello world"
 #>
    try {
        $uri = "$url/configurations/$configId"
        
        $body = @{
            name = $newName
        }
        $result = Invoke-RestMethod -Uri $uri -Method PUT -Body (ConvertTo-Json $body)  -ContentType "application/json" -Headers $headers 
        $result | Add-member -MemberType NoteProperty -name requestResultCode -value 0
            } catch { 
                $global:errorResponse = $_.Exception
                $result = Show-RequestFailure
                return $result
        }
    return $result
    }
Set-Alias Rename-Configuration Rename-Environment   
    
function Update-AutoSuspend ( [string]$configId, [string]$suspendOnIdle ){
<#
   .SYNOPSIS
     Change an environment's auto-suspend setting, null = off, 300-86400 is valid range.
   .SYNTAX
      Update-AutoSuspend ConfigId NumberOfSeconds
   .EXAMPLE
     Update-RunState 12345 300
 #>
    try {
        $uri = "$url/configurations/$configId"
        
        $body = @{
            suspend_on_idle = $suspendOnIdle
        }
        $result = Invoke-RestMethod -Uri $uri -Method PUT -Body (ConvertTo-Json $body)  -ContentType "application/json" -Headers $headers 
        $result | Add-member -MemberType NoteProperty -name requestResultCode -value 0
            } catch { 
                $global:errorResponse = $_.Exception
                $result = Show-RequestFailure
                return $result
        }
    return $result
    }

function Add-UserToProject( [string]$projectId, [string]$userId,[string]$projectRole="participant" ){
<#
    .SYNOPSIS
      Add a user to a project
    .SYNTAX
        Add-UserToProject projectID userID [project-role]
       Return
    .EXAMPLE
      Add-UserToProject 123344 3828 viewer
      ---
      New-Project -projectName "Global Training" -projectDescription "A project for global training"
  #>
	try {
		$uri = "$global:url/projects/$projectId/users/$userId"
		$body = @{
				role = $projectRole
				}
		$result = Invoke-RestMethod -Uri $uri -Method POST -Body (ConvertTo-Json $body) -ContentType "application/json" -Headers $global:headers 
		$result | Add-member -MemberType NoteProperty -name requestResultCode -value 0

			} catch { 
				$global:errorResponse = $_.Exception
				$result = Show-RequestFailure
				return $result
			}
		return $result
	
	}
function Add-UserToGroup( [string]$groupId, [string]$userId ){
<#
    .SYNOPSIS
      Add a user to a group
    .SYNTAX
        Add-UserToProject groupID userID 
       Return
    .EXAMPLE
      Add-UserToGroup 123344 3828 
  #>
	try {
		$uri = "$global:url/groups/$groupId/users/$userId"
		$result = Invoke-RestMethod -Uri $uri -Method POST -Body (ConvertTo-Json $body) -ContentType "application/json" -Headers $global:headers 
		$result | Add-member -MemberType NoteProperty -name requestResultCode -value 0

			} catch { 
				$global:errorResponse = $_.Exception
				Write-Host "StatusCode:" $_.Exception.Response.StatusCode.value__ 
				Write-Host "StatusDescription:" $_.Exception.Response.StatusDescription
				$result = Show-RequestFailure
				return $result
			}
		return $result
	
	}

<#
    .SYNOPSIS
      Get VM metadata - only works from within a VM
    .SYNTAX
        Get-Metadata
        
    .EXAMPLE
      $meta = Get-Metadata
  #>
function Get-Metadata
	{
       $ip = Test-Connection $env:computername -count 1 | select Address,Ipv4Address
       $oct1,$oct2,$oct3,$oct4 = $ip.IPV4Address.split('.')
	$uri = "http://$oct1.$oct2.$oct3.254/skytap"
	try {
		$meta = Invoke-WebRequest $uri -Method GET -ContentType 'application/json' -UseBasicParsing
		$meta.Content | convertfrom-json
		#$myhost = $mc.name + "-" + $mc.id
		#write-output $myhost
		$result | Add-member -MemberType NoteProperty -name requestResultCode -value 0
		} catch { 
				$global:errorResponse = $_.Exception
				$result = Show-RequestFailure
				return $result
			}
		return $result
	}



function Send-SharedDrive([string]$localFilename, [string]$remoteFilename)
    {
    	try {
		$furl = 'ftp://' + $ftpregion + '/shared_drive'
		$freq = [System.Net.FtpWebRequest]::Create($furl+'/'+$remoteFilename)
		if ($ftpuser) {
			$freq.Credentials = New-Object System.Net.NetworkCredential($ftpuser,$ftppwd)
			$freq.Method = [System.Net.WebRequestMethods+Ftp]::UploadFile
			$freq.UseBinary = $True
			$freq.UsePassive = $True
			$freq.KeepAlive = $False
			$localfile = $localFilename
			$upcontent = gc -en byte $localfile
			$freq.ContentLength = $upcontent.Length
			$Run = $freq.GetRequestStream()
			$Run.Write($upcontent, 0, $upcontent.Length)
			$Run.Close()
			$Run.Dispose()
			return 0
		} else {
			write-host "FTP User not set"
			return -1
		}
	}
		catch {
			return -1
		}
}
#new 5/30
function Add-EnvironmentTag( [string]$configId, $taglist ){
<#
   .SYNOPSIS
     Add one or more tags to an environment
   .SYNTAX
      Add-EnvironmentTag ConfigId "tag"
   .EXAMPLE
     Add-EnvironmentTag 12345 "my_special_tag"
     Or
     $tlist = @("tag1","tag2","tagX")
     Add-EnvironmentTag 515151 $tlist
 #>
   $tags = @()
    try {
        $uri = "$url/v2/configurations/$configId/tags"
        foreach ($newtag in $taglist) {
        	$tag = @{'value' = $newtag}
        	$tags += $tag
        }
        $result = Invoke-RestMethod -Uri $uri -Method PUT -Body (ConvertTo-Json $tags)  -ContentType "application/json" -Headers $headers 
        $result | Add-member -MemberType NoteProperty -name requestResultCode -value 0
            } catch { 
                $global:errorResponse = $_.Exception
                $result = Show-RequestFailure
                return $result
        }
    return $result
    }
Set-Alias Tag-Configuration Add-EnvironmentTag
Set-Alias Tag-Environment Add-EnvironmentTag

function Add-TemplateTag( [string]$TemplateId, $taglist ){
<#
   .SYNOPSIS
     Add one or more tags to an Template
   .SYNTAX
      Add-TemplateTag TemplateId "tag"
   .EXAMPLE
     Add-TemplateTag 12345 "my_special_tag"
     Or
     $tlist = @("tag1","tag2","tagX")
     Add-TemplateTag 515151 $tlist
 #>
   $tags = @()
    try {
        $uri = "$url/v2/templates/$TemplateId/tags"
        foreach ($newtag in $taglist) {
        	$tag = @{'value' = $newtag}
        	$tags += $tag
        }
        $result = Invoke-RestMethod -Uri $uri -Method PUT -Body (ConvertTo-Json $tags)  -ContentType "application/json" -Headers $headers 
        $result | Add-member -MemberType NoteProperty -name requestResultCode -value 0
            } catch { 
                $global:errorResponse = $_.Exception
                $result = Show-RequestFailure
                return $result
        }
    return $result
    }
Set-Alias Tag-Configuration Add-TemplateTag
Set-Alias Tag-Template Add-TemplateTag

function Get-Tags ([string]$configId, [string]$templateId, [string]$assetId ) {
<#
    .SYNOPSIS
      Get Tags for an Environment, Template or Asset
    .SYNTAX
       Get-Tag configId 
       Returns tags
    .EXAMPLE
      Get-Tag 12345  
  #>
  		if ($configId) {
  			$uri = "$global:url/configurations/$configId/tags" 
  		} else {	
  			if ($templateId) {
  				$uri = "$global:url/templates/$templateId/tags"
			} else {
				if ($assetId) {
					$uri = "$global:url/assets/$assetId/tags"
				} else {
						$result = New-Object -TypeName psobject -Property @{
						requestResultCode = [int]-1
						eDescription = "Missing parameter"
						eMessage = "You must supply an environment or template ID"
						method = "Get-Tags"
						}
						return $result
				}
			}
		}	
		try {				
			$result = Invoke-RestMethod -Uri $uri -Method GET -ContentType "application/json" -Headers $global:headers 
			$result | Add-member -MemberType NoteProperty -name requestResultCode -value 0
				} catch { 
					$global:errorResponse = $_.Exception
					$result = Show-RequestFailure
					return $result
				}
			return $result
}


function Get-VMCredentials ([string]$vmId) {
<#
    .SYNOPSIS
      Get VM credentials
    .SYNTAX
       Get-VMCredentials
       Returns list of credentials defined for the machine
    .EXAMPLE
      Get-VMCredentials 
  #>
		try {
			$uri = "$global:url/vms/$vmId/credentials"
			$result = Invoke-RestMethod -Uri $uri -Method GET -ContentType "application/json" -Headers $global:headers 
			$result | Add-member -MemberType NoteProperty -name requestResultCode -value 0
				} catch { 
					$global:errorResponse = $_.Exception
					$result = Show-RequestFailure
					return $result
				}
			return $result
	}

function Attach-WAN ([string]$envId, [string]$networkId,[string]$wanId){
<#
    .SYNOPSIS
      Attach to VPN/WAN
    .SYNTAX
       Attach-WAN environment network vpnid
  #>
  write-host $publicIP
	try {
		$uri = "$global:url/v2/configurations/$envId/networks/$networkId/vpns"
		write-host $uri
		$body = @{
				vpn_id = $wanId
			}
		$result = Invoke-RestMethod -Uri $uri -Method POST -Body (ConvertTo-Json $body) -ContentType "application/json" -Headers $global:headers 
		write-host $result.headers
		$result | Add-member -MemberType NoteProperty -name requestResultCode -value 0
			} catch {
				$global:errorResponse = $_.Exception
				$result = Show-RequestFailure
				return $result
		}
	return $result
	}
	
function Connect-WAN ([string]$envId, [string]$networkId,[string]$wanId){
<#
    .SYNOPSIS
      Connect to VPN/WAN
    .SYNTAX
       Connect-WAN environment network vpnid
  #>
  write-host $publicIP
	try {
		$uri = "$global:url/v2/configurations/$envId/networks/$networkId/vpns/$wanId"
		write-host $uri
		$body = @{
				connected = $true
			}

		$result = Invoke-RestMethod -Uri $uri -Method PUT -Body (ConvertTo-Json $body) -ContentType "application/json" -Headers $global:headers 
		$result | Add-member -MemberType NoteProperty -name requestResultCode -value 0
			} catch {
				$global:errorResponse = $_.Exception
				$result = Show-RequestFailure
				return $result
		}
	return $result
	}
	
function Get-WAN ([string]$wanId) {
<#
    .SYNOPSIS
      Get VPN(s)
    .SYNTAX
       Get-WAN [wanId]
  #>

		try {
			if ($wanId) {
				$uri = "$global:url/v2/vpns/$wanId"
			} else {
				$uri = "$global:url/v2/vpns"
			}
			write-host $uri
			$result = Invoke-RestMethod -Uri $uri -Method GET -ContentType "application/json" -Headers $global:headers 
			$result | Add-member -MemberType NoteProperty -name requestResultCode -value 0
				} catch { 
					$global:errorResponse = $_.Exception
					$result = Show-RequestFailure
					return $result
				}
			return $result
	}
Set-Alias Get-VPN Get-WAN
Set-Alias Get-WANs Get-WAN
Set-Alias Get-VPNs Get-WAN

function Get-Network ([string]$configId, [string]$networkId) {
	<#
    .SYNOPSIS
      Get Environment Networks
    .SYNTAX
       Get-Network [networkId]
  #>

		try {
			if ($networkId) {
				$uri = "$global:url/v2/configurations/$configId/networks/$networkId"
			} else {
				$uri = "$global:url/v2/configurations/$configId/networks"
			}
			write-host $uri
			$result = Invoke-RestMethod -Uri $uri -Method GET -ContentType "application/json" -Headers $global:headers 
			$result | Add-member -MemberType NoteProperty -name requestResultCode -value 0
				} catch { 
					$global:errorResponse = $_.Exception
					$result = Show-RequestFailure
					return $result
				}
			return $result
	}
Set-Alias Get-VPN Get-WAN

function Update-EnvironmentUserdata ( [string]$configId, $userdata ){
<#
    .SYNOPSIS
      Change userdata 
    .SYNTAX
      Update-EnvironmentUserdata ConfigId  Contents
       {
	"contents": "Text you want saved in the user data field"
	}
    .EXAMPLE
      Update-EnvironmentUserdata 12345   @{contents="text for userdata field"}
      Or
      $userdata = @{"contents"="This machine does not conform"}
      Update-EnvironmentUserdata 12345  $userdata
      
  #>
	try {
		$uri = "$url/v2/configurations/$configId/user_data"
		
		$body = $userdata
		$result = Invoke-RestMethod -Uri $uri -Method PUT -Body (ConvertTo-Json $body)  -ContentType "application/json" -Headers $headers 
		$result | Add-member -MemberType NoteProperty -name requestResultCode -value 0
			} catch { 
				$global:errorResponse = $_.Exception
				$result = Show-RequestFailure
				return $result
		}
	return $result
	}
	

	
		
# lastline
Export-ModuleMember -function * -alias *

		



			


