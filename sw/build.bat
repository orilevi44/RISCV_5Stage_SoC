@echo off
echo =========================================
echo RISC-V Build Script (Windows)
echo =========================================

:: אם לא סופק שם של טסט, נשתמש בברירת המחדל
set TEST_FILE=%1
if "%TEST_FILE%"=="" set TEST_FILE=test/add_test.c

echo [1/3] Compiling %TEST_FILE% and boot.s...
riscv-none-elf-gcc -march=rv32i -mabi=ilp32 -nostdlib -T link.ld boot.s %TEST_FILE% -o firmware.elf

:: בדיקה אם הקימפול נכשל
if %ERRORLEVEL% NEQ 0 (
    echo.
    echo [ERROR] Compilation failed! Check your C code.
    exit /b %ERRORLEVEL%
)

echo [2/3] Generating firmware.mem (32-bit aligned)...
riscv-none-elf-objcopy -O verilog --verilog-data-width=4 firmware.elf firmware.mem

echo [3/3] Generating Assembly Disassembly (asm.txt)...
riscv-none-elf-objdump -d firmware.elf > asm.txt

echo.
echo =========================================
echo SUCCESS! firmware.mem and asm.txt are ready.
echo =========================================