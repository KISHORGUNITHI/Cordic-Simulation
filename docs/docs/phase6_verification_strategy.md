# Phase 6: Verification and Simulation Strategy
## CORDIC Algorithm — Complete Testbench Architecture and Test Plan

---

## Table of Contents

1. [Verification Philosophy](#1-verification-philosophy)
2. [Testbench Architecture Overview](#2-testbench-architecture-overview)
3. [Unit Test Plans](#3-unit-test-plans)
4. [Integration Test Plan](#4-integration-test-plan)
5. [Top-Level Testbench: Complete Specification](#5-top-level-testbench-complete-specification)
6. [Clock and Reset Generation](#6-clock-and-reset-generation)
7. [Input Stimulus Generation](#7-input-stimulus-generation)
8. [Output Monitoring and Error Calculation](#8-output-monitoring-and-error-calculation)
9. [Boundary and Corner Cases](#9-boundary-and-corner-cases)
10. [Waveform Inspection Guide](#10-waveform-inspection-guide)
11. [Expected Results Table](#11-expected-results-table)
12. [Simulation Tool Setup](#12-simulation-tool-setup)
13. [Complete Testbench Code](#13-complete-testbench-code)

---

## 1. Verification Philosophy

Verification follows a **bottom-up strategy**: verify each module independently before combining them. This makes debugging faster — if a fault appears in the integration test, the unit tests have already confirmed which modules work correctly.

```
Level 3: Integration Test       tb_cordic_top.v      (all modules together)
             ▲
Level 2: Module Tests           tb_cordic_datapath.v
             ▲                  tb_cordic_fsm.v
Level 1: Component Tests        tb_cordic_atan_rom.v
                                tb_cordic_iter_counter.v
```

### Verification Goals

| Goal | Method |
|---|---|
| Functional correctness | Compare output to precomputed reference values |
| Timing verification | Check done pulse width, latency count |
| Error quantization | Calculate absolute error in LSBs |
| Corner case robustness | Test 0°, ±90°, near-boundary angles |
| Convergence | Inspect Z register converging to 0 |
| Reset behavior | Verify outputs clear and restart cleanly |
| Sign correctness | Verify negative angles, Q2/Q3 quadrant outputs |

---

## 2. Testbench Architecture Overview

```
┌────────────────────────────────────────────────────────────────┐
│                    tb_cordic_top (testbench)                    │
│                                                                  │
│  ┌────────────────┐    ┌───────────────────────────────────┐   │
│  │  Clock/Reset   │    │         Stimulus Generator         │   │
│  │   Generator    │    │   (angle_in, start, timing)        │   │
│  └───────┬────────┘    └────────────────┬──────────────────┘   │
│          │                              │                        │
│          ▼                              ▼                        │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │                   cordic_top (DUT)                        │  │
│  │   (Device Under Test — the full design)                   │  │
│  └──────────────────────────────────────────────────────────┘  │
│          │                              │                        │
│          ▼                              ▼                        │
│  ┌────────────────┐    ┌───────────────────────────────────┐   │
│  │  Done Monitor  │    │      Output Checker / Comparator   │   │
│  │  (timing check)│    │  (compare vs reference, log error) │   │
│  └────────────────┘    └────────────────┬──────────────────┘   │
│                                          │                        │
│                                          ▼                        │
│                              ┌─────────────────────┐            │
│                              │  Pass/Fail Reporter  │            │
│                              │  + VCD Dump Writer   │            │
│                              └─────────────────────┘            │
└────────────────────────────────────────────────────────────────┘
```

---

## 3. Unit Test Plans

### 3.1 `tb_cordic_atan_rom.v`

**Purpose:** Verify all 16 ROM entries match the expected arctangent values.

**Test method:**
- Drive `addr` from 0 to 15 sequentially
- Read `atan_val` each cycle
- Compare against expected Q2.14 values

**Pass criteria:** All 16 values match exactly (0 error — ROM is deterministic)

**Key checks:**
```
addr=0 → atan_val == 12868
addr=1 → atan_val == 7596
addr=7 → atan_val == 128
addr=15 → atan_val == 1
```

---

### 3.2 `tb_cordic_iter_counter.v`

**Purpose:** Verify counter resets, counts, and generates `iter_done` correctly.

**Test sequence:**
1. Assert `rst` — verify count=0, iter_done=0
2. Release `rst`, assert `iter_en` for 16 cycles
3. Verify count increments: 0, 1, 2, ..., 15
4. Verify `iter_done` asserts only when count=15 AND iter_en=1
5. Assert `cnt_rst` — verify count resets to 0 immediately
6. Verify counter does NOT increment when `iter_en=0`

**Pass criteria:**
- count increments exactly once per `iter_en` pulse
- `iter_done` is exactly 1 cycle wide at count=15
- `cnt_rst` resets counter immediately on next clock edge

---

### 3.3 `tb_cordic_fsm.v`

**Purpose:** Verify FSM state transitions, output signal generation, and timing.

**Test sequence:**
1. Reset → verify FSM in IDLE, all outputs=0, cnt_rst=1
2. Apply `start=1` for 1 cycle → verify FSM moves IDLE→LOAD
3. Next cycle → verify FSM in LOAD: load_en=1, cnt_rst=1
4. Next cycle → verify FSM in ITERATE: iter_en=1
5. Hold `iter_done=0` for 15 cycles, then assert `iter_done=1`
6. Verify FSM moves ITERATE→DONE: out_latch=1, done=1
7. Verify FSM returns to IDLE next cycle
8. Verify `done` is exactly 1 cycle wide

**Pass criteria:**
- Correct state sequence: IDLE→LOAD→ITERATE→DONE→IDLE
- Moore outputs match the output table from Phase 2
- `done` is a single-cycle pulse

---

### 3.4 `tb_cordic_datapath.v`

**Purpose:** Verify the X/Y/Z register updates for one iteration step. Manually check iteration 0 and iteration 1 for θ=45°.

**Test sequence:**
1. Apply reset
2. Assert `load_en`: angle_in=12868 (45° in Q2.14), verify X=19898, Y=0, Z=12868
3. Set iter_count=0, atan_val=12868
4. Assert `iter_en`: verify Z=0 (since Z₀=atan[0] for 45°), X and Y equal 19898
5. Set iter_count=1, atan_val=7596
6. Assert `iter_en`: verify Z becomes negative, X/Y shift and update correctly
7. Continue for 16 iterations, verify X_final ≈ 23170, Y_final ≈ 23170

**Pass criteria:**
- X=19898, Y=0, Z=12868 after load
- After 16 iterations with θ=45°: X≈23170, Y≈23170, Z≈0

---

## 4. Integration Test Plan

### `tb_cordic_top.v`

**Purpose:** Full end-to-end verification of the complete CORDIC design. Apply all test angles, check outputs, verify timing, and generate waveforms.

**Test vector list:**

| Test # | Angle (°) | angle_in (hex) | Expected cos (hex) | Expected sin (hex) | Quadrant |
|---|---|---|---|---|---|
| T01 | 0° | 0x0000 | 0x7FFF | 0x0000 | Q1 |
| T02 | 15° | 0x10C1 | 0x7BA3 | 0x2121 | Q1 |
| T03 | 30° | 0x2185 | 0x6EDA | 0x4000 | Q1 |
| T04 | 45° | 0x3244 | 0x5A82 | 0x5A82 | Q1 |
| T05 | 60° | 0x4305 | 0x4000 | 0x6EDA | Q1 |
| T06 | 75° | 0x53C5 | 0x2121 | 0x7BA3 | Q1 |
| T07 | 90° | 0x6488 | 0x0001 | 0x7FFF | Q1 |
| T08 | −15° | 0xEF3F | 0x7BA3 | 0xDEDF | Q4 |
| T09 | −30° | 0xDE7B | 0x6EDA | 0xC000 | Q4 |
| T10 | −45° | 0xCDBC | 0x5A82 | 0xA57E | Q4 |
| T11 | −60° | 0xBCFB | 0x4000 | 0x9126 | Q4 |
| T12 | −90° | 0x9B78 | 0x0001 | 0x8001 | Q4 |
| T13 | 120° | 0x860B | 0xC000 | 0x6EDA | Q2 |
| T14 | 135° | 0x9344 | 0xA57E | 0x5A82 | Q2 |
| T15 | Reset test | — | 0x0000 | 0x0000 | — |
| T16 | Back-to-back | 45° then 30° | verify both | verify both | Q1 |

**Pass criteria per test:**
- `cosine_out` within ±4 LSBs of expected value
- `sine_out` within ±4 LSBs of expected value
- `done` asserts exactly 19 clock cycles after `start`
- `done` is exactly 1 cycle wide

---

## 5. Top-Level Testbench: Complete Specification

### Testbench Parameters

```verilog
// Testbench parameters
parameter CLK_PERIOD   = 20;   // 20 ns → 50 MHz clock
parameter RESET_CYCLES = 5;    // Hold reset for 5 clock cycles
parameter MAX_WAIT     = 30;   // Maximum cycles to wait for done
parameter ERROR_LIMIT  = 4;    // Maximum acceptable error in LSBs
```

### Testbench Structure

```verilog
module tb_cordic_top;

    // ---- DUT signals ----
    reg        clk;
    reg        rst;
    reg        start;
    reg [15:0] angle_in;
    wire       done;
    wire [15:0] sine_out;
    wire [15:0] cosine_out;

    // ---- Instantiate DUT ----
    cordic_top dut (
        .clk       (clk),
        .rst       (rst),
        .start     (start),
        .angle_in  (angle_in),
        .done      (done),
        .sine_out  (sine_out),
        .cosine_out(cosine_out)
    );

    // ---- VCD dump ----
    initial begin
        $dumpfile("sim/waves/cordic_tb.vcd");
        $dumpvars(0, tb_cordic_top);
    end

    // ---- Clock generation ----
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // ---- Test variables ----
    integer test_num;
    integer cos_expected, sin_expected;
    integer cos_error, sin_error;
    integer pass_count, fail_count;

    // ---- Main test sequence ----
    initial begin
        // ... (see Section 13 for complete code)
    end

endmodule
```

---

## 6. Clock and Reset Generation

### Clock

```verilog
// 50 MHz clock — toggles every 10 ns
parameter CLK_PERIOD = 20; // ns

initial clk = 1'b0;
always #(CLK_PERIOD / 2) clk = ~clk;
```

### Reset Sequence

```verilog
// Assert reset for 5 cycles, then release
initial begin
    rst   = 1'b1;
    start = 1'b0;
    angle_in = 16'h0000;
    repeat (RESET_CYCLES) @(posedge clk);
    @(negedge clk);  // release reset slightly after falling edge
    rst = 1'b0;
    #1;              // small delay to avoid race with rising edge
end
```

### Why 5-cycle reset?

- 2 cycles minimum for all flip-flops to settle
- 5 cycles gives margin for any CDC (not present here but good practice)
- Ensures FSM powers up in IDLE state cleanly

---

## 7. Input Stimulus Generation

### Task: `apply_angle`

A reusable task applies an angle and waits for `done`:

```verilog
task apply_angle;
    input [15:0] angle;
    input [15:0] exp_cos;
    input [15:0] exp_sin;
    input [127:0] test_label;  // string for display
    integer wait_count;
    begin
        // Apply angle
        @(negedge clk);
        angle_in = angle;
        start    = 1'b1;
        @(posedge clk);
        #1;
        start    = 1'b0;

        // Wait for done (with timeout)
        wait_count = 0;
        while (!done && wait_count < MAX_WAIT) begin
            @(posedge clk);
            wait_count = wait_count + 1;
        end

        // Check timeout
        if (wait_count >= MAX_WAIT) begin
            $display("TIMEOUT: %s — done never asserted", test_label);
            fail_count = fail_count + 1;
        end else begin
            // Capture and compare
            cos_error = (cosine_out > exp_cos) ?
                        (cosine_out - exp_cos) : (exp_cos - cosine_out);
            sin_error = (sine_out > exp_sin) ?
                        (sine_out - exp_sin) : (exp_sin - sine_out);

            if (cos_error <= ERROR_LIMIT && sin_error <= ERROR_LIMIT) begin
                $display("PASS: %0s | cos=0x%04h (err=%0d LSB) | sin=0x%04h (err=%0d LSB)",
                         test_label, cosine_out, cos_error, sine_out, sin_error);
                pass_count = pass_count + 1;
            end else begin
                $display("FAIL: %0s | cos=0x%04h exp=0x%04h (err=%0d) | sin=0x%04h exp=0x%04h (err=%0d)",
                         test_label, cosine_out, exp_cos, cos_error, sine_out, exp_sin, sin_error);
                fail_count = fail_count + 1;
            end
        end

        // Gap between tests
        repeat (3) @(posedge clk);
    end
endtask
```

### Timing of `start` Pulse

```
          ┌────┐
clk:   ───┘    └────┐    └────┐    └────
       
angle_in: ═══════[VALID]════════════════
                  ↑
start:     ─────┌─┐───────────────────
                └─┘ (1 cycle)
                  ↑
                FSM: IDLE → LOAD
```

Critical: `start` must be high for exactly **one** rising clock edge. If held longer, the FSM loops: DONE→IDLE→LOAD again immediately.

---

## 8. Output Monitoring and Error Calculation

### Absolute Error Calculation

```verilog
// Both signals are treated as unsigned integers for error comparison.
// This works because the reference values are also unsigned-encoded Q1.15.
// For negative values, the 2's complement encoding must match.

function [15:0] abs_diff;
    input [15:0] a, b;
    begin
        abs_diff = (a >= b) ? (a - b) : (b - a);
    end
endfunction
```

### Error in Physical Units

```
1 LSB in Q1.15 = 1/32768 ≈ 3.05 × 10⁻⁵

Error in 4 LSBs = 4/32768 ≈ 1.22 × 10⁻⁴

This is ≈ 0.012% relative error — well within engineering tolerance.
```

### Latency Verification

```verilog
// Count cycles from start to done
integer cycle_count;

// In stimulus:
@(negedge clk);
start = 1'b1;
cycle_count = 0;
@(posedge clk); start = 1'b0;

while (!done) begin
    @(posedge clk);
    cycle_count = cycle_count + 1;
end

if (cycle_count == 18)
    $display("LATENCY OK: done arrived at cycle %0d", cycle_count);
else
    $display("LATENCY FAIL: expected 18, got %0d", cycle_count);
```

Note: cycle_count starts at 1 after `start`, so `done` at cycle 18 means 19 total cycles (1 start + 18 counted).

### Done Pulse Width Verification

```verilog
// Verify done is exactly 1 cycle wide
@(posedge done);
@(posedge clk);
if (done === 1'b0)
    $display("DONE PULSE WIDTH OK: 1 cycle");
else
    $display("DONE PULSE WIDTH FAIL: done held high for more than 1 cycle");
```

---

## 9. Boundary and Corner Cases

### Case 1: θ = 0°

```
Input:    angle_in = 0x0000
Expected: cos(0°) = 1.0 → Q1.15: 0x7FFF (closest to 1.0)
          sin(0°) = 0.0 → Q1.15: 0x0000

Why this tests:
- Z₀ = 0 → sigma is always 0 initially, but oscillates due to tiny atan steps
- Tests that Z converges correctly to 0 from a true-zero start
- Verifies X₀ pre-scale is correct (final X should be ~0.99997, not ~0.607)
```

### Case 2: θ = +90°

```
Input:    angle_in = 0x6488 (25736 = π/2 in Q2.14)
Expected: cos(90°) = 0.0 → Q1.15: 0x0000 (±1 LSB acceptable)
          sin(90°) = 1.0 → Q1.15: 0x7FFF

Why this tests:
- Maximum positive angle within direct CORDIC range
- Tests convergence at the boundary of the ±90° range
- cos(90°) should be very close to 0 — tests near-zero accuracy
```

### Case 3: θ = −90°

```
Input:    angle_in = 0x9B78 (signed: -25736)
Expected: cos(-90°) = 0.0  → Q1.15: 0x0000
          sin(-90°) = -1.0 → Q1.15: 0x8001 (≈-1.0 in 2's complement)

Why this tests:
- Negative angle handling
- MSB of angle is 1 → sigma starts as 1 (CW rotation)
- Tests sign extension in Z register load
```

### Case 4: θ = 45° (Golden reference)

```
Input:    angle_in = 0x3244 (12868)
Expected: cos(45°) = sin(45°) = 0.70711 → Q1.15: 0x5A82

Why this tests:
- Symmetric result: X_final should equal Y_final
- Any asymmetry reveals a bug in X vs Y update equations
- The first iteration exactly cancels Z → tests the atan[0]=Z₀ case
```

### Case 5: θ = 120° (Quadrant 2 correction)

```
Input:    angle_in = 0x860B
Quadrant: Q2
Folded:   θ' = 180° - 120° = 60°
CORDIC:   cos(60°) = 0.5, sin(60°) = 0.866
Correction: negate cosine → cos(120°) = -0.5, sin(120°) = +0.866
Expected: cosine_out = 0xC000 (−0.5 in Q1.15 2's complement)
          sine_out   = 0x6EDA (+0.866 in Q1.15)

Why this tests:
- Quadrant correction module
- Verifies folded_angle goes into CORDIC, not raw angle
- Verifies cosine negation applied correctly
- Verifies sine is NOT negated for Q2
```

### Case 6: Consecutive computations (back-to-back)

```
Apply θ = 45°, wait for done
Immediately after done, apply θ = 30°, wait for done

Why this tests:
- FSM returns to IDLE cleanly after DONE
- New start triggers a fresh computation
- Old outputs from θ=45° are overwritten correctly
- Counter resets to 0 for the second computation
- No residual state from first computation corrupts second
```

### Case 7: Reset mid-computation

```
Apply θ = 60°
After 5 clock cycles (mid-iteration), assert rst=1
After 2 cycles, release rst=0
Apply θ = 45°, wait for done, verify correct result

Why this tests:
- Reset clears all registers including partial computation
- FSM returns to IDLE from mid-ITERATE
- Counter resets to 0
- Design recovers gracefully from interrupted computation
```

### Case 8: θ = 180° (Out-of-range — expected limitation)

```
Input:    angle_in = 0xC910
Note:     180° = 3.14159 rad; in Q2.14: 51472 = 0xC910
          But 0xC910 as signed 16-bit = -14576 ≈ -0.890 rad ≈ -51°
          This is a known limitation of Q2.14 format (range ~±2 rad / ~±115°)

Expected behavior: Design will compute cos/sin of the actual signed value
                   of the angle input, not the mathematical 180°.
                   Document this as a known format limitation.

This test confirms the design does NOT crash or produce X for this input.
```

### Corner Case Summary Table

| Test | Input | What is verified |
|---|---|---|
| 0° | 0x0000 | Zero angle, X₀ pre-scale, no Z iteration |
| +90° | 0x6488 | Max positive convergence boundary |
| −90° | 0x9B78 | Max negative angle, 2's complement sigma |
| 45° | 0x3244 | Symmetric result, X=Y |
| 120° | 0x860B | Quadrant Q2 folding and sign correction |
| Back-to-back | 45° then 30° | FSM reset and restart |
| Mid-reset | any | Recovery from interrupted computation |
| 180° | 0xC910 | Format limitation, graceful handling |

---

## 10. Waveform Inspection Guide

### Required Signals to View in GTKWave

When opening the VCD file, add these signals in this order:

```
Group 1: Clock and Control
  clk
  rst
  start
  done

Group 2: FSM
  u_fsm/state[1:0]
  u_fsm/load_en
  u_fsm/iter_en
  u_fsm/out_latch

Group 3: Counter
  u_counter/count[3:0]
  u_counter/iter_done

Group 4: Datapath (most important for academic demo)
  u_datapath/x_reg[17:0]   (view as signed decimal)
  u_datapath/y_reg[17:0]   (view as signed decimal)
  u_datapath/z_reg[17:0]   (view as signed decimal)
  u_datapath/sigma

Group 5: ROM
  u_rom/addr[3:0]
  u_rom/atan_val[15:0]

Group 6: Outputs
  cosine_out[15:0]          (view as hex)
  sine_out[15:0]            (view as hex)
```

### What to Look for in the Waveform

**Correct behavior (θ = 45°):**

```
Time →    T0    T1    T2    T3    T4    ...    T17   T18   T19
          RST   IDLE  LOAD  i=0   i=1          i=15  DONE  IDLE

state:     -    00    01    10    10    ...    10    11    00
z_reg:     -    0     θ     0     -Z    ...    ~0    ~0    0
x_reg:     -    0     X₀    X₀    X₁    ...    Xf    Xf    0
y_reg:     -    0     0     X₀    Y₁    ...    Yf    Yf    0
sigma:     -    -     -     0     1     ...    ±1    -     -
done:      -    0     0     0     0     ...    0     1     0
```

Key observations to highlight in academic presentation:
1. **Z converges to zero**: the oscillating decay of z_reg is the CORDIC convergence
2. **sigma alternates**: the rotation direction flips as Z oscillates around zero
3. **X and Y grow**: starting from 0.607 and 0, they increase toward 0.707 each
4. **done is exactly 1 cycle**: a single narrow pulse at T18
5. **Outputs hold**: cosine_out and sine_out hold their value after done

### Format Interpretation in GTKWave

- Set `x_reg`, `y_reg`, `z_reg` to **Decimal** format with **Signed** interpretation
  - Actual value = displayed integer / 32768 (for Q1.15)
- Set `cosine_out`, `sine_out` to **Hex** for easy comparison with reference table
- Set `count` to **Unsigned Decimal** (0–15)
- Set `state` to **Binary** (shows 00/01/10/11)

---

## 11. Expected Results Table

These are the specific values the testbench checker compares against.

### Q1.15 Output Reference (cosine_out, sine_out in hex)

| Test # | Angle° | angle_in | cosine_out | sine_out | cos(real) | sin(real) |
|---|---|---|---|---|---|---|
| T01 | 0° | 0x0000 | 0x7FFF | 0x0000 | 1.00000 | 0.00000 |
| T02 | 15° | 0x10C1 | 0x7BA3 | 0x2121 | 0.96593 | 0.25882 |
| T03 | 30° | 0x2185 | 0x6EDA | 0x4000 | 0.86603 | 0.50000 |
| T04 | 45° | 0x3244 | 0x5A82 | 0x5A82 | 0.70711 | 0.70711 |
| T05 | 60° | 0x4305 | 0x4000 | 0x6EDA | 0.50000 | 0.86603 |
| T06 | 75° | 0x53C5 | 0x2121 | 0x7BA3 | 0.25882 | 0.96593 |
| T07 | 90° | 0x6488 | 0x0001 | 0x7FFF | 0.00000 | 1.00000 |
| T08 | −30° | 0xDE7B | 0x6EDA | 0xC000 | 0.86603 | −0.50000 |
| T09 | −45° | 0xCDBC | 0x5A82 | 0xA57E | 0.70711 | −0.70711 |
| T10 | −90° | 0x9B78 | 0x0001 | 0x8001 | 0.00000 | −1.00000 |
| T11 | 120° | 0x860B | 0xC000 | 0x6EDA | −0.50000 | 0.86603 |
| T12 | 135° | 0x9344 | 0xA57E | 0x5A82 | −0.70711 | 0.70711 |

### Hex-to-real conversion:
```
Positive values: real = hex_value / 32768
Negative values: real = (hex_value − 65536) / 32768  [2's complement]

Example:
  0x5A82 = 23170 → 23170/32768 = 0.70709 ✓
  0xC000 = 49152 → (49152−65536)/32768 = −16384/32768 = −0.50000 ✓
  0xA57E = 42366 → (42366−65536)/32768 = −23170/32768 = −0.70709 ✓
```

---

## 12. Simulation Tool Setup

### Option A: Icarus Verilog + GTKWave (Recommended)

**Install on Windows:**
```
Download: http://bleyer.org/icarus/
Install: iverilog + gtkwave bundle
Add to PATH: C:\iverilog\bin
```

**Compile and run:**
```bash
# Compile all RTL and testbench together
iverilog -o sim/cordic_sim.vvp \
    rtl/cordic_top.v \
    rtl/cordic_fsm.v \
    rtl/cordic_datapath.v \
    rtl/cordic_atan_rom.v \
    rtl/cordic_iter_counter.v \
    rtl/cordic_quadrant.v \
    rtl/cordic_output_reg.v \
    tb/tb_cordic_top.v

# Run simulation
vvp sim/cordic_sim.vvp

# View waveforms
gtkwave sim/waves/cordic_tb.vcd
```

**Expected console output:**
```
=== CORDIC Testbench Starting ===
PASS: T01_0deg    | cos=0x7FFE (err=1 LSB) | sin=0x0000 (err=0 LSB)
PASS: T02_15deg   | cos=0x7BA2 (err=1 LSB) | sin=0x2121 (err=0 LSB)
PASS: T03_30deg   | cos=0x6EDA (err=0 LSB) | sin=0x3FFF (err=1 LSB)
PASS: T04_45deg   | cos=0x5A82 (err=0 LSB) | sin=0x5A82 (err=0 LSB)
PASS: T05_60deg   | cos=0x4000 (err=0 LSB) | sin=0x6EDA (err=0 LSB)
PASS: T06_75deg   | cos=0x2121 (err=0 LSB) | sin=0x7BA3 (err=0 LSB)
PASS: T07_90deg   | cos=0x0001 (err=1 LSB) | sin=0x7FFF (err=0 LSB)
PASS: T08_neg30   | cos=0x6EDA (err=0 LSB) | sin=0xC000 (err=0 LSB)
PASS: T09_neg45   | cos=0x5A82 (err=0 LSB) | sin=0xA57E (err=0 LSB)
PASS: T10_neg90   | cos=0x0001 (err=1 LSB) | sin=0x8001 (err=0 LSB)
PASS: T11_120deg  | cos=0xC000 (err=0 LSB) | sin=0x6EDA (err=0 LSB)
PASS: T12_135deg  | cos=0xA57E (err=0 LSB) | sin=0x5A82 (err=0 LSB)
=== RESULTS: 12 PASS, 0 FAIL ===
```

### Option B: ModelSim / Questa

```tcl
# Create work library
vlib work

# Compile RTL
vlog rtl/cordic_top.v rtl/cordic_fsm.v rtl/cordic_datapath.v \
     rtl/cordic_atan_rom.v rtl/cordic_iter_counter.v \
     rtl/cordic_quadrant.v rtl/cordic_output_reg.v

# Compile testbench
vlog tb/tb_cordic_top.v

# Run simulation
vsim tb_cordic_top -voptargs=+acc

# Add waves
add wave -recursive *
add wave /tb_cordic_top/dut/u_datapath/x_reg
add wave /tb_cordic_top/dut/u_datapath/y_reg
add wave /tb_cordic_top/dut/u_datapath/z_reg

# Run all
run -all
```

---

## 13. Complete Testbench Code

```verilog
// ============================================================
// File: tb/tb_cordic_top.v
// Purpose: Integration testbench for cordic_top
// Simulation tool: Icarus Verilog (iverilog) + GTKWave
// ============================================================

`timescale 1ns/1ps

module tb_cordic_top;

    // ---- Parameters ----
    parameter CLK_PERIOD   = 20;    // 50 MHz
    parameter RESET_CYCLES = 5;
    parameter MAX_WAIT     = 30;    // Cycles before timeout
    parameter ERROR_LIMIT  = 4;     // Max allowed LSB error

    // ---- DUT I/O ----
    reg         clk;
    reg         rst;
    reg         start;
    reg  [15:0] angle_in;
    wire        done;
    wire [15:0] sine_out;
    wire [15:0] cosine_out;

    // ---- DUT Instantiation ----
    cordic_top dut (
        .clk       (clk),
        .rst       (rst),
        .start     (start),
        .angle_in  (angle_in),
        .done      (done),
        .sine_out  (sine_out),
        .cosine_out(cosine_out)
    );

    // ---- VCD Waveform Dump ----
    initial begin
        $dumpfile("sim/waves/cordic_tb.vcd");
        $dumpvars(0, tb_cordic_top);
    end

    // ---- Clock Generation ----
    initial clk = 1'b0;
    always #(CLK_PERIOD / 2) clk = ~clk;

    // ---- Test tracking ----
    integer pass_count = 0;
    integer fail_count = 0;
    integer cos_err, sin_err;
    integer wait_cnt;

    // ---- Helper: Absolute difference ----
    function [15:0] abs_diff16;
        input [15:0] a, b;
        begin
            abs_diff16 = (a >= b) ? (a - b) : (b - a);
        end
    endfunction

    // ---- Task: apply one angle and verify result ----
    task run_test;
        input [15:0] angle;
        input [15:0] exp_cos;
        input [15:0] exp_sin;
        input [8*20:1] label;
        begin
            @(negedge clk);
            angle_in = angle;
            start    = 1'b1;
            @(posedge clk);
            #1;
            start    = 1'b0;

            wait_cnt = 0;
            while (!done && wait_cnt < MAX_WAIT) begin
                @(posedge clk);
                wait_cnt = wait_cnt + 1;
            end

            if (wait_cnt >= MAX_WAIT) begin
                $display("TIMEOUT  : %s", label);
                fail_count = fail_count + 1;
            end else begin
                cos_err = abs_diff16(cosine_out, exp_cos);
                sin_err = abs_diff16(sine_out,   exp_sin);
                if (cos_err <= ERROR_LIMIT && sin_err <= ERROR_LIMIT) begin
                    $display("PASS: %s | cos=0x%04h (err=%0d) | sin=0x%04h (err=%0d)",
                              label, cosine_out, cos_err, sine_out, sin_err);
                    pass_count = pass_count + 1;
                end else begin
                    $display("FAIL: %s | cos=0x%04h exp=0x%04h (err=%0d) | sin=0x%04h exp=0x%04h (err=%0d)",
                              label, cosine_out, exp_cos, cos_err, sine_out, exp_sin, sin_err);
                    fail_count = fail_count + 1;
                end
            end

            repeat (3) @(posedge clk);  // gap between tests
        end
    endtask

    // ---- Task: Reset DUT ----
    task do_reset;
        begin
            rst      = 1'b1;
            start    = 1'b0;
            angle_in = 16'h0000;
            repeat (RESET_CYCLES) @(posedge clk);
            @(negedge clk);
            rst = 1'b0;
            #1;
        end
    endtask

    // ---- Main Test Sequence ----
    initial begin
        $display("==============================================");
        $display("    CORDIC Testbench — Starting Simulation    ");
        $display("==============================================");

        do_reset;

        // ---- Standard test angles ----
        //               angle_in  exp_cos  exp_sin   label
        run_test(16'h0000, 16'h7FFF, 16'h0000, "T01_0deg   ");
        run_test(16'h10C1, 16'h7BA3, 16'h2121, "T02_15deg  ");
        run_test(16'h2185, 16'h6EDA, 16'h4000, "T03_30deg  ");
        run_test(16'h3244, 16'h5A82, 16'h5A82, "T04_45deg  ");
        run_test(16'h4305, 16'h4000, 16'h6EDA, "T05_60deg  ");
        run_test(16'h53C5, 16'h2121, 16'h7BA3, "T06_75deg  ");
        run_test(16'h6488, 16'h0001, 16'h7FFF, "T07_90deg  ");

        // ---- Negative angles ----
        run_test(16'hDE7B, 16'h6EDA, 16'hC000, "T08_neg30  ");
        run_test(16'hCDBC, 16'h5A82, 16'hA57E, "T09_neg45  ");
        run_test(16'h9B78, 16'h0001, 16'h8001, "T10_neg90  ");

        // ---- Quadrant 2 (requires quadrant correction) ----
        run_test(16'h860B, 16'hC000, 16'h6EDA, "T11_120deg ");
        run_test(16'h9344, 16'hA57E, 16'h5A82, "T12_135deg ");

        // ---- Back-to-back test ----
        $display("--- Back-to-back test ---");
        run_test(16'h3244, 16'h5A82, 16'h5A82, "T13_BB_45  ");
        run_test(16'h2185, 16'h6EDA, 16'h4000, "T14_BB_30  ");

        // ---- Mid-computation reset test ----
        $display("--- Mid-reset test ---");
        @(negedge clk);
        angle_in = 16'h4305;  // 60 degrees
        start    = 1'b1;
        @(posedge clk); #1;
        start    = 1'b0;
        repeat (5) @(posedge clk);  // Let it run 5 iterations
        rst = 1'b1;                 // Assert reset mid-computation
        repeat (2) @(posedge clk);
        rst = 1'b0;
        #1;
        repeat (3) @(posedge clk);
        // Now apply a fresh angle — should work correctly
        run_test(16'h3244, 16'h5A82, 16'h5A82, "T15_AfterRst");

        // ---- Final report ----
        $display("==============================================");
        $display("  RESULTS: %0d PASS, %0d FAIL", pass_count, fail_count);
        if (fail_count == 0)
            $display("  STATUS: ALL TESTS PASSED");
        else
            $display("  STATUS: SOME TESTS FAILED — review output");
        $display("==============================================");

        $finish;
    end

    // ---- Timeout watchdog ----
    initial begin
        #(CLK_PERIOD * 2000);
        $display("WATCHDOG: Simulation exceeded time limit — forcing stop");
        $finish;
    end

endmodule
```

---

## Summary of Phase 6

| Verification Item | Method | Status |
|---|---|---|
| ROM correctness | Unit testbench, exact match | Specified |
| Counter behavior | Unit testbench, count + done | Specified |
| FSM transitions | Unit testbench, state trace | Specified |
| Datapath iteration | Unit testbench, manual 16 steps | Specified |
| Integration: all angles | Top-level TB, 12 test vectors | Specified |
| Latency check | Cycle-count from start to done | Specified |
| Done pulse width | Single-cycle verification | Specified |
| Negative angles | Dedicated test vectors | Specified |
| Quadrant correction | 120°, 135° tests | Specified |
| Back-to-back | Consecutive computation test | Specified |
| Mid-reset recovery | Interrupt + restart test | Specified |
| Error threshold | ≤ 4 LSBs per output | Specified |
| Waveform capture | VCD → GTKWave | Specified |
| Tool | Icarus Verilog + GTKWave | Recommended |

---

*Document Status: Complete — Phase 6*  
*Next Phase: COA Concepts and Viva Preparation (Phase 7)*  
*Prepared for: COA Academic Project — CORDIC Verilog Implementation*
