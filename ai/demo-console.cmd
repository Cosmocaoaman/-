@echo off
setlocal
cd /d "%~dp0rime-data"
echo Local AI protocol demo. Start start-mock.ps1 in another terminal first.
echo Type each line then Enter: nihao / {Control+Tab} / wait / {Control+Tab} / {Tab}
echo Type exit to close. MOCK output is not an AI prediction.
"%~dp0..\librime\build-x64\bin\rime_api_console.exe"
