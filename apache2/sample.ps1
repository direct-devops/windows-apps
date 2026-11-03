<#
.SYNOPSIS
  Installs Apache (via Chocolatey) on Windows and deploys the Tooplate "Sweet Bakery" template.

.USAGE
  Run in an elevated PowerShell:
    Set-ExecutionPolicy Bypass -Scope Process -Force
    .\deploy.ps1
    .\deploy.ps1 -Port 80
#>

param(
    [int]$Port = 8080,
    [string]$TemplateUrl = "https://www.tooplate.com/zip-templates/2168_sweet_bakery.zip"
)

$ErrorActionPreference = "Stop"

function Write-Step($msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }

# 0. Admin check
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
           ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "Please run this script as Administrator." -ForegroundColor Red
    exit 1
}

# 1. Chocolatey
Write-Step "Checking Chocolatey"
if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
    Write-Host "Installing Chocolatey..."
    Set-ExecutionPolicy Bypass -Scope Process -Force
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
    Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
    $env:Path += ";$env:ALLUSERSPROFILE\chocolatey\bin"
} else {
    Write-Host "Chocolatey already installed."
}

# 2. Apache
Write-Step "Locating Apache"
$candidates = @(
    "$env:APPDATA\Apache24",
    "C:\Users\Administrator\AppData\Roaming\Apache24",
    "C:\Apache24",
    "C:\tools\Apache24"
)
$apacheRoot = $candidates | Where-Object { Test-Path "$_\bin\httpd.exe" } | Select-Object -First 1

if (-not $apacheRoot) {
    Write-Step "Installing Apache (apache-httpd) and VC++ runtime"
    choco install vcredist140 -y --no-progress
    choco install apache-httpd -y --no-progress
    $apacheRoot = $candidates | Where-Object { Test-Path "$_\bin\httpd.exe" } | Select-Object -First 1
}

if (-not $apacheRoot) {
    Write-Host "Could not find Apache after install. Run: where /r C:\ httpd.exe" -ForegroundColor Red
    exit 1
}
Write-Host "Apache found at: $apacheRoot"

$httpd = Join-Path $apacheRoot "bin\httpd.exe"
$conf  = Join-Path $apacheRoot "conf\httpd.conf"
$htdocs = Join-Path $apacheRoot "htdocs"

# 3. Configure port
Write-Step "Configuring port $Port"
Copy-Item $conf "$conf.bak" -Force
$content = Get-Content $conf -Raw
$content = $content -replace '(?m)^Listen\s+.*$', "Listen $Port"
$content = $content -replace '(?m)^#?ServerName\s+.*$', "ServerName localhost:$Port"
Set-Content -Path $conf -Value $content -Encoding ASCII

# Make sure htdocs allows access
if ($content -match '(?s)<Directory "\$\{SRVROOT\}/htdocs">.*?Require local.*?</Directory>') {
    $content = $content -replace '(?s)(<Directory "\$\{SRVROOT\}/htdocs">.*?)Require local(.*?</Directory>)', '$1Require all granted$2'
    Set-Content -Path $conf -Value $content -Encoding ASCII
}

Write-Step "Testing Apache config"
& $httpd -t

# 4. Download and extract template
Write-Step "Downloading template"
$zip = Join-Path $env:TEMP "sweet_bakery.zip"
$extract = Join-Path $env:TEMP "sweet_bakery"
if (Test-Path $extract) { Remove-Item $extract -Recurse -Force }

try {
    Invoke-WebRequest -Uri $TemplateUrl -OutFile $zip -UserAgent "Mozilla/5.0" -UseBasicParsing
} catch {
    Write-Host "Download failed: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Download the zip in a browser, save it to $zip and re-run this script."
    if (-not (Test-Path $zip)) { exit 1 }
}

Write-Step "Extracting template"
Expand-Archive -Path $zip -DestinationPath $extract -Force

$indexFile = Get-ChildItem $extract -Recurse -Filter "index.html" | Select-Object -First 1
if (-not $indexFile) {
    Write-Host "index.html not found in the extracted template." -ForegroundColor Red
    exit 1
}
$siteSource = $indexFile.DirectoryName
Write-Host "Template source: $siteSource"

# 5. Deploy to htdocs (with backup)
Write-Step "Deploying to $htdocs"
$backup = "$htdocs`_backup"
if ((Test-Path $htdocs) -and -not (Test-Path $backup)) {
    Copy-Item $htdocs $backup -Recurse -Force
}
Get-ChildItem $htdocs -Force | Remove-Item -Recurse -Force
robocopy $siteSource $htdocs /E /NFL /NDL /NJH /NJS | Out-Null

# 6. Firewall
Write-Step "Opening firewall port $Port"
$ruleName = "Apache $Port"
if (-not (Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -DisplayName $ruleName -Direction Inbound -Action Allow -Protocol TCP -LocalPort $Port | Out-Null
}

# 7. Service
Write-Step "Installing and starting Apache service"
$svc = Get-Service -Name "Apache*" -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $svc) {
    & $httpd -k install
    $svc = Get-Service -Name "Apache*" -ErrorAction SilentlyContinue | Select-Object -First 1
}
if ($svc) {
    Set-Service -Name $svc.Name -StartupType Automatic
    if ($svc.Status -eq "Running") { Restart-Service -Name $svc.Name } else { Start-Service -Name $svc.Name }
} else {
    & $httpd -k start
}

# 8. Final restart of the Apache service
Write-Step "Restarting Apache service"
$svc = Get-Service -Name "Apache*" -ErrorAction SilentlyContinue | Select-Object -First 1
if ($svc) {
    Restart-Service -Name $svc.Name -Force
    Start-Sleep -Seconds 2
    Get-Service -Name $svc.Name | Format-Table Name, Status, StartType -AutoSize
} else {
    & $httpd -k restart
}

# 9. Verify
Write-Step "Verifying"
Start-Sleep -Seconds 3
try {
    $resp = Invoke-WebRequest -Uri "http://localhost:$Port" -UseBasicParsing -TimeoutSec 10
    Write-Host "HTTP $($resp.StatusCode) - site is up." -ForegroundColor Green
} catch {
    Write-Host "Could not reach http://localhost:$Port : $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Host "Check: $apacheRoot\logs\error.log"
}

$publicIp = $null
try { $publicIp = (Invoke-RestMethod -Uri "https://ifconfig.me/ip" -TimeoutSec 5).Trim() } catch {}

Write-Host "`nDone." -ForegroundColor Green
Write-Host "Local:  http://localhost:$Port"
if ($publicIp) { Write-Host "Public: http://$publicIp`:$Port  (also open TCP $Port in your cloud security group)" }
