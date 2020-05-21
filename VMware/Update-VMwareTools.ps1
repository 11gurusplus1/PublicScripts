<#

**This script might cause the computer to reboot**

This script updates VMware tools to the latest avalible version.

The script might need to be run several times for fresh installs since VC redist needs to be installed which requires a reboot.

Andy Morales
#>
function Test-RegistryValue {
    <#
    Checks if a reg key/value exists

    #Modified version of the function below
    #https://www.jonathanmedd.net/2014/02/testing-for-the-presence-of-a-registry-key-and-value.html

    Andy Morales
    #>

    [CmdletBinding()]
    param (
        [parameter(Mandatory = $true,
            Position = 1,
            HelpMessage = 'HKEY_LOCAL_MACHINE\SYSTEM')]
        [ValidatePattern('Registry::.*|HKEY_')]
        [ValidateNotNullOrEmpty()]
        [String]$Path,

        [parameter(Mandatory = $true,
            Position = 2)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [parameter(Position = 3)]
        $ValueData
    )

    Set-StrictMode -Version 2.0

    #Add Regdrive if it is not present
    if ($Path -notmatch 'Registry::.*') {
        $Path = 'Registry::' + $Path
    }

    try {
        #Reg key with value
        if ($ValueData) {
            if ((Get-ItemProperty -Path $Path -ErrorAction Stop | Select-Object -ExpandProperty $Name -ErrorAction Stop) -eq $ValueData) {
                return $true
            }
            else {
                return $false
            }
        }
        #Key key without value
        else {
            $RegKeyCheck = Get-ItemProperty -Path $Path -ErrorAction Stop | Select-Object -ExpandProperty $Name -ErrorAction Stop
            if ($null -eq $RegKeyCheck) {
                #if the Key Check returns null then it probably means that the key does not exist.
                return $false
            }
            else {
                return $true
            }
        }
    }
    catch {
        return $false
    }
}

#Check if the computer is a VMware VM
if (( Get-CimInstance -ClassName win32_computersystem).Manufacturer -ne 'VMware, Inc.') {
    Write-Output 'Computer is not a VMware VM. Script will exit'
    Exit
}

#Find the URL to the latest version
$LatestVersionExe = (Invoke-WebRequest -Uri https://packages.vmware.com/tools/releases/latest/windows/x64/).Links.href | Where-Object { $_ -match 'VMware-tools-.*\.exe' }
$LatestVersionFullURL = "https://packages.vmware.com/tools/releases/latest/windows/x64/" + "$LatestVersionExe"

if (Test-Path "C:\Program Files\VMware\VMware Tools\vmtoolsd.exe") {
    #Get the file version of the update package, and the installed package
    [version]$ToolsInstalledVersion = ('{0}.{1}.{2}' -f ((Get-Item -Path "C:\Program Files\VMware\VMware Tools\vmtoolsd.exe").VersionInfo.fileversion).split('.') )
    #Check the x86 version so that the script works on x86 and x64
    [Version]$ToolsUpdateVersion = ('{0}.{1}.{2}' -f ([regex]::Match("$LatestVersionExe", '\d{1,2}\.\d{1,2}\.\d{1,2}').value).split('.') )

    #Check to see if the update is newer than the installed version
    If ($ToolsUpdateVersion -gt $ToolsInstalledVersion) {
        $VmToolsShouldBeUpdated = $true
    }
    else {
        $VmToolsShouldBeUpdated = $false
    }
}
#If vmtoolsd.exe was not found then VM tools are probably not installed
else {
    $VmToolsShouldBeUpdated = $true
}

if ($VmToolsShouldBeUpdated) {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    #Detect if VC Redist 2015 is installed
    if ($env:PROCESSOR_ARCHITECTURE -eq 'AMD64') {
        if (Test-RegistryValue -Path 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64' -Name 'Major' ) {
            #VC x64 is already installed
            $InstallVCx64 = $false
        }
        else {
            #installVC x64
            $InstallVCx64 = $true
        }

        if (Test-RegistryValue -Path 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Wow6432Node\Microsoft\VisualStudio\14.0\VC\Runtimes\x86' -Name 'Major') {
            #VC x86 is already installed
            $InstallVCx86 = $false
        }
        else {
            #installVC x86
            $InstallVCx86 = $true
        }
    }
    else {
        $InstallVCx64 = $false

        if (Test-RegistryValue -Path 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\X86' -Name 'Major') {
            #VC x86 is already installed
            $InstallVCx86 = $false
        }
        else {
            #installVC x86
            $InstallVCx86 = $true
        }
    }

    #Download and Install VC Redist if required
    if ($InstallVCx64) {
        Write-Output 'Installing VC Redist x64'
        (New-Object System.Net.WebClient).DownloadFile('https://download.microsoft.com/download/9/3/F/93FCF1E7-E6A4-478B-96E7-D4B285925B00/vc_redist.x64.exe', 'C:\Windows\Temp\vc_redist.x64.exe')
        $VCx64Proc = Start-Process -Wait -FilePath 'C:\Windows\Temp\vc_redist.x64.exe' -ArgumentList '/Q /restart' -PassThru
    }
    if ($InstallVCx86) {
        Write-Output 'Installing VC Redist x86'
        (New-Object System.Net.WebClient).DownloadFile('https://download.microsoft.com/download/9/3/F/93FCF1E7-E6A4-478B-96E7-D4B285925B00/vc_redist.x86.exe', 'C:\Windows\Temp\vc_redist.x86.exe')
        $VCx86Proc = Start-Process -Wait -FilePath 'C:\Windows\Temp\VC_redist.x86.exe' -ArgumentList '/Q /restart' -PassThru

    }

    Write-Output 'Downloading VMware Tools'

    #Download VMware Tools
    (New-Object System.Net.WebClient).DownloadFile("$LatestVersionFullURL", 'C:\Windows\Temp\VMwareTools.exe')

    Write-Output 'Installing VMware Tools'

    #Install VMware Tools
    $VMToolsInstallProc = Start-Process -Wait -FilePath 'C:\Windows\Temp\VMwareTools.exe' -ArgumentList '/s /v /qn /l c:\windows\temp\VMToolsInstall.log' -PassThru

    #Reboot if Required
    if ($VCx64Proc.ExitCode -eq '3010' -or $VCx86Proc.ExitCode -eq '3010' -or $VMToolsInstallProc.ExitCode -eq '3010') {
        Restart-Computer -Force
    }
}
