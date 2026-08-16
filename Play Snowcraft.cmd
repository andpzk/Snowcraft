@echo off
setlocal

set "SNOWCRAFT_EXE=%~dp0EXE\Snowcraft.exe"

if not exist "%SNOWCRAFT_EXE%" (
    echo Snowcraft.exe was not found in the EXE folder.
    echo Please keep this launcher in the game folder.
    pause
    exit /b 1
)

start "" /D "%~dp0EXE" "%SNOWCRAFT_EXE%"

