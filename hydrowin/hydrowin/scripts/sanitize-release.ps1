# Убирает пути сборки и упоминания среды разработки из папок для передачи.
param(
    [string[]]$Targets = @(
        "C:\GidroVin\Windows",
        "C:\GidroVin\Windows_new",
        "C:\GidroVin\Web",
        "C:\hydrowin\release\windows",
        "C:\hydrowin\release\web"
    )
)

$ErrorActionPreference = "SilentlyContinue"

$cleanNativeAssets = @'
{"format-version":[1,0,0],"native-assets":{"windows_x64":{"package:sqlite3/src/ffi/libsqlite3.g.dart":["absolute","sqlite3.dll"]}}}
'@.Trim()

$cleanNativeManifest = @'
{"format-version":[1,0,0],"native-assets":{"windows_x64":{"package:sqlite3/src/ffi/libsqlite3.g.dart":["absolute","sqlite3.dll"]}}}
'@.Trim()

foreach ($root in $Targets) {
    if (-not (Test-Path $root)) { continue }

    foreach ($name in @("native_assets.json", "data\flutter_assets\NativeAssetsManifest.json")) {
        $path = Join-Path $root $name
        if (Test-Path $path) {
            Set-Content -Path $path -Value $cleanNativeAssets -Encoding UTF8 -NoNewline
        }
    }

    Get-ChildItem $root -Recurse -File -Include *.json,*.txt,*.bat,*.md,*.html -ErrorAction SilentlyContinue |
        ForEach-Object {
            $content = Get-Content $_.FullName -Raw -ErrorAction SilentlyContinue
            if (-not $content) { return }
            $new = $content `
                -replace '\\Users\\[^\\]+\\\.cursor\\[^\r\n"''\\]+', '' `
                -replace 'C:\\Users\\HYDRO\\[^\r\n"''\\]+', '' `
                -replace 'C:\\hydrowin\\mobile\\hydrowin\\build\\native_assets\\windows\\sqlite3\.dll', 'sqlite3.dll' `
                -replace 'Programs\\cursor\\[^\r\n;''"]+', '' `
                -replace 'cursor-sandbox-cache\\[^\r\n"''\\]+', ''
            if ($new -ne $content) {
                Set-Content -Path $_.FullName -Value $new -Encoding UTF8
            }
        }
}

Write-Host "Sanitized release folders." -ForegroundColor Green
