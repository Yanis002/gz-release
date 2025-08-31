@echo off
setlocal

set GZINJECT=bin\gzinject.exe
bin\gru.exe lua/patch-iso.lua %*
rmdir /s /q isoextract
