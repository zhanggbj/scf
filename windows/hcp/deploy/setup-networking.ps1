param(
	[Parameter(Mandatory=$true)]
	[ValidateScript({ if($_ -match "^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$"){
		$True
		}else{
			Throw "$_ is not a valid IPV4 address. Please use something like 10.21.0.1."
		}
	})]
    [string] $k8MasterIP,
    [Parameter(Mandatory=$false)]
	[ValidateRange(80,65535)]
    [int] $k8sPort = 8080,
    [Parameter(Mandatory=$false)]
	[ValidateRange(80,65535)]
    [int] $etcdPort = 2379,
    [Parameter(Mandatory=$false)]
    [string] $flannelUserPassword = "Password1234!",
    [Parameter(Mandatory=$false)]
	[ValidateScript({If (Test-Path $_) {
			$True
		}else{
			Throw "$_ is not a valid file."
		}
	})]
    [string] $flannelInstallDir = "C:/flannel",
    [Parameter(Mandatory=$false)]
    [ValidateScript({ if($_ -match "^[0-9]{1,3}[s,m]$"){
		$True
		}else{
			Throw "$_ is not a valid interval. Please use something like 1s for 1 seccond or 2m for 2 minutes."
		}
	})]
	[string] $k8sQueryPeriod = "1s",
    [Parameter(Mandatory=$true)]
	[ValidateScript({If (Test-Path $_) {
			$True
		}else{
			Throw "$_ is not a valid file."
		}
	})]
    [string] $etcdKeyFile,
    [Parameter(Mandatory=$true)]
	[ValidateScript({If (Test-Path $_) {
			$True
		}else{
			Throw "$_ is not a valid file."
		}
	})]
    [string] $etcdCertFile,
    [Parameter(Mandatory=$true)]
    [ValidateScript({If (Test-Path $_) {
			$True
		}else{
			Throw "$_ is not a valid file."
		}
	})]
	[string] $etcdCaFile	,
  [Parameter(Mandatory=$false)]
	[ValidateScript({ if($_ -match "^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\/(8|16|24)$"){
		$True
		}else{
			Throw "$_ is not a valid subnet. Please use something like 10.21.0.0/16  or don't use this param to use the default."
		}
	})]
    [string] $k8sServSubnet = "",
	[Parameter(Mandatory=$false)]
	[ValidateScript({ if($_ -match "^http:\/\/[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}:[0-9]{2,5}$"){
		$True
		}else{
			Throw "$_ is not a valid address:port for proxy. Please use something like http://10.12.22.1:3128 or don't use this param to use the default."
		}
	})]
    [string] $httpProxy = "",
	[Parameter(Mandatory=$false)]
	[ValidateScript({ if($_ -match "^http[s]?:\/\/[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}:[0-9]{2,5}$"){
		$True
		}else{
			Throw "$_ is not a valid address:port for proxy. Please use something like http://10.12.22.1:3128. or don't use this param to use the default."
		}
	})]
    [string] $httpsProxy = "",
	[Parameter(Mandatory=$false)]
	[ValidateScript( { If ($_ -match "^([0-9|\*]{1,3}\.[0-9|\*]{1,3}\.[0-9|\*]{1,3}\.[0-9|\*]{1,3}\,?){1,}$"){
		$True
		}else{
			Throw "$_ is not a valid specifier for noProxy. Please use something like 10.21.*.*,192.100.200.* or don't use this param to use the default."
		}
	})]
    [string] $noProxy = "",
  [Parameter(Mandatory=$false)]
	[ValidateScript({ if($_ -match "^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\/(8|16|24)$"){
		$True
		}else{
			Throw "$_ is not a valid subnet. Please use something like 10.21.0.0/16 or don't use this param to use the default."
		}
	})]
	[string] $k8sAllowedSubnet=""
)

$ErrorActionPreference = "Stop"

$wd="$PSScriptRoot\resources\hcf-networking"
mkdir -f $wd  | Out-Null

if (($httpProxy -ne "") -and ($httpsProxy -ne "")) {

    $hklm64 = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, [Microsoft.Win32.RegistryView]::Registry64)
    $hklm32 = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, [Microsoft.Win32.RegistryView]::Registry32)

    ## Disable IE first run wizard
    ## https://www.petri.com/disable-ie8-ie9-welcome-screen
    $ieMainRegPath = "Software\Policies\Microsoft\Internet Explorer\Main"
    $disableWizard = { param ($ieRegKey)
        $ieMainSettings = $ieRegKey.CreateSubKey($ieMainRegPath, [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree)
        $ieMainSettings.SetValue("DisableFirstRunCustomize", 1)
        $ieMainSettings.Dispose()
    }

    & $disableWizard $hklm64
    & $disableWizard $hklm32


    ## Parse proxy env

    $proxyServers = ""

    if ($httpProxy -ne "") {
        $proxyServers += "http=$httpProxy"
    }

    if ($httpsProxy -ne "") {
        if ($proxyServers -ne "") { $proxyServers += ";" }
        $proxyServers += "https=$httpsProxy"
    }

    $bypassList = ($noProxy -replace ',', ';')

    echo "Setting proxy servers     : $proxyServers"
    echo "Setting proxy bypass list : $bypassList"


    # Disable ProxySettingsPerUser
    $proxyPolicyRegPath = "Software\Policies\Microsoft\Windows\CurrentVersion\Internet Settings"
    $setProxyPolicy = { param ($ieRegKey)
        $iePolicySettings = $ieRegKey.CreateSubKey($proxyPolicyRegPath, [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree)
        $iePolicySettings.SetValue("ProxySettingsPerUser", 0)
        $iePolicySettings.Dispose()
    }

    & $setProxyPolicy $hklm64
    & $setProxyPolicy $hklm32

    # Set proxy for WinINET at machine level
    $proxyRegPath = "Software\Microsoft\Windows\CurrentVersion\Internet Settings"
    $setProxy = { param ($ieRegKey)
        $ieSettings = $ieRegKey.CreateSubKey($proxyRegPath, [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree)
        $ieSettings.SetValue("AutoDetect", 0)
        $ieSettings.SetValue("ProxyEnable", 1)
        $ieSettings.SetValue("MigrateProxy", 0)
        $ieSettings.SetValue("ProxyServer", $proxyServers, [Microsoft.Win32.RegistryValueKind]::String)
        $ieSettings.SetValue("ProxyOverride", $bypassList)
        $ieSettings.Dispose()
    }

    & $setProxy $hklm64
    & $setProxy $hklm32

    $hklm64.Dispose()
    $hklm32.Dispose()

    # Set proxy for WinHTTP
    netsh winhttp set proxy proxy-server="$proxyServers" bypass-list="$bypassList"

    # Run Internet Explorer with an interactive logon token to
    # initialize the system proxy.
    # I agree, it is weird, but it is the only workaround that does not require
    # the user to RDP into the box and initialize IE.
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = "powershell.exe"
    $startInfo.Arguments = "/c", "(new-object -ComObject internetexplorer.application).navigate('127.0.0.1')"
    $startInfo.RedirectStandardOutput = $true
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $false
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    $process.Start()
    $process.WaitForExit()
}

Write-Output "Getting local IP ..."
$localIP = (Find-NetRoute -RemoteIPAddress $k8MasterIP)[0].IPAddress
Write-Output "Found local IP: ${localIP}"

if($k8sServSubnet -eq ""){
  $k8sServSubnet="172.16.0.0/16"
}

$env:WIN_K8S_SERV_SUBNET = $k8sServSubnet
$env:WIN_K8S_IP = "${k8MasterIP}:${k8sPort}"
$env:WIN_K8S_QUERY_PERIOD = $k8sQueryPeriod
$env:WIN_K8S_EXTERNAL_IP = $localIP
if($k8sAllowedSubnet -ne ""){
  $env:WIN_K8S_ALLOWED_SUBNET = $k8sAllowedSubnet
}

Write-Output @"
Installing win-k8s-connector using:
    WIN_K8S_SERV_SUBNET=$($env:WIN_K8S_SERV_SUBNET)
    WIN_K8S_IP=$($env:WIN_K8S_IP)
    WIN_K8S_QUERY_PERIOD=$($env:WIN_K8S_QUERY_PERIOD)
    WIN_K8S_EXTERNAL_IP=$($env:WIN_K8S_EXTERNAL_IP)
"@
if($k8sAllowedSubnet -ne ""){
  Write-Output "    WIN_K8S_ALLOWED_SUBNET=$($env:WIN_K8S_ALLOWED_SUBNET)"
}
cmd /c "$wd\win-k8s-conn-installer.exe /Q"
Write-Output "Finished installing win-k8s-connector."

$env:FLANNEL_ETCD_ENDPOINTS = "https://${k8MasterIP}:${etcdPort}"
$env:FLANNEL_INSTALL_DIR = $flannelInstallDir
$env:FLANNEL_USER_PASSWORD = $flannelUserPassword
$env:FLANNEL_EXT_INTERFACE = $localIP
$env:FLANNEL_ETCD_KEYFILE = $etcdKeyfile
$env:FLANNEL_ETCD_CERTFILE = $etcdCertFile
$env:FLANNEL_ETCD_CAFILE = $etcdCaFile

Write-Output @"
Installing flannel using:
    FLANNEL_ETCD_ENDPOINTS=$($env:FLANNEL_ETCD_ENDPOINTS)
    FLANNEL_INSTALL_DIR=$($env:FLANNEL_INSTALL_DIR)
    FLANNEL_USER_PASSWORD=$($env:FLANNEL_USER_PASSWORD)
    FLANNEL_EXT_INTERFACE=$($env:FLANNEL_EXT_INTERFACE)
    FLANNEL_ETCD_KEYFILE=$($env:FLANNEL_ETCD_KEYFILE)
    FLANNEL_ETCD_CERTFILE=$($env:FLANNEL_ETCD_CERTFILE)
    FLANNEL_ETCD_CAFILE=$($env:FLANNEL_ETCD_CAFILE)
"@
cmd /c "$wd\flannel-installer.exe /Q"
Write-Output "Finished installing flannel"

Write-Output "Getting dns server ..."
$kubedns = (curl "${k8MasterIP}:${k8sPort}/api/v1/namespaces/kube-system/services/kube-dns").Content | ConvertFrom-Json
$dns = $kubedns.spec.ClusterIP
Write-Output "Found dns ${dns}"
Write-Output "Setting dns server..."
Get-NetAdapter | Set-DnsClientServerAddress -ServerAddresses ($dns)
Write-Output "Finished setting dns server"

Write-Output "Waiting for services to start ..."
Start-Sleep -s 30

#Check if the services are started and running ok

function CheckService
{
	Param($serviceName)
	$rez = (get-service $serviceName -ErrorAction SilentlyContinue)

	if ($rez -ne $null) {
		if ($rez.Status.ToString().ToLower() -eq "running"){
			write-host "INFO: Service $serviceName is running"
		}else{
			write-warning "Service $serviceName is not running. Its status is $rez.Status"
      Write-Output "Please look in the logs C:\$serviceName\logs for a possible reason."
		}

	}else{
		write-warning "Service $serviceName not found"
	}
}

#List of services to check if started
$services = @("win-k8s-connector","flannel")

foreach ($service in $services){
	CheckService($service)
}

Write-Output "Getting rpmgr IP ..."
$rpmgr = (curl "${k8MasterIP}:${k8sPort}/api/v1/namespaces/hcp/services/rpmgr-int").Content | ConvertFrom-Json
$rpmgrip = $rpmgr.spec.ClusterIP
Write-Output "Found rpmgr IP: ${rpmgrip}"

Write-Output "Checking route ..."
$netroute = (Find-NetRoute -RemoteIPAddress $rpmgrip).DestinationPrefix
if ($netroute -ne "0.0.0.0/0") {
    Write-Host "Found route ${netroute}"
}
else {
    Write-Error "Could not find route"
    exit 1
}

Write-Output "Checking dns ..."
Resolve-DnsName "nats-int.hcp.svc.cluster.hcp"
Write-Output "Finished."