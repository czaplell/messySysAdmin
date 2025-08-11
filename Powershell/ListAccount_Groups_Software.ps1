<#
.SYNOPSIS
Scipt to list local accounts, groups, and installed software on a computer, and upload the results to SharePoint Team Site

.DESCRIPTION
Put this script as correction script to intune https://intune.microsoft.com/#view/Microsoft_Intune_DeviceSettings/DevicesMenu/~/scripts and select group to check


.EXAMPLE
An example

.NOTES
General notes
#>#




$computerName = $env:COMPUTERNAME
function GetLocalAccountInfo($computerName){
[CmdletBinding()]
$directoryEntry = [ADSI]"WinNT://$computerName"

<# 
    get all users
    who are not disabled
    bitmask for disabled in UserFlags is 2
    https://support.microsoft.com/en-au/help/305144/how-to-use-useraccountcontrol-to-manipulate-user-account-properties
#>
$users = $directoryEntry.Children | Where-Object {$_.SchemaClassName -eq 'user' }#-and -not ($_.UserFlags.Value -band 2)} #With UserFlags check disabled accounts
$results = @()

Write-Host "Getting local account info for $computerName"
foreach ($u in $users)
{
    # create new PSCustomObject for output
    
    $tempUser = New-Object -TypeName PSObject


    # janky but I can't think of a better way to do it in 2.0
    if ($u | Get-Member | Select-Object -ExpandProperty Name | Where-Object {$_ -eq 'LastLogin'})
    {  
        $lastLogin  = Get-Date $u.LastLogin.Value
        $today      = Get-Date
        $daysAgo    = ($today - $lastLogin).Days
    }
    else
    {
        $lastLogin  = 'never'
        $daysAgo    = 'never'
    }

    $tempUser | Add-Member -MemberType NoteProperty -Name 'ComputerName' -Value $computerName
    $tempUser | Add-Member -MemberType NoteProperty -Name 'Username' -Value $u.Name.Value
    $tempUser | Add-Member -MemberType NoteProperty -Name 'LastLogin' -Value $lastLogin
    $tempUser | Add-Member -MemberType NoteProperty -Name 'DaysAgo' -Value $daysAgo
    $tempUser | Add-Member -MemberType NoteProperty -Name 'Enabled' -Value (Get-LocalUser -Name $u.Name.Value).Enabled -ErrorAction SilentlyContinue
    

   $results += $tempUser
   $path = "$pwd\$computerName.json"
   $results | ConvertTo-Json | Out-file  -FilePath $path
   
}
return $results
} 
function GetLocalGroupMembershipInfo($computerName){
[CmdletBinding()]
$computerName = $env:COMPUTERNAME
$results = @()
$knownSID = @(
    "S-1-5-32-544", # Administrators
    "S-1-5-32-545", # Users
    "S-1-5-32-546", # Guests
    "S-1-5-32-547" # Power Users
)
Foreach($SID in $knownSID){
    $tempUser = New-Object -TypeName PSObject
    $group = Get-LocalGroup -SID $SID -ErrorAction SilentlyContinue #check if the SID is a valid local group
    if($null -eq $group){

    }
    else{

        $members = Get-LocalGroupMember -SID $SID -ErrorAction SilentlyContinue | ?{$_.ObjectClass -ne "Group" -and $_.PrincipalSource -ne "AzureAD"} |Select-Object -ExpandProperty Name
        $names = $members -replace "$computerName\\", "" -join ", "
        $tempUser | Add-Member -MemberType NoteProperty -Name 'ComputerName' -Value $computerName
        $tempUser | Add-Member -MemberType NoteProperty -Name 'GroupName' -Value $group.Name
        $tempUser | Add-Member -MemberType NoteProperty -Name 'GroupSID' -Value $group.SID
        $tempUser | Add-Member -MemberType NoteProperty -Name 'GroupMembers' -Value $names

        
        



       
        }

$results += $tempUser 
$path = "$pwd\$computerName"+"_Groups.json"
$results | ConvertTo-Json | Out-File -FilePath $path -Encoding utf8
    

}
return $results

}

function ListOfInstalledSoftware($computerName){
    [CmdletBinding()]
    $software = Get-WmiObject -Class Win32_Product -ComputerName $computerName | Select-Object Name, Version, Vendor
    $software | Format-Table -AutoSize
    $path = "$pwd\$computerName"+"_Software.json"
    $software | ConvertTo-Json | Out-File -FilePath $path -Encoding utf8
    return $software
}

Write-Host "Calling Local Account Info Function"
GetLocalAccountInfo $computerName
GetLocalGroupMembershipInfo $computerName 
ListOfInstalledSoftware $computerName

######################### Part to send a message

Write-Host "Preparing to send message..." 
$tenantId = "TenantID" ############################# TenantID
$clientId = "APP Client ID" ######################## App Client ID - you need to register APP here https://portal.azure.com/?feature.msaljs=true#view/Microsoft_AAD_RegisteredApps/ApplicationsListBlade with Sites.ReadWrite.All permissions
$clientSecret = "APP Secret"


# Get token
$tokenResponse = Invoke-RestMethod -Method POST -Uri "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token" -Body @{
    client_id     = $clientId
    scope         = "https://graph.microsoft.com/.default"
    client_secret = $clientSecret
    grant_type    = "client_credentials"
}

$accessToken = $tokenResponse.access_token

# Load file and convert to Base64
$attachmentPath_U = "$pwd\$computerName.json"
$fileName_U = [System.IO.Path]::GetFileName($attachmentPath_U)

$attachmentPath_G = "$pwd\$computerName"+"_Groups.json"
$fileName_G = [System.IO.Path]::GetFileName($attachmentPath_G)

$attachmentPath_S = "$pwd\$computerName"+"_Software.json"
$fileName_S = [System.IO.Path]::GetFileName($attachmentPath_S)



$tokenResponse = Invoke-RestMethod -Method Post -Uri "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token" `
    -Body @{
        client_id     = $clientId
        scope         = "https://graph.microsoft.com/.default"
        client_secret = $clientSecret
        grant_type    = "client_credentials"
    }

$token = $accessToken
$headers = @{ Authorization = "Bearer $token" }

$siteHostname = "<yourdomain>.sharepoint.com" #Hostname url
$sitePath = "/sites/Place_to_dump File" #Site path
$libraryName = "Documents" #library

$siteUrl = "https://graph.microsoft.com/v1.0/sites/$siteHostname"+":"+"$sitePath"
$site = Invoke-RestMethod -Uri $siteUrl -Headers $headers
$siteId = $site.id
$siteId



$fileContent_U = Get-Content $attachmentPath_U #-Encoding Byte -ReadCount 0
$fileContent_G = Get-Content $attachmentPath_G #-Encoding Byte -ReadCount 0
$fileContent_S = Get-Content $attachmentPath_S #-Encoding Byte -ReadCount 0

$uploadUrl = "https://graph.microsoft.com/v1.0/sites/$siteId/drives?$filter=name eq '$libraryName'"
$drive = (Invoke-RestMethod -Uri $uploadUrl -Headers $headers).value[0]
$driveId = $drive.id
$driveId

$uploadUri = "https://graph.microsoft.com/v1.0/drives/$driveId/root:/raporty/inbox/$fileName_U"+":/content"
Invoke-RestMethod -Uri $uploadUri -Method PUT -Headers $headers -Body $fileContent_U

$uploadUri = "https://graph.microsoft.com/v1.0/drives/$driveId/root:/raporty/inbox/$fileName_G"+":/content"
Invoke-RestMethod -Uri $uploadUri -Method PUT -Headers $headers -Body $fileContent_G

$uploadUri = "https://graph.microsoft.com/v1.0/drives/$driveId/root:/raporty/inbox/$fileName_S"+":/content"
Invoke-RestMethod -Uri $uploadUri -Method PUT -Headers $headers -Body $fileContent_S

Remove-Item -Path $attachmentPath_U -Force
Remove-Item -Path $attachmentPath_G -Force
Remove-Item -Path $attachmentPath_S -Force
