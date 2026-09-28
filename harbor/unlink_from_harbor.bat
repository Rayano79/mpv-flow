@echo off
title Unlink MPV Flow from Harbor
cd /d "%~dp0"

if exist "..\vs\python.exe" (
    "..\vs\python.exe" harbor_bridge.py unlink
) else if exist "vs\python.exe" (
    "vs\python.exe" harbor_bridge.py unlink
) else (
    python harbor_bridge.py unlink
)

echo.
pause
