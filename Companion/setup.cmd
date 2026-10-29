@echo off
cd /d "%~dp0"
py -3 -m venv .venv
if errorlevel 1 goto fail
.venv\Scripts\python.exe -m pip install -r requirements.txt
if errorlevel 1 goto fail
if not exist config.json copy config.example.json config.json >nul
notepad config.json
echo Save the configuration in Notepad, then close it and continue here.
pause
.venv\Scripts\python.exe monitor.py --setup
pause
exit /b
:fail
echo Setup failed. Install Python 3.11 or newer from python.org, then retry.
pause
