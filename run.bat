@echo off
echo ===========================================
echo    RISC-V SoC Hierarchy Simulation (FST)
echo ===========================================

:: 1. Create sim directory
if not exist sim mkdir sim

:: 2. Clean old files
echo Cleaning old simulation files...
if exist sim\waves.fst del /q sim\waves.fst
if exist sim\riscv_sim del /q sim\riscv_sim
if exist sim\soc.stems del /q sim\soc.stems

:: 3. Compilation (Including all SoC directories and Monitors)
echo Compiling SoC and Testbench...
iverilog -g2012 -o sim/soc_sim ^
tb/soc_tb.sv ^
tb/monitors/*.sv ^
rtl/soc_top.sv ^
rtl/core/*.sv ^
rtl/interconnect/*.sv ^
rtl/memory/*.sv ^
rtl/perips/*.sv

if %errorlevel% neq 0 (
    echo [ERROR] Compilation failed!
    pause
    exit /b %errorlevel%
)

:: 4. Generate RTL Stems (Hierarchy Map)
echo Generating SoC Hierarchy Map...
iverilog -g2012 -t null -o sim/soc.stems ^
tb/soc_tb.sv ^
tb/monitors/*.sv ^
rtl/soc_top.sv ^
rtl/core/*.sv ^
rtl/interconnect/*.sv ^
rtl/memory/*.sv ^
rtl/perips/*.sv

:: 5. Run the simulation
echo Running SoC simulation...
vvp sim/soc_sim -fst

:: 6. Open GTKWave
echo Opening GTKWave with SoC Hierarchy...
start "" "C:\GTKWave\gtkwave64\bin\gtkwave.exe" -t sim/soc.stems sim/waves.fst

echo Done! SoC is ready for debugging.
pause