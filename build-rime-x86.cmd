@echo off
setlocal
set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
if not exist "%VSWHERE%" (
  echo Visual Studio 2022 C++ Build Tools is required.
  exit /b 1
)
for /f "tokens=*" %%i in ('call "%VSWHERE%" -latest -version "[17.0,18.0)" -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath') do set "VSROOT=%%i"
if not defined VSROOT (
  echo Visual Studio 2022 C++ tools were not found.
  exit /b 1
)
call "%VSROOT%\Common7\Tools\VsDevCmd.bat" -arch=x86 -host_arch=x64
if errorlevel 1 exit /b %errorlevel%
set "PATH=%~dp0.venv\Scripts;%PATH%"
cd /d "%~dp0librime"
set "build_dir=build-x86"
set "deps_install_prefix=%CD%\stage-x86"
set "rime_install_prefix=%CD%\dist-x86"
call build.bat deps librime test
exit /b %errorlevel%





