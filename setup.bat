@echo off
title mpv flow Setup
cd /d "%~dp0"

echo ==============================================================================
echo    MPV Flow + VapourSynth RIFE TensorRT Automated Setup
echo ==============================================================================
echo.

if exist "vs\python.exe" (
    "vs\python.exe" setup.py
) else if exist "python.exe" (
    "python.exe" setup.py
) else (
    python setup.py
)

if %ERRORLEVEL% neq 0 (
    echo.
    echo [ERROR] Setup encountered an issue. Please review the messages above.
    pause
    exit /b %ERRORLEVEL%
)

pause
