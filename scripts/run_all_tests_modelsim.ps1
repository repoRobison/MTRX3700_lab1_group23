param(
    [string]$ModelSimBin = 'C:\intelFPGA_lite\18.1\modelsim_ase\win32aloem'
)

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$workRoot = Join-Path $projectRoot 'work'
$vlib = Join-Path $ModelSimBin 'vlib.exe'
$vlog = Join-Path $ModelSimBin 'vlog.exe'
$vsim = Join-Path $ModelSimBin 'vsim.exe'

foreach ($tool in @($vlib, $vlog, $vsim)) {
    if (-not (Test-Path -LiteralPath $tool)) {
        throw "ModelSim tool not found: $tool"
    }
}

# Recreate only the project-local, gitignored simulator directory.
if (Test-Path -LiteralPath $workRoot) {
    $resolvedWork = (Resolve-Path -LiteralPath $workRoot).Path
    $resolvedParent = Split-Path -Parent $resolvedWork
    if ($resolvedParent -ne $projectRoot -or (Split-Path -Leaf $resolvedWork) -ne 'work') {
        throw "Refusing to remove unexpected simulator path: $resolvedWork"
    }
    Remove-Item -Recurse -Force -LiteralPath $resolvedWork
}
New-Item -ItemType Directory -Path $workRoot | Out-Null

Push-Location $workRoot
try {
    & $vlib work
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    $sources = @()
    foreach ($folder in @('rtl', 'smoke_test', 'tb')) {
        $sources += Get-ChildItem -Recurse -File -LiteralPath (Join-Path $projectRoot $folder) |
            Where-Object { $_.Extension -in @('.v', '.sv') } |
            Sort-Object FullName |
            Select-Object -ExpandProperty FullName
    }

    # ModelSim-Altera 10.5b reports initial FPGA values plus always_ff as 7061.
    # Quartus and Verilator accept this FPGA power-up pattern; suppress only
    # that legacy-frontend diagnostic, not general warnings.
    & $vlog -sv -suppress 7061 "+incdir+$projectRoot\rtl\common" $sources
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    $failed = 0
    $tests = Get-ChildItem -File -LiteralPath (Join-Path $projectRoot 'tb') |
        Where-Object { $_.Name -match '_tb\.(sv|v)$' } |
        Sort-Object Name

    foreach ($test in $tests) {
        $name = $test.BaseName
        $output = & $vsim -c -quiet "work.$name" -do `
            'onbreak {quit -code 1}; onerror {quit -code 1}; run -all; quit -code 0' 2>&1
        $exitCode = $LASTEXITCODE
        $outputText = $output -join "`n"

        if ($exitCode -eq 0 -and $outputText -match 'PASS' -and
                $outputText -notmatch '\*\* Fatal') {
            Write-Host "PASS  $name"
        } else {
            Write-Host "FAIL  $name"
            $output | Select-Object -Last 40
            $failed++
        }
    }

    Write-Host '-----'
    Write-Host "$($tests.Count - $failed) passed, $failed failed"
    exit $failed
}
finally {
    Pop-Location
}
