@echo off
:: =============================================================================
:: run_test.bat  <test_name>
::
:: Usage:
::   run_test.bat echo
::
:: Convention:
::   Testbench : tb/<test_name>_tb.sv
::   Firmware  : sim/hex/<test_name>.hex
::   Binary    : sim/bin/<test_name>_sim  (deleted after run)
::   Waves     : sim/waves/waves.fst
:: =============================================================================

setlocal

:: --- Argument check ---
if "%~1"=="" (
    echo.
    echo  Usage: run_test.bat ^<test_name^>
    echo  Example: run_test.bat echo
    echo.
    pause
    exit /b 1
)

set TEST=%~1
set TB=tb/%TEST%_tb.sv
set HEX=sim/hex/%TEST%.hex
set BIN=sim/bin/%TEST%_sim
set WAVES=sim/waves/waves.fst

echo.
echo ===========================================
echo   RISC-V SoC  --  Test: %TEST%
echo ===========================================

:: --- Check that testbench exists ---
if not exist "%TB%" (
    echo [ERROR] Testbench not found: %TB%
    pause
    exit /b 1
)

:: --- Check that hex file exists ---
if not exist "%HEX%" (
    echo [ERROR] Hex file not found: %HEX%
    pause
    exit /b 1
)

:: --- Create directories if they don't exist ---
if not exist sim\hex mkdir sim\hex
if not exist sim\bin mkdir sim\bin
if not exist sim\waves mkdir sim\waves

:: --- Clean old outputs ---
if exist "%WAVES%"  del /q "%WAVES%"
if exist "%BIN%"    del /q "%BIN%"

:: --- Compile ---
echo Compiling...
iverilog -g2012 -o %BIN% ^
  %TB% ^
  rtl/soc_top.sv ^
  rtl/core/*.sv ^
  rtl/interconnect/*.sv ^
  rtl/memory/*.sv ^
  rtl/perips/*.sv

if %errorlevel% neq 0 (
    echo [ERROR] Compilation failed.
    pause
    exit /b %errorlevel%
)

:: --- Run ---
echo Running...
vvp %BIN% -fst +HEX_FILE=%HEX%

:: --- Cleanup binary ---
:: If you want to keep the compiled files, put a "::" before the next line
if exist "%BIN%" del /q "%BIN%"

echo.
echo Done.
pause
endlocal