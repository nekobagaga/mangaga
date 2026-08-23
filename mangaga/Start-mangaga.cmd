@echo off
setlocal

set "ROOT=%~dp0"
set "APP=%ROOT%src\mangaga.ps1"
set "POWERSHELL=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"

if not exist "%APP%" (
  echo Cannot find app script:
  echo %APP%
  echo.
  pause
  exit /b 1
)

"%POWERSHELL%" -NoProfile -ExecutionPolicy Bypass -STA -File "%APP%"
set "EXIT_CODE=%ERRORLEVEL%"

if not "%EXIT_CODE%"=="0" (
  echo.
  echo mangaga exited with code %EXIT_CODE%.
  echo.
  pause
)

exit /b %EXIT_CODE%

