@echo off
title Link MPV Flow with Harbor
cd /d "%~dp0"

if exist "..\vs\python.exe" (
    "..\vs\python.exe" harbor_bridge.py
) else if exist "vs\python.exe" (
    "vs\python.exe" harbor_bridge.py
) else (
    python harbor_bridge.py
)

echo.
pause
