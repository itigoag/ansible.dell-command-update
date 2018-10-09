#!powershell

# Copyright: (c) 2018, Simon Baerlocher <s.baerlocher@sbaerlocher.ch>
# Copyright: (c) 2018, ITIGO AG <opensource@itigo.ch>
# GNU General Public License v3.0+ (see COPYING or https://www.gnu.org/licenses/gpl-3.0.txt)

#Requires -Module Ansible.ModuleUtils.ArgvParser
#Requires -Module Ansible.ModuleUtils.CommandUtil
#Requires -Module Ansible.ModuleUtils.Legacy

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

$params = Parse-Args -arguments $args -supports_check_mode $true
$check_mode = Get-AnsibleParam -obj $params -name "_ansible_check_mode" -type "bool" -default $false

$state = Get-AnsibleParam -obj $params -name "state" -type "str" -default "update" -validateset "update", "import"
$policy = Get-AnsibleParam -obj $params -name "policy" -type "str"


$result = @{
    changed = $false
}

$dcu_app = Get-Command -Name "C:\Program Files (x86)\Dell\CommandUpdate\dcu-cli.exe" -CommandType Application -ErrorAction SilentlyContinue
if (-not $dcu_app) {
    Fail-Json -obj $result -message "Failed to find Dell Command | Update, please install it"
}

function Invoke-SuspendBitlocker {

    $bitlockerstatus = (Get-Bitlockervolume -MountPoint $env:SystemDrive).ProtectionStatus
    if ($bitlockerstatus -eq "On" -and $option -ne "import") {

        $bitlockerPause = (Suspend-BitLocker -MountPoint "$($env:SystemDrive)" -RebootCount 1).ProtectionStatus
        if ($bitlockerPause -ne "off" ) {
            Fail-Json -obj $result -message "Bitlocker is activated and could not be paused."
        }
    }
}

function Get-ExitCode {

    param(
        $exitcode
    )

    switch ($res.ExitCode) {
        0 { 
            $result = @{
                changed = $true
            }
        }
        1 {
            Invoke-SuspendBitlocker
            $result = @{
                changed = $true
                reboot_required = $true
            }
        }
        2 { Fail-Json -obj $result -message "Fatal error during patch-process Check log files."}
        3 { Fail-Json -obj $result -message "Error during patch-process Check log files." }
        4 { Fail-Json -obj $result -message "Dell Update Command detected an invalid system and stopped." }
        5 {
            Invoke-SuspendBitlocker
            $result = @{
                changed = $true
                reboot_required = $true
            }
        }
    }
}
function Set-DellCommamdUpdatePolicy {

    param(
        $dcu_app,
        $policy
    )

    $argumentList = Argv-ToString -arguments @("/import", "/policy", $policy)
    $res = Start-Process "$($dcu_app.Path)" -wait -PassThru -ArgumentList $argumentList
    Get-ExitCode -exitcode $res.ExitCode
}

function Update-DellCommamdUpdate {

    param(
        $dcu_app,
        $policy
    )

    $argumentList = Argv-ToString -arguments @("/policy", $policy)
    $res = Start-Process "$($dcu_app.Path)" -wait -PassThru -ArgumentList $argumentList
    Get-ExitCode -exitcode $res.ExitCode
}

if (-not $check_mode) {
    if ($state -eq "import"){
        Set-DellCommamdUpdatePolicy -dcu_app $dcu_app -policy $policy
    } elseif ($state -eq "update"){
        Update-DellCommamdUpdate -dcu_app $dcu_app -policy $policy
    }
}

# Return result
Exit-Json -obj $result