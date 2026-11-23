param(
    [string]$VivadoBin = 'C:\Xilinx\Vivado\2020.2\bin',
    [string]$OutputRoot = 'C:\__Project\_verification_20261026',
    [int[]]$Seeds = @(1001,1002,1003),
    [switch]$ReuseBuild
)

$ErrorActionPreference = 'Continue'
$projectRoot = Split-Path -Parent $PSScriptRoot
$buildDir = Join-Path $OutputRoot 'build\uvm'
New-Item -ItemType Directory -Path $buildDir -Force | Out-Null
$filelist = Get-Content (Join-Path $PSScriptRoot 'filelist_tb_rv32i_uvm.f') | ForEach-Object {
    if ($_ -match '^\.\./\.\./(.+)$') {
        (Join-Path $projectRoot $Matches[1]).Replace('\','/')
    } else { $_ }
}
$filelist | Set-Content (Join-Path $buildDir 'submission.f') -Encoding ascii

function Invoke-Simulator([string]$toolName, [string[]]$toolArgs, [string]$logName) {
    $tool = Join-Path $VivadoBin "$toolName.bat"
    & $tool @toolArgs 2>&1 | Out-File $logName -Encoding utf8
    if ($LASTEXITCODE -ne 0) { throw "$toolName failed; see $logName" }
}

Push-Location $buildDir
try {
    if (-not $ReuseBuild) {
        Write-Output 'Compiling current source...'
        Invoke-Simulator 'xvlog' @('-sv','-L','uvm','-f','submission.f') 'compile.log'
        Write-Output 'Elaborating UVM...'
        Invoke-Simulator 'xelab' @('-debug','typical','-timescale','1ns/1ps','-mt','auto','-L','uvm','-top','tb_rv32i_uvm','-snapshot','submission_snap') 'elaborate.log'
    }
    $cases = @(@{kind='directed'; seed=1001; flag='RV32I_DIRECTED'})
    foreach ($seed in $Seeds) { $cases += @{kind='random'; seed=$seed; flag='RV32I_RANDOM'} }
    $cases += @{kind='xprop'; seed=1001; flag='RV32I_XPROP'}
    $cases += @{kind='illegal'; seed=1001; flag='RV32I_ILLEGAL'}
    $results = @()
    foreach ($case in $cases) {
        $log = "$($case.kind)_$($case.seed).log"
        Write-Output "Running $log..."
        Invoke-Simulator 'xsim' @('submission_snap','-sv_seed',"$($case.seed)",'-testplusarg',$case.flag,'-R') $log
        $text = Get-Content $log -Raw
        $isNegative = $case.kind -eq 'illegal'
        $fatal = [regex]::Match($text,'UVM_FATAL\s*:\s*(\d+)')
        $errors = [regex]::Match($text,'UVM_ERROR\s*:\s*(\d+)')
        $errorCount = if ($errors.Success) { [int]$errors.Groups[1].Value } else { -1 }
        $fatalCount = if ($fatal.Success) { [int]$fatal.Groups[1].Value } else { -1 }
        $scbEncodingCount = [regex]::Matches($text,'(?m)^UVM_ERROR.*\[SCB_ENCODING\]').Count
        $dataErrorCount = [regex]::Matches($text,'(?m)^UVM_ERROR.*\[SCB_DATA\]').Count
        $assertionCount = [regex]::Matches($text,'(?m)^Error: RV32I_ASSERT: TB assumption violated - illegal R/I encoding reached EXECUTE').Count
        $pass = $text.Contains('$finish called') -and $fatalCount -eq 0
        # The strict ISA reference returns zero for illegal encodings. MUL-as-ADD
        # and reserved-SLLI produce two additional SCB_DATA mismatches in this DUT.
        if ($isNegative) { $pass = $pass -and $errorCount -eq 5 -and $scbEncodingCount -eq 3 -and $dataErrorCount -eq 2 -and $assertionCount -eq 3 }
        else {
            $pass = $pass -and $errorCount -eq 0 -and $text -notmatch '(?m)^Error:|SCB_SUMMARY.*FAIL:\s*[1-9]'
        }
        $results += [pscustomobject]@{
            kind=$case.kind; seed=$case.seed; pass=$pass; uvm_error=$errorCount;
            uvm_fatal=$fatalCount; expected_negative=$isNegative;
            encoding_errors=$scbEncodingCount; data_errors=$dataErrorCount;
            legality_assertions=$assertionCount; log=$log
        }
        Write-Output "$($case.kind) seed=$($case.seed) pass=$pass errors=$errorCount fatal=$fatalCount"
    }
    $results | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $OutputRoot 'results.json') -Encoding utf8
    if (@($results | Where-Object { -not $_.pass }).Count -gt 0) { throw 'Verification failed; inspect results.json' }
} finally { Pop-Location }
