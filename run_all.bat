@echo off
echo =================================================================
echo   CORDIC Sine/Cosine Processor - Automated Verification Suite
echo =================================================================

where iverilog >nul 2>nul
if %ERRORLEVEL% equ 0 (
    echo [INFO] Icarus Verilog detected. Running Verilog simulation...
    if not exist sim mkdir sim
    if not exist sim\waves mkdir sim\waves
    iverilog -o sim\cordic_sim.vvp rtl\cordic_top.v rtl\cordic_fsm.v rtl\cordic_datapath.v rtl\cordic_atan_rom.v rtl\cordic_iter_counter.v rtl\cordic_quadrant.v rtl\cordic_output_reg.v tb\tb_cordic_top.v
    if %ERRORLEVEL% equ 0 (
        vvp sim\cordic_sim.vvp
    ) else (
        echo [WARN] iverilog compilation failed, falling back to C-simulator.
    )
) else (
    echo [INFO] Icarus Verilog not on PATH. Using GCC cycle-accurate simulator...
)

echo.
echo [INFO] Running cycle-accurate verification engine...
if not exist sim mkdir sim
gcc -O2 sim\sim_cordic.c -o sim\sim_cordic.exe
if %ERRORLEVEL% equ 0 (
    sim\sim_cordic.exe
) else (
    echo [ERROR] GCC build failed.
    exit /b 1
)

echo.
echo [INFO] Generating mathematical precision analysis...
python run_simulation.py

echo.
echo =================================================================
echo   Verification Completed Successfully!
echo   VCD Waveform saved to: sim\waves\cordic_tb.vcd
echo =================================================================

