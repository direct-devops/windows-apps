# Install Apache on Windows and Deploy Template "Sweet Bakery"

Template: https://www.tooplate.com/zip-templates/2168_sweet_bakery.zip

Run all commands in an **elevated** PowerShell (Run as administrator).

Apache install folder used in this guide:

```
C:\Users\Administrator\AppData\Roaming\Apache24
```

---

# Part 1: Install Apache

## 1. Install Chocolatey

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
```

Close and reopen PowerShell (as administrator), then verify:

```powershell
choco --version
```

## 2. Install Apache

On Windows the package is `apache-httpd` (`apache2` is the Linux name).

```powershell
choco install apache-httpd -y
```

If you get a `VCRUNTIME140.dll` error later, install the Visual C++ runtime:

```powershell
choco install vcredist140 -y
```

## 3. Find the install folder

```powershell
dir C:\Users\Administrator\AppData\Roaming\Apache24
dir C:\Apache24
dir C:\tools\Apache24
```

The folder that lists `bin`, `conf` and `htdocs` is your install folder. If none exist:

```powershell
where /r C:\ httpd.exe
```

## 4. Test in the foreground (optional)

```powershell
cd C:\Users\Administrator\AppData\Roaming\Apache24\bin
.\httpd.exe
```

Open `http://localhost` (or the port you configured). You should see **It works!**. Press Ctrl+C to stop.

## 5. Check or change the port

Edit `C:\Users\Administrator\AppData\Roaming\Apache24\conf\httpd.conf`:

```apache
Listen 8080
ServerName localhost:8080
```

Use `80` instead of `8080` if nothing else (such as IIS) uses port 80. Check with:

```powershell
netstat -ano | findstr :80
```

Test the config:

```powershell
.\httpd.exe -t
```

It should print `Syntax OK`.

## 6. Install and start as a Windows service

```powershell
cd C:\Users\Administrator\AppData\Roaming\Apache24\bin
.\httpd.exe -k install
.\httpd.exe -k start
```

Confirm it starts automatically at boot:

```powershell
Get-Service Apache*
```

StartType should be `Automatic`.

## 7. Confirm it is listening

```powershell
netstat -ano | findstr :8080
```

You should see `0.0.0.0:8080` in LISTENING state.

## 8. Open the firewall

Windows Firewall (change the port if you use another):

```powershell
netsh advfirewall firewall add rule name="Apache 8080" dir=in action=allow protocol=TCP localport=8080
```

On a cloud VM (AWS, Azure, GCP), also allow inbound TCP 8080 in the security group / network security group.

## 9. Test access

- On the server: `http://localhost:8080`
- From another computer: `http://<public-ip>:8080`

Find the public IP with `curl ifconfig.me`. Use `http://`, not `https://`.

---

# Part 2: Deploy the Sweet Bakery template

## 10. Download and extract

```powershell
cd $env:TEMP
Invoke-WebRequest -Uri "https://www.tooplate.com/zip-templates/2168_sweet_bakery.zip" -OutFile sweet_bakery.zip -UserAgent "Mozilla/5.0"
Expand-Archive sweet_bakery.zip -DestinationPath sweet_bakery -Force
dir $env:TEMP\sweet_bakery
```

Note the folder name shown (usually `2168_sweet_bakery`). If the download fails, download the zip in a browser and use its saved path instead.

## 11. Back up the default site (optional)

```powershell
Rename-Item "C:\Users\Administrator\AppData\Roaming\Apache24\htdocs" "htdocs_backup"
New-Item -ItemType Directory "C:\Users\Administrator\AppData\Roaming\Apache24\htdocs" | Out-Null
```

## 12. Copy the template into htdocs

```powershell
robocopy "$env:TEMP\sweet_bakery\2168_sweet_bakery" "C:\Users\Administrator\AppData\Roaming\Apache24\htdocs" /E
```

Use the actual folder name from step 10 if it differs. Confirm `index.html` is directly inside `htdocs`:

```powershell
dir C:\Users\Administrator\AppData\Roaming\Apache24\htdocs
```

## 13. Make sure access is allowed

In `httpd.conf`:

```apache
DocumentRoot "${SRVROOT}/htdocs"

<Directory "${SRVROOT}/htdocs">
    Options Indexes FollowSymLinks
    AllowOverride None
    Require all granted
</Directory>

DirectoryIndex index.html
```

## 14. Restart Apache

```powershell
cd C:\Users\Administrator\AppData\Roaming\Apache24\bin
.\httpd.exe -t
.\httpd.exe -k restart
```

## 15. Open the site

- On the server: `http://localhost:8080`
- From another computer: `http://<public-ip>:8080`

Hard refresh with Ctrl+F5 if you still see the old page.

---

# Optional: serve on port 80

1. In `httpd.conf`, set `Listen 80` and `ServerName localhost:80`.
2. Make sure port 80 is free: `netstat -ano | findstr :80`
3. Restart: `.\httpd.exe -k restart`
4. Open port 80 in the Windows and cloud firewalls.
5. Browse to `http://<public-ip>`

---

# Troubleshooting

| Problem | Fix |
|---|---|
| Browser can't open the site | Apache not running. Run `.\httpd.exe` in the foreground to see the error, or `.\httpd.exe -k start`. |
| "Could not bind to address" | Another program uses the port (often IIS on port 80). Change `Listen` to 8080. |
| `VCRUNTIME140.dll` missing | `choco install vcredist140 -y` |
| Works locally, not from outside | Open the port in Windows Firewall and in the cloud security group. Use the correct port in the URL. |
| Shows "It works!" instead of the template | Old `index.html` remains, or files are in a subfolder. Check `dir` on `htdocs`. |
| 403 Forbidden | Set `Require all granted` in the `<Directory>` block and make sure `index.html` exists. |
| 404 Not Found | Files copied at the wrong folder level. Move them directly into `htdocs`. |
| CSS/images missing | Keep `css`, `js`, `images` folders beside `index.html`. Hard refresh with Ctrl+F5. |
| Restart fails | Run `.\httpd.exe -t` and read `logs\error.log`. |

# Quick reference

```powershell
cd C:\Users\Administrator\AppData\Roaming\Apache24\bin
.\httpd.exe -k start
.\httpd.exe -k stop
.\httpd.exe -k restart
.\httpd.exe -t
type ..\logs\error.log
```
