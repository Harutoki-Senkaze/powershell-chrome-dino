@echo off
rem ============================================================
rem  ChromeDino launcher - double-click to play
rem
rem  Why this file exists:
rem    1) .ps1 files open in Notepad when double-clicked
rem    2) Windows blocks unsigned scripts by default
rem    3) the legacy console needs its code page switched to UTF-8
rem       (ChromeDino.ps1 does that itself)
rem
rem  Optional 1st argument = render mode: braille | block | ascii
rem  Keep this file pure ASCII - non-ASCII breaks cmd parsing.
rem ============================================================
title ChromeDino
setlocal
set "HERE=%~dp0"
if "%HERE:~-1%"=="\" set "HERE=%HERE:~0,-1%"
set "RENDER=%~1"
if "%RENDER%"=="" set "RENDER=auto"

if not exist "%HERE%\ChromeDino.ps1" (
    echo [x] ChromeDino.ps1 not found next to this launcher.
    pause
    exit /b 1
)

rem Prefer Windows Terminal (its default font has braille glyphs).
where wt >nul 2>nul
if %errorlevel%==0 (
    wt nt -d "%HERE%" pwsh -NoExit -NoProfile -ExecutionPolicy Bypass -File "%HERE%\ChromeDino.ps1" -Render %RENDER%
    if not errorlevel 1 exit /b
    echo [i] Windows Terminal launch failed - running in this window instead.
)

where pwsh >nul 2>nul
if %errorlevel%==0 (
    pwsh -NoProfile -ExecutionPolicy Bypass -File "%HERE%\ChromeDino.ps1" -Render %RENDER%
) else (
    echo [i] PowerShell 7 not found, using Windows PowerShell 5.1
    powershell -NoProfile -ExecutionPolicy Bypass -File "%HERE%\ChromeDino.ps1" -Render %RENDER%
)

echo.
echo ==== game exited ====
echo Recommended window: at least 151 columns x 15 rows
pause