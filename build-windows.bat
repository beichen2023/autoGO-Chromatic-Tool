@echo off
setlocal

cd /d "%~dp0"

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0build-windows.ps1" %*
if errorlevel 1 (
    echo.
    echo Windows EXE build failed. Please check the error above.
    exit /b 1
)

echo.
echo Windows EXE build completed.
