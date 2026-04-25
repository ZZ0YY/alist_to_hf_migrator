@echo off
setlocal enabledelayedexpansion

:: ============================================================================
:: Alist-To-HF Migrator - Windows Build Script
:: Builds the Flutter Windows app and packages it as a zip in dist/
:: ============================================================================

echo ============================================
echo   Alist-To-HF Migrator - Windows Build
echo ============================================
echo.

:: Read version from pubspec.yaml
for /f "tokens=2 delims=:" %%a in ('findstr "version:" pubspec.yaml ^| findstr /v "sdk"') do (
    set VERSION=%%a
    set VERSION=!VERSION: =!
    set VERSION=!VERSION:+=!
    goto :found_version
)
:found_version

if "%VERSION%"=="" (
    echo [ERROR] Could not extract version from pubspec.yaml
    exit /b 1
)

echo [INFO] Version: %VERSION%
echo.

:: Create dist directory
if not exist dist mkdir dist

:: Step 1: Get dependencies
echo [1/3] Running flutter pub get...
call flutter pub get
if %errorlevel% neq 0 (
    echo [ERROR] flutter pub get failed
    exit /b 1
)
echo [OK] Dependencies resolved
echo.

:: Step 2: Build
echo [2/3] Building Windows release...
call flutter build windows --release
if %errorlevel% neq 0 (
    echo [ERROR] flutter build windows failed
    exit /b 1
)
echo [OK] Build completed
echo.

:: Step 3: Package
echo [3/3] Packaging release zip...
set ZIP_NAME=alist-to-hf-migrator-%VERSION%-windows-x64.zip
set RELEASE_DIR=build\windows\x64\runner\Release

if not exist "%RELEASE_DIR%" (
    echo [ERROR] Release directory not found: %RELEASE_DIR%
    exit /b 1
)

:: Use PowerShell to create the zip
powershell -NoProfile -Command "Compress-Archive -Path '%RELEASE_DIR%\*' -DestinationPath 'dist\%ZIP_NAME%' -Force"
if %errorlevel% neq 0 (
    echo [ERROR] Failed to create zip archive
    exit /b 1
)

echo [OK] Package created: dist\%ZIP_NAME%
echo.

:: Summary
echo ============================================
echo   Build Successful!
echo ============================================
echo   Output: dist\%ZIP_NAME%
echo ============================================

endlocal
