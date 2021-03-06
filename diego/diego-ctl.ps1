param(
    [Parameter(Mandatory=$true, Position=1)]
    [ValidateSet('start', 'run', 'stop', 'status', 'watch-status')]
    [string]$Action,

    [Parameter(Mandatory=$false, Position=2)]
    [ValidateSet("all", "converger", "consul", "rep", "auctioneer" , "garden-windows")]
    [string]$Component = 'all',
    
    [Parameter(Mandatory=$false)]
    [string]$DiegoBinDir = ''
)

$ErrorActionPreference = "Stop"
$isVerbose = [bool]$PSBoundParameters["Verbose"]
$PSDefaultParameterValues = @{"*:Verbose"=$isVerbose}
$currentDir = split-path $SCRIPT:MyInvocation.MyCommand.Path -parent

# If we're running on 32 bit PowerShell, we need to restart in 64 bit mode.
if (($pshome -like "*syswow64*") -and ((Get-WmiObject Win32_OperatingSystem).OSArchitecture -like "64*")) {
    Write-Warning "Restarting script under 64 bit PowerShell"
 
    $powershellLocation = Join-Path ($pshome -replace "syswow64", "sysnative") "powershell.exe"
    $scriptPath = $SCRIPT:MyInvocation.MyCommand.Path
    
    # relaunch this script under 64 bit shell
    $args = "-nologo -file ${scriptPath} -Action $Action -Component $Component -DiegoBinDir `"$DiegoBinDir`""
    if ($isVerbose)
    {
        $args = "$args -Verbose"
    }

    Start-Process -PassThru -NoNewWindow $powershellLocation $args | Out-Null

    # This will exit the original powershell process. This will only be done in case of an x86 process on a x64 OS.
    exit 0
}

function Start-Daemon{[CmdletBinding()]param($daemon)
    $existingDaemonProcess = Get-Daemon $daemon
    
    if ($existingDaemonProcess -eq $null)
    {
        Write-Host "Starting ${daemon} ..."
        $exe = Join-Path $binDir $processes[$daemon]['exe']
        $stdoutLog = Join-Path $logDir $processes[$daemon]['stdout']
        $stderrLog = Join-Path $logDir $processes[$daemon]['stderr']
        $pidFile = Join-Path $pidDir $processes[$daemon]['pid']
        $args = $processes[$daemon]['args']

        $daemonProcess = Start-Process -PassThru -NoNewWindow -RedirectStandardOutput $stdoutLog -RedirectStandardError $stderrLog $exe "${args}"
        $daemonProcess.Id | Out-File $pidFile
        Write-Host "Started ${daemon} with PID $($daemonProcess.Id)."
    }
    else
    {
        Write-Output "${daemon} is already running"
    }
}

function Run-Daemon{[CmdletBinding()]param($daemon)
    $exe = Join-Path $binDir $processes[$daemon]['exe']
    $args = $processes[$daemon]['args']

    $daemonProcess = Start-Process -PassThru -NoNewWindow -Wait $exe "${args}"
}

function Stop-Daemon{[CmdletBinding()]param($daemon)
    $existingDaemonProcess = Get-Daemon $daemon
    
    if ($existingDaemonProcess -ne $null)
    {
        Write-Host "Stopping ${daemon} with PID $($existingDaemonProcess.Id) ..."
        $existingDaemonProcess.Kill()
    }
    else
    {
        Write-Output "${daemon} is not running"
    }
}

function Get-Daemon{[CmdletBinding()]param($daemon)

    $pidFile = Join-Path $pidDir $processes[$daemon]['pid']
    $exe = Join-Path $binDir $processes[$daemon]['exe']

    if (!(Test-Path $pidFile))
    {
        return $null
    }

    try
    {
        $daemonPid = (Get-Content -Raw $pidFile).Trim()
        $daemonProcess = [System.Diagnostics.Process]::GetProcessById($daemonPid)

        if ($daemonProcess.MainModule.FileName -ne $exe)
        {
            Write-Verbose "Process with id ${daemonPid} for ${daemon} is not the expected executable. Should be ${exe} but it's $($daemonProcess.MainModule.FileName)."
            return $null
        }

        return $daemonProcess
    }
    catch
    {
        Write-Verbose "Process with id ${daemonPid} for ${daemon} is not running."
        return $null
    }  
}

function Get-DaemonHumanStatus{[CmdletBinding()]param($daemon)
   $existingDaemonProcess = Get-Daemon $daemon
    
    if ($existingDaemonProcess -ne $null)
    {
        return "Running"
    }
    else
    {
        return "Stopped"
    }    
}

function Check-Paths{[CmdletBinding()]param($daemon)
    if (!(Test-Path $configDir))
    {
        throw "Config dir '${configDir}' not found."
    }

    if (!(Test-Path $binDir))
    {
        throw "Bin dir '${binDir}' not found."
    }

    if (!(Test-Path $consulJsonConfig))
    {
        throw "Consul json config '${consulJsonConfig}' not found."
    }

    if (!(Test-Path $diegoJsonConfig))
    {
        throw "Diego json config '${diegoJsonConfig}' not found."
    }

    mkdir $pidDir -ErrorAction 'SilentlyContinue' | out-null
    mkdir $logDir -ErrorAction 'SilentlyContinue' | out-null
    mkdir $consulDataDir -ErrorAction 'SilentlyContinue' | out-null
}

try
{
    if (![string]::IsNullOrWhiteSpace($DiegoBinDir))
    {
        $binDir = $DiegoBinDir
    }
    else
    {
        $devDiegoBinDir = [System.IO.Path]::GetFullPath((Join-Path $currentDir ".\bin"))

        # See if there are binaries (just check for garden-windows) in the current directory
        # If there aren't, look in .\bin\
        # Error otherwise
        if (Test-Path (Join-Path $currentDir "garden-windows.exe"))
        {
            $binDir = $currentDir
        }
        elseif (Test-Path (Join-Path $devDiegoBinDir "garden-windows.exe"))
        {
            $binDir = $devDiegoBinDir
        }
        else
        {
            throw "Can't find diego binaries. Looked in '${currentDir}' and '${devDiegoBinDir}'."
        }
    }

    $configDir = Join-Path $currentDir 'config'
    $pidDir = Join-Path $currentDir 'pids'
    $logDir = Join-Path $currentDir 'logs'

    $diegoJsonConfig = Join-Path $configDir 'windows-diego.json'
    $consulJsonConfig = Join-Path $configDir 'consul.json'
    $consulDataDir = Join-Path $binDir 'consul_data'

    Check-Paths

    $diegoConfig = Get-Content -Raw $diegoJsonConfig | ConvertFrom-Json

    $etcdCluster = $diegoConfig.etcdCluster
    $consulCluster = $diegoConfig.consulCluster
	$consulRecursors = ($diegoConfig.consulRecursors.Split(",", [StringSplitOptions]::RemoveEmptyEntries) | % { "-recursor `"$($_)`"" }) -join " "

    $gardenListenNetwork = $diegoConfig.gardenListenNetwork
    $gardenListenAddr = $diegoConfig.gardenListenAddr
    $gardenLogLevel = $diegoConfig.gardenLogLevel
    $gardenCellIP = $diegoConfig.gardenCellIP

    $consulServerIp = $diegoConfig.consulServerIp

    $repCellID = $diegoConfig.repCellID
    $repZone = $diegoConfig.repZone
    $repMemoryMB = $diegoConfig.repMemoryMB
    $repDiskMB = $diegoConfig.repDiskMB
    $repListenAddr = $diegoConfig.repListenAddr
    $repRootFSProvider = $diegoConfig.repRootFSProvider
    $repContainerMaxCpuShares = $diegoConfig.repContainerMaxCpuShares
    $repContainerInodeLimit = $diegoConfig.repContainerInodeLimit
    $bbsAddress = $diegoConfig.bbsAddress

    $processes = @{
        "converger" = @{
            "exe" = "converger.exe";
            "stdout" = "converger.stdout.log";
            "stderr" = "converger.stderr.log";
            "pid" = "converger.pid";
            "args" = "-etcdCluster ${etcdCluster} -consulCluster=`"${consulCluster}`"";
        };
        "consul" = @{
            "exe" = "consul.exe";
            "stdout" = "consul.stdout.log";
            "stderr" = "consul.stderr.log";
            "pid" = "consul.pid";
            "args" = "agent -bind ${gardenCellIP} -config-file ${consulJsonConfig} -data-dir ${consulDataDir} -join ${consulServerIp} ${consulRecursors}";
        };
        "rep" = @{
            "exe" = "rep.exe";
            "stdout" = "rep.stdout.log";
            "stderr" = "rep.stderr.log";
            "pid" = "rep.pid";
            "args" = "-etcdCluster ${etcdCluster} -bbsAddress=`"${bbsAddress}`" -consulCluster=`"${consulCluster}`" -cellID=${repCellID} -zone=${repZone} -rootFSProvider=${repRootFSProvider} -listenAddr=${repListenAddr} -gardenNetwork=${gardenListenNetwork} -gardenAddr=${gardenListenAddr} -memoryMB=${repMemoryMB} -diskMB=${repDiskMB} -containerMaxCpuShares=${repContainerMaxCpuShares} -containerInodeLimit=${repContainerInodeLimit} -allowPrivileged -skipCertVerify -exportNetworkEnvVars";
        };
        "auctioneer" = @{
            "exe" = "auctioneer.exe";
            "stdout" = "auctioneer.stdout.log";
            "stderr" = "auctioneer.stderr.log";
            "pid" = "auctioneer.pid";
            "args" = "-etcdCluster ${etcdCluster} -consulCluster=`"${consulCluster}`" -bbsAddress=`"${bbsAddress}`"";
        };
        "garden-windows" = @{
            "exe" = "garden-windows.exe";
            "stdout" = "garden-windows.stdout.log";
            "stderr" = "garden-windows.stderr.log";
            "pid" = "garden-windows.pid";
            "args" = "-listenNetwork=${gardenListenNetwork} -listenAddr=${gardenListenAddr} -logLevel=${gardenLogLevel} -cellIP=${gardenCellIP}";
        };
    }

    if ($Component -eq 'all')
    {
        if ($Action -eq 'run')
        {
            throw "Cannot 'run' more than one process at a time. Either use 'start' or specify a single service."
        }
        
        $processesToAct = $processes.Keys
    }
    else
    {
        $processesToAct = @($Component)
    }

    switch ($Action)
    {
        "unregister-prison" {
            Unregister-Prison
        }
        "register-prison" {
            Register-Prison
        }
        "start" {
            foreach ($daemon in $processesToAct)
            {
                Start-Daemon $daemon
            }
        }
        "run" {
            Run-Daemon $processesToAct[0]
        }
        "stop" {
            foreach ($daemon in $processesToAct)
            {
                Stop-Daemon $daemon
            }
        }
        "status" {
            $processesToAct | ForEach-Object {
                New-Object PSObject -Property @{
                    "Component" = $_
                    "Status" = Get-DaemonHumanStatus $_
                }
            } | Format-Table
        }
        "watch-status" {
            while ($true)
            {
                cls
                $processesToAct | ForEach-Object {
                    New-Object PSObject -Property @{
                        "Component" = $_
                        "Status" = Get-DaemonHumanStatus $_
                    }
                } | Format-Table
                sleep 2
            }
        }
    }

    exit 0
}
catch
{
    $errorMessage = $_.Exception.Message
    Write-Host -ForegroundColor Red "${errorMessage}"
    Write-Verbose $_.Exception

    exit 1
}