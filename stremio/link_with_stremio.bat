@echo off
title Link MPV Flow with Stremio
cd /d "%~dp0"

if exist "..\vs\python.exe" (
    "..\vs\python.exe" stremio_bridge.py
) else if exist "vs\python.exe" (
    "vs\python.exe" stremio_bridge.py
) else (
    python stremio_bridge.py
)

echo.
pause
