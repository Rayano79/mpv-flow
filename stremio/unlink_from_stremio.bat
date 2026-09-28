@echo off
title Unlink MPV Flow from Stremio
cd /d "%~dp0"

if exist "..\vs\python.exe" (
    "..\vs\python.exe" stremio_bridge.py unlink
) else if exist "vs\python.exe" (
    "vs\python.exe" stremio_bridge.py unlink
) else (
    python stremio_bridge.py unlink
)

echo.
pause
