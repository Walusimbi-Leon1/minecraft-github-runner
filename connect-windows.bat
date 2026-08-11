@echo off
REM connect-windows.bat <trycloudflare-URL>  — open the tunnel to your Colab Minecraft server
REM Usage:   connect-windows.bat https://xxxx.trycloudflare.com
REM Then in Minecraft: Multiplayer -> Add Server -> address:  localhost:25565
REM Keep this window open while you play.

if "%1"=="" (
  echo Usage: connect-windows.bat https://xxxx.trycloudflare.com
  exit /b 1
)

set "URL=%1"
set "CF=%USERPROFILE%\.cloudflared\cloudflared.exe"

if not exist "%CF%" (
  echo Downloading cloudflared...
  powershell -NoProfile -Command "New-Item -ItemType Directory -Force -Path \"$env:USERPROFILE\.cloudflared\" | Out-Null; Invoke-WebRequest -Uri 'https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe' -OutFile \"$env:USERPROFILE\.cloudflared\cloudflared.exe\""
)

echo Keep this window open. In Minecraft, add server:  localhost:25565
"%CF%" access tcp --hostname %URL% --url 127.0.0.1:25565
pause
