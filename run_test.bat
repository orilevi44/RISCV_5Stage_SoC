@echo off
:: =============================================================================
:: run_test.bat  <test_name>
::
:: Usage:
::   run_test.bat echo          → compiles tb/echo_test_tb.sv, loads sim/hex/echo.hex
::   run_test.bat alu_add       → compiles tb/alu_add_tb.sv,   loads sim/hex/alu_add.hex
::   run_test.bat branch        → compiles tb/branch_tb.sv,    loads sim/hex/branch.hex
::
:: Convention:
::   Testbench : tb/<test_name>_tb.sv
::   Firmware  : sim/hex/<test_name>.hex
::   Binary    : sim/<test_name>_sim  (deleted after run)
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
set BIN=sim/%TEST%_sim

echo.
echo ===========================================
echo   RISC-V SoC  --  Test: %TEST%
echo ===========================================

:: --- Check that testbench exists ---
if not exist %TB% (
    echo [ERROR] Testbench not found: %TB%
    pause
    exit /b 1
)

:: --- Check that hex file exists ---
if not exist %HEX% (
    echo [ERROR] Hex file not found: %HEX%
    pause
    exit /b 1
)

:: --- Clean old outputs ---
if not exist sim     mkdir sim
if not exist sim\hex mkdir sim\hex
if exist sim\waves.fst  del /q sim\waves.fst
if exist %BIN%          del /q %BIN%

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
if exist "%BIN%" del /q "%BIN%"

echo.
echo Done.
pause
endlocal
