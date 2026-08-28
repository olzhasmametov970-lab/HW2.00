# На сервере (RDP / WinRM): поднять Caddy HTTPS
# Запуск ИЗ backend на машине с доступом к 5.165.27.141

$ErrorActionPreference = "Stop"
$RemoteHost = "5.165.27.141"
$User = "Admin2"

Write-Host "=== Enable HTTPS (Caddy) on $RemoteHost ===" -ForegroundColor Cyan
$secure = Read-Host -AsSecureString "Password for ${User}@${RemoteHost}"
$cred = New-Object System.Management.Automation.PSCredential($User, $secure)
$session = New-PSSession -ComputerName $RemoteHost -Credential $cred -ErrorAction Stop

try {
    Write-Host "Ищем docker-compose backend..." -ForegroundColor Yellow
    $remotePath = Invoke-Command -Session $session -ScriptBlock {
        $candidates = @(
            "C:\hydrowin\backend",
            "C:\hydrowin\hydrowin\backend",
            "C:\Users\Admin2\hydrowin\backend"
        )
        foreach ($p in $candidates) {
            if (Test-Path (Join-Path $p "docker-compose.yml")) { return $p }
        }
        Get-ChildItem -Path C:\ -Filter "docker-compose.yml" -Recurse -ErrorAction SilentlyContinue -Depth 4 |
            Where-Object { $_.FullName -match "hydrowin" } |
            Select-Object -First 1 -ExpandProperty DirectoryName
    }
    if (-not $remotePath) { throw "backend с docker-compose.yml не найден" }
    Write-Host "Path: $remotePath"

    Write-Host "Копируем Caddyfile + docker-compose.yml ..." -ForegroundColor Yellow
    $local = $PSScriptRoot
    Copy-Item -ToSession $session -Path "$local\Caddyfile" -Destination $remotePath -Force
    Copy-Item -ToSession $session -Path "$local\docker-compose.yml" -Destination $remotePath -Force

    Invoke-Command -Session $session -ScriptBlock {
        param($p)
        $envPath = Join-Path $p ".env"
        if (-not (Test-Path $envPath)) { throw ".env не найден в $p" }
        $text = Get-Content $envPath -Raw
        if ($text -notmatch "API_DOMAIN=") {
            Add-Content $envPath "`nAPI_DOMAIN=app.hydrowin.ru`nAPP_DOMAIN=app.hydrowin.ru`nACME_EMAIL=admin@hydrowin.ru`n"
        }
        else {
            $text = $text -replace "API_DOMAIN\s*=\s*\S+", "API_DOMAIN=app.hydrowin.ru"
            if ($text -notmatch "APP_DOMAIN=") {
                $text += "`nAPP_DOMAIN=app.hydrowin.ru`n"
            }
            else {
                $text = $text -replace "APP_DOMAIN\s*=\s*\S+", "APP_DOMAIN=app.hydrowin.ru"
            }
            if ($text -notmatch "ACME_EMAIL=") {
                $text += "`nACME_EMAIL=admin@hydrowin.ru`n"
            }
            Set-Content -Path $envPath -Value $text -NoNewline
        }
        # Firewall 80/443
        foreach ($port in 80, 443) {
            $name = "HydroWin-HTTPS-$port"
            if (-not (Get-NetFirewallRule -DisplayName $name -ErrorAction SilentlyContinue)) {
                New-NetFirewallRule -DisplayName $name -Direction Inbound -Protocol TCP -LocalPort $port -Action Allow | Out-Null
                Write-Host "Firewall: opened TCP $port"
            }
        }
        Set-Location $p
        docker compose pull caddy
        docker compose up -d caddy
        Start-Sleep -Seconds 5
        docker compose ps
        docker compose logs --tail 50 caddy
    } -ArgumentList $remotePath

    Write-Host "`nПроверка с этой машины:" -ForegroundColor Yellow
    curl.exe -sI --connect-timeout 10 --max-time 30 "https://app.hydrowin.ru/v1/health"
    Write-Host "`n=== Готово: https://app.hydrowin.ru/v1 ===" -ForegroundColor Green
}
finally {
    Remove-PSSession $session -ErrorAction SilentlyContinue
}
