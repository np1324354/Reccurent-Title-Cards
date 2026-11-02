@echo off
setlocal
 title Recurrent Title Cards v1.0b Installer
for %%I in ("%~dp0.") do set "GAME_ROOT=%%~fI"
set "SCRIPT=%~dp0Install-Recurrent-Title-Cards-v1.0b.ps1"
set "RESULT=1"

if not exist "%SCRIPT%" (
  echo ERROR: Installer script not found. Extract the entire ZIP.
  goto :finish
)
if not exist "%GAME_ROOT%\Control_DX12.exe" if not exist "%GAME_ROOT%\Control.exe" (
  echo ERROR: Extract this ZIP directly into the folder containing Control_DX12.exe.
  goto :finish
)

echo Recurrent Title Cards v1.0b - standalone alternative
echo ---------------------------------------------------
echo Builds v1.0b from the verified game HUD, or converts the exact v1.0 loose HUD.
echo It checks the source and final hashes and backs up any existing loose HUD outside data\.
echo.
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -GamePath "%GAME_ROOT%"
set "RESULT=%ERRORLEVEL%"

:finish
echo.
if not "%RESULT%"=="0" echo Installation did not complete. Review the error above.
pause
exit /b %RESULT%
