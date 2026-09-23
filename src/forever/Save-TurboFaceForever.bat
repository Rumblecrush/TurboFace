@echo off
setlocal
title Save TurboFace Forever Settings
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Tools\Save-ForeverVariables.ps1"
set "TF_EXIT=%ERRORLEVEL%"
echo.
if not "%TF_EXIT%"=="0" echo TurboFace settings were not updated.
pause
exit /b %TF_EXIT%
