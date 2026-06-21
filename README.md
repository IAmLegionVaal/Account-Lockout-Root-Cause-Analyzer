# Account Lockout Root Cause Analyzer

A defensive PowerShell toolkit for account-lockout evidence collection, root-cause analysis and selected guarded recovery actions.

## Repair workflow

Preview an account unlock:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\Account_Lockout_Repair_Toolkit.ps1 -Identity jsmith -UnlockAccount -DryRun
```

Examples:

```powershell
.\Account_Lockout_Repair_Toolkit.ps1 -Identity jsmith -UnlockAccount
.\Account_Lockout_Repair_Toolkit.ps1 -PurgeKerberosTickets
.\Account_Lockout_Repair_Toolkit.ps1 -RestartNetlogon
.\Account_Lockout_Repair_Toolkit.ps1 -Identity jsmith -UnlockAccount -PurgeKerberosTickets -Yes
```

## What the repair does

- Requires an elevated Windows PowerShell session and the RSAT Active Directory module.
- Exports the target user's lockout state and selected attributes to JSON before unlocking it.
- Refuses automated unlocks for accounts marked as protected administrative accounts.
- Can purge Kerberos tickets for the current logon session or restart the local Netlogon service.
- Supports `-DryRun`, an interactive confirmation prompt, `-Yes`, timestamped action logs and post-repair verification.
- Uses exit code `0` for success, `2` for invalid input, `3` for missing privileges or prerequisites, `4` for cancellation, `5` for action failure and `6` for verification failure.

## Safety

Review the analyzer evidence before unlocking an account. Unlocking does not correct saved credentials, mapped drives, services, mobile devices or scheduled tasks that may immediately lock the account again. The repair tool does not reset passwords, delete credentials or alter domain lockout policy.

## Author

Dewald Pretorius — L2 IT Support Engineer
