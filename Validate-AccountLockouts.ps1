#requires -Version 5.1
<# Created by Dewald Pretorius. Read-only account lockout validator. #>
[CmdletBinding()]param([ValidateRange(1,720)][int]$Hours=24,[ValidateRange(1,10000)][int]$WarningCount=10,[string]$OutputPath=(Join-Path ([Environment]::GetFolderPath('Desktop')) 'Account_Lockout_Validation'))
$ErrorActionPreference='Stop';New-Item -ItemType Directory $OutputPath -Force|Out-Null;$s=Get-Date -Format yyyyMMdd_HHmmss
try{$events=@(Get-WinEvent -FilterHashtable @{LogName='Security';Id=4740;StartTime=(Get-Date).AddHours(-$Hours)} -ErrorAction Stop|Select-Object TimeCreated,MachineName,Message);$events|Export-Csv (Join-Path $OutputPath "lockouts_$s.csv") -NoTypeInformation;[ordered]@{Generated=(Get-Date);Hours=$Hours;LockoutCount=$events.Count;WarningThreshold=$WarningCount}|ConvertTo-Json|Set-Content (Join-Path $OutputPath "summary_$s.json");if($events.Count-ge$WarningCount){exit 1};exit 0}catch{Write-Error $_;exit 5}
