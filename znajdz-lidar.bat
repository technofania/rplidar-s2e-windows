@echo off
rem Sama autodetekcja adresu czujnika (zapisuje go dla TouchDesignera).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\find-lidar.ps1"
pause
