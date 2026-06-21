[CmdletBinding()]
param(
    [string]$Identity,
    [switch]$UnlockAccount,
    [switch]$PurgeKerberosTickets,
    [switch]$RestartNetlogon,
    [switch]$DryRun,
    [switch]$Yes,
    [string]$LogDirectory = "$env:ProgramData\IAmLegionVaal\AccountLockoutRepair"
)

$ErrorActionPreference = 'Stop'
$ExitInvalidInput = 2
$ExitPrerequisite = 3
$ExitCancelled = 4
$ExitActionFailure = 5
$ExitVerificationFailure = 6

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Write-Log {
    param([string]$Message)
    $line = "{0:u} {1}" -f (Get-Date), $Message
    Write-Host $line
    Add-Content -LiteralPath $script:LogPath -Value $line
}

function Invoke-RepairAction {
    param([string]$Description, [scriptblock]$Action)
    if ($DryRun) {
        Write-Log "[DRY-RUN] $Description"
        return
    }
    Write-Log "[ACTION] $Description"
    & $Action
}

if (-not ($UnlockAccount -or $PurgeKerberosTickets -or $RestartNetlogon)) {
    Write-Error 'Select at least one repair action.'
    exit $ExitInvalidInput
}
if ($UnlockAccount -and [string]::IsNullOrWhiteSpace($Identity)) {
    Write-Error '-Identity is required with -UnlockAccount.'
    exit $ExitInvalidInput
}
if (-not (Test-IsAdministrator)) {
    Write-Error 'Run this repair script from an elevated PowerShell session.'
    exit $ExitPrerequisite
}

New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$script:LogPath = Join-Path $LogDirectory "AccountLockoutRepair_$stamp.log"
$backupPath = Join-Path $LogDirectory "AccountLockoutRepair_Backup_$stamp.json"

try {
    Import-Module ActiveDirectory -ErrorAction Stop
} catch {
    Write-Error "The ActiveDirectory module is required: $($_.Exception.Message)"
    exit $ExitPrerequisite
}

$user = $null
if ($UnlockAccount) {
    try {
        $user = Get-ADUser -Identity $Identity -Properties LockedOut,Enabled,AdminCount,DistinguishedName,LastBadPasswordAttempt,badPwdCount
    } catch {
        Write-Error "Unable to resolve AD user '$Identity': $($_.Exception.Message)"
        exit $ExitInvalidInput
    }
    if ($user.AdminCount -eq 1) {
        Write-Error 'Protected administrative accounts are intentionally excluded from automated unlock repair.'
        exit $ExitInvalidInput
    }
    $user | Select-Object SamAccountName,Enabled,LockedOut,AdminCount,DistinguishedName,LastBadPasswordAttempt,badPwdCount |
        ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $backupPath -Encoding UTF8
    Write-Log "Saved pre-change AD user evidence to $backupPath"
}

$requested = @()
if ($UnlockAccount) { $requested += "unlock AD account '$Identity'" }
if ($PurgeKerberosTickets) { $requested += 'purge Kerberos tickets for the current logon session' }
if ($RestartNetlogon) { $requested += 'restart the local Netlogon service' }

if (-not $DryRun -and -not $Yes) {
    $answer = Read-Host ("Proceed with: {0}? [y/N]" -f ($requested -join '; '))
    if ($answer -notmatch '^(?i)y(es)?$') {
        Write-Log '[CANCELLED] No changes were made.'
        exit $ExitCancelled
    }
}

try {
    if ($UnlockAccount) {
        Invoke-RepairAction "Unlock AD account '$Identity'" { Unlock-ADAccount -Identity $user.DistinguishedName }
    }
    if ($PurgeKerberosTickets) {
        Invoke-RepairAction 'Purge Kerberos tickets for the current logon session' {
            & klist.exe purge | ForEach-Object { Write-Log "[KLIST] $_" }
            if ($LASTEXITCODE -ne 0) { throw "klist.exe exited with code $LASTEXITCODE" }
        }
    }
    if ($RestartNetlogon) {
        Invoke-RepairAction 'Restart the local Netlogon service' { Restart-Service -Name Netlogon -Force }
    }
} catch {
    Write-Log "[FAILED] $($_.Exception.Message)"
    exit $ExitActionFailure
}

if ($DryRun) {
    Write-Log '[COMPLETE] Dry-run completed; no changes were made.'
    exit 0
}

$verificationFailed = $false
try {
    if ($UnlockAccount) {
        $after = Get-ADUser -Identity $user.DistinguishedName -Properties LockedOut,Enabled,badPwdCount
        Write-Log ("[VERIFY] User={0}; Enabled={1}; LockedOut={2}; badPwdCount={3}" -f $after.SamAccountName,$after.Enabled,$after.LockedOut,$after.badPwdCount)
        if ($after.LockedOut) { $verificationFailed = $true }
    }
    if ($RestartNetlogon) {
        $service = Get-Service -Name Netlogon
        Write-Log "[VERIFY] Netlogon status: $($service.Status)"
        if ($service.Status -ne 'Running') { $verificationFailed = $true }
    }
} catch {
    Write-Log "[VERIFY-FAILED] $($_.Exception.Message)"
    $verificationFailed = $true
}

if ($verificationFailed) { exit $ExitVerificationFailure }
Write-Log '[COMPLETE] Requested repairs completed and verification passed.'
exit 0
