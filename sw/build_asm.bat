@echo off
echo =========================================
echo RISC-V Build Script (Pure Assembly)
echo =========================================

:: אם לא סופק שם של טסט, נשתמש בברירת המחדל
set TEST_FILE=%1
if "%TEST_FILE%"=="" set TEST_FILE= tests\asm_tests\cache_loop.asm

echo [1/3] Assembling and Linking %TEST_FILE%...
:: קימפול קובץ האסמבלי לקובץ אובייקט
riscv-none-elf-as -march=rv32i -mabi=ilp32 -o test.o %TEST_FILE%

:: בדיקה אם הקימפול נכשל
if %ERRORLEVEL% NEQ 0 (
    echo.
    echo [ERROR] Assembly failed! Check your ASM code.
    exit /b %ERRORLEVEL%
)

:: לינקינג ישירות לכתובת אפס, ללא קובץ Linker וללא boot.s
riscv-none-elf-ld -Ttext 0x00000000 -o firmware.elf test.o

echo [2/3] Generating firmware.mem (32-bit aligned)...
riscv-none-elf-objcopy -O verilog --verilog-data-width=4 firmware.elf firmware.mem

echo [3/3] Generating Assembly Disassembly (asm.txt)...
riscv-none-elf-objdump -d firmware.elf > asm.txt

:: מחיקת קובץ האובייקט הזמני שנוצר
del test.o

echo.
echo =========================================
echo SUCCESS! firmware.mem and asm.txt are ready.
echo =========================================