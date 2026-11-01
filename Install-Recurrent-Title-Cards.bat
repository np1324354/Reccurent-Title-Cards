@echo off
setlocal
title Recurrent Title Cards
set "GAME_ROOT=%~dp0"
set "SCRIPT=%GAME_ROOT%Install-Recurrent-Title-Cards.ps1"

if not exist "%GAME_ROOT%Control_DX12.exe" (
  echo ERROR: Extract this ZIP into the main Control folder beside Control_DX12.exe.
  goto :failed
)
if not exist "%SCRIPT%" (
  echo ERROR: Install-Recurrent-Title-Cards.ps1 was not found.
  goto :failed
)

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%"
set "RESULT=%ERRORLEVEL%"
echo.
if not "%RESULT%"=="0" echo Installation stopped. See the error above.
echo.
pause
exit /b %RESULT%

:failed
echo.
pause
exit /b 1
