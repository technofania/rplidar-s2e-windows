@echo off
rem Diagnostyka czujnika: siec, ping, model, tryby, 4 s odbioru danych.
rem UDP nie jest na wylacznosc, ale czujnik wysyla strumien temu, kto ostatni poprosil -
rem odznacz Active na komponencie albo zamknij TouchDesignera, zeby pomiar byl uczciwy.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\test-lidar.ps1"
