<#
.SYNOPSIS
    Konvertiert GTA-V-formatige .ydr/.ybn aus Sollumz ins RDR2-Format.

.DESCRIPTION
    Ruft CitiCon aus dem RedM-Client auf. CitiCon schreibt die konvertierte
    Datei als "<name>_nya.<ext>" neben das Original; dieses Skript sammelt sie
    ein, benennt zurueck und legt sie im Zielordner ab.

    Der Aufruf ist "CitiCon.com formats:convert <datei> [<datei> ...]",
    ausgefuehrt mit dem RedM.app-Ordner als Arbeitsverzeichnis.

.EXAMPLE
    .\tools\convert_to_rdr2.ps1 -InputPath out\export -OutputPath me_cubetest\stream

.EXAMPLE
    # Ganzer Terrain-Lauf, in Bloecken zu 50 Dateien
    .\tools\convert_to_rdr2.ps1 -InputPath out\export -OutputPath out\rdr2 -BatchSize 50
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$InputPath,
    [Parameter(Mandatory = $true)][string]$OutputPath,
    [string]$RedMPath = "$env:LOCALAPPDATA\RedM\RedM.app",
    [int]$BatchSize = 25
)

$ErrorActionPreference = 'Stop'

$citicon = Join-Path $RedMPath 'CitiCon.com'
if (-not (Test-Path $citicon)) {
    throw "CitiCon nicht gefunden unter '$citicon'. RedM-Pfad mit -RedMPath angeben."
}

$files = Get-ChildItem -Path $InputPath -Include *.ydr, *.ybn -Recurse -File
if ($files.Count -eq 0) { throw "Keine .ydr/.ybn unter '$InputPath' gefunden." }

New-Item -ItemType Directory -Force -Path $OutputPath | Out-Null
$work = Join-Path ([System.IO.Path]::GetTempPath()) ("c2rdr_" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $work | Out-Null

Write-Host "$($files.Count) Dateien, Bloecke zu $BatchSize" -ForegroundColor Cyan
$done = 0; $failed = @()

try {
    for ($i = 0; $i -lt $files.Count; $i += $BatchSize) {
        $batch = $files[$i..([Math]::Min($i + $BatchSize - 1, $files.Count - 1))]
        $copies = foreach ($f in $batch) {
            $dst = Join-Path $work $f.Name
            Copy-Item $f.FullName $dst -Force
            $dst
        }

        # CitiCon erwartet den RedM-Ordner als Arbeitsverzeichnis.
        Push-Location $RedMPath
        try {
            $quoted = $copies | ForEach-Object { '"{0}"' -f $_ }
            & $citicon 'formats:convert' @quoted 2>&1 | Out-Null
        } finally {
            Pop-Location
        }

        foreach ($src in $copies) {
            $dir  = Split-Path $src -Parent
            $base = [IO.Path]::GetFileNameWithoutExtension($src)
            $ext  = [IO.Path]::GetExtension($src)
            $nya  = Join-Path $dir ($base + '_nya' + $ext)

            if (Test-Path $nya) {
                Move-Item $nya (Join-Path $OutputPath ($base + $ext)) -Force
                $done++
            } else {
                $failed += ($base + $ext)
            }
        }
        Write-Progress -Activity 'Konvertiere' -Status "$done / $($files.Count)" `
            -PercentComplete (100.0 * $done / $files.Count)
    }
} finally {
    Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "$done konvertiert -> $OutputPath" -ForegroundColor Green
if ($failed.Count -gt 0) {
    Write-Host "$($failed.Count) fehlgeschlagen:" -ForegroundColor Yellow
    $failed | Select-Object -First 20 | ForEach-Object { Write-Host "  $_" }
    if ($failed.Count -gt 20) { Write-Host "  ... und $($failed.Count - 20) weitere" }
}
