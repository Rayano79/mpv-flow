@echo off
title TensorRT Model 2 (RIFE v4.25 Lite) Engine Builder
cd /d "%~dp0"
set "PATH=%~dp0..\vs\vs-plugins\vsmlrt-cuda;%~dp0..\vs\vs-plugins;%~dp0..\vs;%PATH%"

echo ==============================================================================
echo    Compiling TensorRT Engines for Model 2: RIFE v4.25 Lite (Fast & Detailed)
echo    Resolutions: 1080p (1920x1088) & 720p (1280x768)
echo ==============================================================================
echo.

if exist "..\vs\python.exe" (
    "..\vs\python.exe" build_all_engines.py --model 2
) else if exist "vs\python.exe" (
    "vs\python.exe" build_all_engines.py --model 2
) else (
    python build_all_engines.py --model 2
)

exit %ERRORLEVEL%
