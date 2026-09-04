$exe = "C:\Program Files\OpenSCAD\openscad.exe"
$dir = $PSScriptRoot

if (-not (Test-Path $exe)) {
    Write-Error "OpenSCAD not found: $exe"
    exit 1
}

$parts = @(
    "hydrowin_shell",
    "hydrowin_standoffs_board",
    "hydrowin_standoffs_dcdc",
    "hydrowin_base",
    "hydrowin_lid"
)

foreach ($part in $parts) {
    $scad = Join-Path $dir "$part.scad"
    $stl  = Join-Path $dir "$part.stl"
    Write-Host "Export $part.stl ..."
    & $exe -o $stl $scad
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

Write-Host "Done."
