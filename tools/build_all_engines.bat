@echo off
title TensorRT RIFE Engine Pre-Compiler (All Models)
cd /d "%~dp0"
set "PATH=%~dp0..\vs\vs-plugins\vsmlrt-cuda;%~dp0..\vs\vs-plugins;%~dp0..\vs;%PATH%"

echo ==============================================================================
echo    Starting TensorRT RIFE Engine Pre-Compiler (All 4 Default Models)
echo ==============================================================================
echo.

if exist "..\vs\python.exe" (
    "..\vs\python.exe" build_all_engines.py
) else if exist "vs\python.exe" (
    "vs\python.exe" build_all_engines.py
) else (
    python build_all_engines.py
)

echo.
echo ==============================================================================
echo    Pre-compilation process finished! Press any key to exit.
echo ==============================================================================
pause >nul
