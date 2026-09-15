@echo off
rem ASCII-only launcher: runs the first *.ps1 in this folder that is not a
rem test/scratch file (test_*, pet_*, pt*), then exits.
for %%F in ("%~dp0*.ps1") do (
  echo %%~nF | findstr /i /b "test_ pet_ pt" >nul
  if errorlevel 1 (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%%F"
    goto :done
  )
)
echo [ERROR] No pet script found next to this launcher.
pause
:done
