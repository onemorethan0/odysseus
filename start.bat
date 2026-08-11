@echo off
cd /d "%~dp0"
echo Starting Odysseus at http://127.0.0.1:7000 ...
venv\Scripts\python.exe -m uvicorn app:app --host 127.0.0.1 --port 7000
