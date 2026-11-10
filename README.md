# 16-Bit CORDIC Trigonometric Processor in Verilog
## Computer Organization and Architecture (COA) Design & Verification

[![Verification](https://img.shields.io/badge/Simulation-87%2F87%20Passed-brightgreen)](file:///c:/Users/HP/Desktop/COA/run_simulation.py)
[![Latency](https://img.shields.io/badge/Latency-18%20Clock%20Cycles-blue)](file:///c:/Users/HP/Desktop/COA/rtl/cordic_top.v)
[![Precision](https://img.shields.io/badge/Error-%E2%89%A41%20LSB%20(Q1.15)-purple)](file:///c:/Users/HP/Desktop/COA/sim/sim_cordic.c)

A complete, multiplier-free, cycle-accurate implementation of the **CORDIC (COordinate Rotation DIgital Computer)** algorithm in synthesizable Verilog HDL. The core computes both $\sin(\theta)$ and $\cos(\theta)$ over the full $[-\pi, +\pi]$ circular domain using only arithmetic shifts, additions, and subtractions.

---

## 1. System Specifications

| Parameter | Value | Description |
|---|---|---|
| **Target Function** | $\sin(\theta), \cos(\theta)$ | Simultaneous vector rotation mode |
| **Input Angle Format** | Signed `Q3.13` (16-bit) | Full $[-\pi, +\pi]$ range ($-4.0$ to $+4.0$ rad) |
| **Output Data Format** | Signed `Q1.15` (16-bit) | Domain $[-1.0, +1.0)$ with saturation |
| **Internal Precision** | Signed `Q3.19` / `Q4.18` (22-bit) | 2 MSB integer guard bits, 4 LSB fractional guard bits |
| **Iterations** | 16 micro-rotations | Shifts from $i = 0$ to $15$ |
| **Execution Latency** | **18 clock cycles** | Exact deterministic latency from accepted `start` |
| **Target Clock** | 50 MHz ($T = 20\text{ ns}$) | Single synchronous clock domain |
| **Maximum Error** | $\le 1\text{ LSB}$ ($\approx 3.05 \times 10^{-5}$) | Well within design margin ($\le 4\text{ LSB}$) |
| **Hardware Resources** | Multiplier-free | 0 DSP blocks, shift-add datapath only |

---

## 2. Architecture & Module Hierarchy

```
cordic_top (Top-Level Structural System)
│
├── cordic_quadrant     (Combinational full-circle [-pi, +pi] fold into [0, +pi/2])
├── cordic_fsm          (4-State Moore Controller: IDLE -> LOAD -> ITERATE -> DONE)
├── cordic_iter_counter (Synchronous 4-bit iteration counter, asserts iter_done at 15)
├── cordic_atan_rom     (Combinational 16-word Q0.18 arctangent lookup table)
├── cordic_datapath     (22-bit shift-and-add arithmetic core with pre-scaled X0)
└── cordic_output_reg   (Rounding bias, quadrant sign reconstruction, saturation, holding reg)
```

---

## 3. Directory Layout

```
COA/
├── rtl/                        # Synthesizable Verilog RTL source files
│   ├── cordic_top.v            # Top-level integration core
│   ├── cordic_fsm.v            # 4-state control finite state machine
│   ├── cordic_datapath.v       # 22-bit arithmetic datapath
│   ├── cordic_atan_rom.v       # 16-entry arctangent ROM
│   ├── cordic_iter_counter.v   # Synchronous 4-bit iteration counter
│   ├── cordic_quadrant.v       # Angle folding and quadrant detector
│   └── cordic_output_reg.v     # Output rounding, sign correction, saturation
│
├── tb/                         # Verilog testbenches (unit and integration)
│   ├── tb_cordic_top.v         # Full integration testbench (26 test cases)
│   ├── tb_cordic_datapath.v    # Datapath unit verification
│   ├── tb_cordic_fsm.v         # FSM transition and output validation
│   ├── tb_cordic_atan_rom.v    # ROM table verification
│   ├── tb_cordic_iter_counter.v# Counter step and reset validation
│   ├── tb_cordic_quadrant.v    # Quadrant folding verification
│   └── tb_cordic_output_reg.v  # Output rounding, clamping, and holding testbench
│
├── sim/                        # Simulation and verification environment
│   ├── sim_cordic.c            # Cycle-accurate C simulation engine
│   ├── sim_cordic.exe          # Compiled binary simulator
│   └── waves/                  # GTKWave VCD waveform files
│       └── cordic_tb.vcd       # 54 KB full simulation waveform dump
│
├── docs/docs/                  # Comprehensive engineering design documentation
│   ├── phase1_mathematical_foundation.md
│   ├── phase2_hardware_architecture.md
│   ├── phase3_implementation_strategy.md
│   ├── phase4_numerical_validation.md
│   ├── phase5_verilog_blueprint.md
│   ├── phase6_verification_strategy.md
│   ├── phase7_coa_concepts_viva.md
│   └── phase8_demonstration_plan.md
│
├── run_simulation.py           # Automated test harness & precision validator
├── run_all.bat                 # One-click execution batch script
└── README.md                   # Project documentation & summary
```

---

## 4. How to Run the Tests

### Method A: Automated Python Harness (Recommended)
Runs all unit and integration testbenches and outputs a comparative floating-point error table:
```powershell
python run_simulation.py
```

### Method B: One-Click Batch Script
```cmd
run_all.bat
```

### Method C: Running via Icarus Verilog
If `iverilog` is installed:
```powershell
iverilog -o sim/cordic_sim.vvp rtl/*.v tb/tb_cordic_top.v
vvp sim/cordic_sim.vvp
```

---

## 5. Viewing Simulation Waveforms

The test harness produces a GTKWave-compatible Value Change Dump (`.vcd`) file:
- Location: `sim/waves/cordic_tb.vcd` (also mirrored at `cordic_tb.vcd`)

To open in GTKWave:
```powershell
gtkwave sim\waves\cordic_tb.vcd
```

### Key Waveform Signals to Inspect:
1. `clk`, `rst`, `start`, `done`: Control handshake and deterministic 18-cycle latency.
2. `fsm_state[1:0]`: `00` (IDLE) $\to$ `01` (LOAD) $\to$ `10` (ITERATE) $\to$ `11` (DONE).
3. `count[3:0]`: Advances from 0 to 15 during the `ITERATE` state.
4. `z_reg[21:0]`: Observes convergence towards zero as micro-rotations proceed.
5. `cosine_out[15:0]`, `sine_out[15:0]`: Latch final valid results when `done` asserts.

---

## 6. Verification Summary Table

| Test Case | Angle | Expected Cos | Expected Sin | Hardware Cos | Hardware Sin | Latency | Status |
|---|---|---|---|---|---|---|---|
| **T01** | $0^\circ$ | `0x7FFF` | `0x0000` | `0x7FFF` | `0x0000` | 18 cycles | **PASS** |
| **T02** | $15^\circ$ | `0x7BA3` | `0x2121` | `0x7BA3` | `0x2121` | 18 cycles | **PASS** |
| **T03** | $30^\circ$ | `0x6EDA` | `0x4000` | `0x6EDB` | `0x3FFF` | 18 cycles | **PASS** |
| **T04** | $45^\circ$ | `0x5A82` | `0x5A82` | `0x5A82` | `0x5A83` | 18 cycles | **PASS** |
| **T05** | $60^\circ$ | `0x4000` | `0x6EDA` | `0x3FFF` | `0x6EDB` | 18 cycles | **PASS** |
| **T06** | $75^\circ$ | `0x2121` | `0x7BA3` | `0x2121` | `0x7BA3` | 18 cycles | **PASS** |
| **T07** | $90^\circ$ | `0x0000` | `0x7FFF` | `0x0000` | `0x7FFF` | 18 cycles | **PASS** |
| **T08** | $120^\circ$ | `0xC000` | `0x6EDA` | `0xC001` | `0x6EDB` | 18 cycles | **PASS** |
| **T09** | $135^\circ$ | `0xA57E` | `0x5A82` | `0xA57E` | `0x5A83` | 18 cycles | **PASS** |
| **T10** | $150^\circ$ | `0x9126` | `0x4000` | `0x9125` | `0x3FFF` | 18 cycles | **PASS** |
| **T11** | $180^\circ$ | `0x8000` | `0x0000` | `0x8000` | `0x0000` | 18 cycles | **PASS** |
| **T12–T17** | Quadrant 4 | Negative angles | Verified | Measured | Measured | 18 cycles | **PASS** |
| **T18–T21** | Quadrant 3 | Large negative | Verified | Measured | Measured | 18 cycles | **PASS** |
| **T22–T23** | Back-to-Back | Zero-gap pulse | Verified | Measured | Measured | 18 cycles | **PASS** |
| **T24** | Busy-Immune | Mid-run pulse | Ignored | Measured | Measured | — | **PASS** |
| **T25** | Reset Recovery| Mid-run abort | Clean reset | Measured | Measured | 18 cycles | **PASS** |

**Result: 87/87 Total Assertions Passed (100% Success Rate)**

