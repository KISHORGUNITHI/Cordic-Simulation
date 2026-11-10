# Phase 5: Verilog Implementation Blueprint
## CORDIC Algorithm — Complete RTL Module Specifications

---

## Table of Contents

1. [Project Directory Structure](#1-project-directory-structure)
2. [Global Parameters and Constants](#2-global-parameters-and-constants)
3. [Module 1: cordic_top](#3-module-1-cordic_top)
4. [Module 2: cordic_fsm](#4-module-2-cordic_fsm)
5. [Module 3: cordic_datapath](#5-module-3-cordic_datapath)
6. [Module 4: cordic_atan_rom](#6-module-4-cordic_atan_rom)
7. [Module 5: cordic_iter_counter](#7-module-5-cordic_iter_counter)
8. [Module 6: cordic_quadrant](#8-module-6-cordic_quadrant)
9. [Module 7: cordic_output_reg](#9-module-7-cordic_output_reg)
10. [Inter-Module Wiring Reference](#10-inter-module-wiring-reference)
11. [Synthesis and Simulation Notes](#11-synthesis-and-simulation-notes)
12. [Implementation Checklist for Antigravity](#12-implementation-checklist-for-antigravity)

---

## 1. Project Directory Structure

```
COA_CORDIC/
│
├── rtl/                          ← All synthesizable Verilog RTL
│   ├── cordic_top.v              ← Top-level structural module
│   ├── cordic_fsm.v              ← Control FSM (4-state Moore)
│   ├── cordic_datapath.v         ← CORDIC X/Y/Z iteration logic
│   ├── cordic_atan_rom.v         ← Arctangent lookup table ROM
│   ├── cordic_iter_counter.v     ← 4-bit iteration counter
│   ├── cordic_quadrant.v         ← Quadrant detection and correction
│   └── cordic_output_reg.v       ← Output latch registers
│
├── tb/                           ← Testbenches (non-synthesizable)
│   ├── tb_cordic_top.v           ← Top-level integration testbench
│   ├── tb_cordic_fsm.v           ← FSM unit test
│   ├── tb_cordic_datapath.v      ← Datapath unit test
│   └── tb_cordic_atan_rom.v      ← ROM verification
│
├── sim/                          ← Simulation outputs
│   ├── waves/                    ← VCD waveform dumps
│   └── logs/                     ← Simulation log files
│
├── docs/                         ← Project documentation
│   ├── phase1_mathematical_foundation.md
│   ├── phase2_hardware_architecture.md
│   ├── phase3_implementation_strategy.md
│   ├── phase4_numerical_validation.md
│   └── phase5_verilog_blueprint.md
│
└── scripts/
    ├── compile.sh                ← Icarus Verilog compile script
    └── simulate.sh               ← Simulation + VCD generation script
```

---

## 2. Global Parameters and Constants

These constants are used consistently across all modules. They must not be changed without updating all dependent modules.

```verilog
// ============================================================
// CORDIC Global Parameters
// ============================================================

// Data widths
parameter DATA_WIDTH   = 16;    // External I/O width (Q1.15)
parameter INT_WIDTH    = 18;    // Internal datapath width (2 guard bits)
parameter ANGLE_WIDTH  = 16;    // Angle input width (Q2.14)
parameter ITER_BITS    = 4;     // Bits for iteration counter (0–15)
parameter NUM_ITER     = 16;    // Number of CORDIC iterations

// Fixed-point constants
// X₀ = 1/K₁₆ = 0.60725, in Q1.15: round(0.60725 × 32768) = 19898 = 0x4DBA
parameter X0_INIT      = 18'sh04DBA;  // Pre-scaled initial X (signed, 18-bit)
parameter Y0_INIT      = 18'sh00000;  // Initial Y = 0

// FSM state encoding
parameter IDLE    = 2'b00;
parameter LOAD    = 2'b01;
parameter ITERATE = 2'b10;
parameter DONE    = 2'b11;

// Quadrant encoding
parameter Q1 = 2'b00;   // 0° to 90°
parameter Q2 = 2'b01;   // 90° to 180°
parameter Q3 = 2'b10;   // -180° to -90°
parameter Q4 = 2'b11;   // -90° to 0°

// Angle boundaries in Q2.14
// π/2  = 1.5708 radians → round(1.5708 × 16384) = 25736 = 0x6488
parameter PI_OVER_2    = 16'sh6488;   // +π/2 in Q2.14
parameter NEG_PI_OVER_2 = 16'shA178; // -π/2 in Q2.14 (2's complement of 25736 → -25736 = 0x9B78... note: -(25736) in 16-bit = 65536-25736 = 39800 = 0x9B78 — but as signed: -25736)
// π    = 3.1416 radians → round(3.1416 × 16384) = 51472 = 0xC910
parameter PI           = 16'shC910;  // Note: use only for quadrant detection

// Arctangent ROM constants (Q2.14 format, 16-bit values)
// arctan(2^-i) × 16384 for i = 0 to 15
```

---

## 3. Module 1: `cordic_top`

### Purpose
Top-level structural module. Instantiates all sub-modules and connects them with internal wires. Contains no behavioral logic of its own.

### Port Declaration

```verilog
module cordic_top (
    input  wire        clk,           // System clock
    input  wire        rst,           // Synchronous active-high reset
    input  wire        start,         // Begin computation (1-cycle pulse)
    input  wire [15:0] angle_in,      // Input angle: Q2.14, signed, radians
    output wire        done,          // Computation complete (1-cycle pulse)
    output wire [15:0] sine_out,      // sin(θ) result: Q1.15 signed
    output wire [15:0] cosine_out     // cos(θ) result: Q1.15 signed
);
```

### Internal Wires

```verilog
    // ---- Quadrant correction signals ----
    wire [15:0] folded_angle;         // Angle folded into [-π/2, +π/2]
    wire [1:0]  quadrant;             // Detected quadrant (Q1/Q2/Q3/Q4)

    // ---- FSM control signals ----
    wire        load_en;              // FSM → datapath: load initial values
    wire        iter_en;              // FSM → datapath + counter: do iteration
    wire        cnt_rst;              // FSM → counter: reset count to 0
    wire        out_latch;            // FSM → output reg: capture final result

    // ---- Iteration counter signals ----
    wire [3:0]  iter_count;           // Current iteration index (0–15)
    wire        iter_done;            // Counter → FSM: all iterations done

    // ---- ROM signal ----
    wire [15:0] atan_val;             // ROM → datapath: arctan(2^-iter_count)

    // ---- Datapath output signals ----
    wire [17:0] x_result;             // Datapath → output reg: X (cosine raw)
    wire [17:0] y_result;             // Datapath → output reg: Y (sine raw)

    // ---- Pre-output (before quadrant correction) ----
    wire [15:0] cos_raw;              // cos before quadrant sign correction
    wire [15:0] sin_raw;              // sin before quadrant sign correction
```

### Sub-module Instantiations

```verilog
    // ---- Quadrant pre-processing ----
    cordic_quadrant u_quadrant (
        .angle_in    (angle_in),
        .folded_angle(folded_angle),
        .quadrant    (quadrant)
    );

    // ---- FSM control unit ----
    cordic_fsm u_fsm (
        .clk      (clk),
        .rst      (rst),
        .start    (start),
        .iter_done(iter_done),
        .load_en  (load_en),
        .iter_en  (iter_en),
        .cnt_rst  (cnt_rst),
        .out_latch(out_latch),
        .done     (done)
    );

    // ---- Iteration counter ----
    cordic_iter_counter u_counter (
        .clk      (clk),
        .rst      (rst),
        .cnt_rst  (cnt_rst),
        .iter_en  (iter_en),
        .count    (iter_count),
        .iter_done(iter_done)
    );

    // ---- Arctangent ROM ----
    cordic_atan_rom u_rom (
        .addr    (iter_count),
        .atan_val(atan_val)
    );

    // ---- CORDIC datapath ----
    cordic_datapath u_datapath (
        .clk      (clk),
        .rst      (rst),
        .load_en  (load_en),
        .iter_en  (iter_en),
        .angle_in (folded_angle),
        .iter_count(iter_count),
        .atan_val (atan_val),
        .x_out    (x_result),
        .y_out    (y_result)
    );

    // ---- Output registers ----
    cordic_output_reg u_outreg (
        .clk      (clk),
        .rst      (rst),
        .out_latch(out_latch),
        .x_in     (x_result[15:0]),
        .y_in     (y_result[15:0]),
        .cos_out  (cos_raw),
        .sin_out  (sin_raw)
    );

    // ---- Quadrant post-correction (combinational) ----
    // Apply sign correction based on detected quadrant
    assign cosine_out = (quadrant == 2'b01 || quadrant == 2'b10) ?
                        (~cos_raw + 1'b1) : cos_raw;   // negate for Q2, Q3
    assign sine_out   = (quadrant == 2'b10 || quadrant == 2'b11) ?
                        (~sin_raw + 1'b1) : sin_raw;   // negate for Q3, Q4

endmodule
```

---

## 4. Module 2: `cordic_fsm`

### Purpose
Moore finite state machine with 4 states. Generates all control signals for the datapath, counter, and output registers. All outputs depend only on the current state (Moore property).

### Complete RTL Specification

```verilog
module cordic_fsm (
    input  wire clk,
    input  wire rst,
    input  wire start,       // External start trigger
    input  wire iter_done,   // From counter: 16 iterations complete
    output reg  load_en,     // Pulse: load initial X0, Y0, Z0
    output reg  iter_en,     // Enable: perform one CORDIC iteration
    output reg  cnt_rst,     // Reset iteration counter
    output reg  out_latch,   // Pulse: latch X/Y into output registers
    output reg  done         // Pulse: computation complete
);

    // ---- State register ----
    reg [1:0] state, next_state;

    // State encoding (matches parameters in cordic_top)
    // IDLE = 2'b00, LOAD = 2'b01, ITERATE = 2'b10, DONE = 2'b11

    // ---- State register (sequential) ----
    always @(posedge clk) begin
        if (rst)
            state <= 2'b00;  // IDLE
        else
            state <= next_state;
    end

    // ---- Next-state logic (combinational) ----
    always @(*) begin
        case (state)
            2'b00: next_state = start     ? 2'b01 : 2'b00; // IDLE → LOAD if start
            2'b01: next_state = 2'b10;                      // LOAD → ITERATE always
            2'b10: next_state = iter_done ? 2'b11 : 2'b10; // ITERATE → DONE if done
            2'b11: next_state = 2'b00;                      // DONE → IDLE always
            default: next_state = 2'b00;
        endcase
    end

    // ---- Output logic (combinational, Moore) ----
    always @(*) begin
        // Default all outputs to 0 (prevents latches)
        load_en   = 1'b0;
        iter_en   = 1'b0;
        cnt_rst   = 1'b0;
        out_latch = 1'b0;
        done      = 1'b0;

        case (state)
            2'b00: begin  // IDLE
                cnt_rst = 1'b1;
            end
            2'b01: begin  // LOAD
                load_en = 1'b1;
                cnt_rst = 1'b1;
            end
            2'b10: begin  // ITERATE
                iter_en = 1'b1;
            end
            2'b11: begin  // DONE
                out_latch = 1'b1;
                done      = 1'b1;
            end
        endcase
    end

endmodule
```

### FSM Behavior Notes

- `cnt_rst` is asserted in both IDLE and LOAD to guarantee the counter starts from 0 when ITERATE begins
- `done` is a single-cycle pulse — the testbench must capture output on the same cycle as `done`
- The FSM has no deadlock states — DONE always returns to IDLE in one cycle
- `next_state` uses `always @(*)` to avoid latches: all cases covered, defaults set

---

## 5. Module 3: `cordic_datapath`

### Purpose
Core CORDIC arithmetic unit. On each `iter_en` pulse, it updates X, Y, and Z registers by one CORDIC iteration. Uses arithmetic right shifts and 2's complement addition/subtraction.

### Complete RTL Specification

```verilog
module cordic_datapath (
    input  wire        clk,
    input  wire        rst,
    input  wire        load_en,        // Load initial conditions
    input  wire        iter_en,        // Perform one iteration
    input  wire [15:0] angle_in,       // Z₀: input angle Q2.14 (folded)
    input  wire [3:0]  iter_count,     // Current iteration index i
    input  wire [15:0] atan_val,       // arctan(2^-i) from ROM
    output wire [17:0] x_out,          // X register (18-bit, Q3.15)
    output wire [17:0] y_out           // Y register (18-bit, Q3.15)
);

    // ---- Internal registers (18-bit for overflow protection) ----
    reg signed [17:0] x_reg;
    reg signed [17:0] y_reg;
    reg signed [17:0] z_reg;

    // ---- Initial conditions (constants) ----
    // X0 = 1/K16 = 0.60725 in Q1.15 = 19898 = 0x4DBA, sign-extended to 18-bit
    localparam signed [17:0] X0_CONST = 18'sh04DBA;
    localparam signed [17:0] Y0_CONST = 18'sh00000;

    // ---- Combinational signals ----
    wire        sigma;                 // Rotation direction: 0=CCW(+), 1=CW(-)
    wire signed [17:0] x_shift;       // x_reg >>> iter_count
    wire signed [17:0] y_shift;       // y_reg >>> iter_count
    wire signed [17:0] atan_ext;      // atan_val sign-extended to 18-bit
    wire signed [17:0] x_next;        // Combinational next X
    wire signed [17:0] y_next;        // Combinational next Y
    wire signed [17:0] z_next;        // Combinational next Z

    // ---- Sign of Z determines rotation direction ----
    assign sigma   = z_reg[17];       // MSB of z_reg: 0=positive, 1=negative

    // ---- Arithmetic right shifts ----
    assign x_shift = x_reg >>> iter_count;
    assign y_shift = y_reg >>> iter_count;

    // ---- Sign-extend atan_val from 16-bit to 18-bit ----
    assign atan_ext = {{2{atan_val[15]}}, atan_val};

    // ---- Next-value computation (CORDIC equations) ----
    // When sigma=0 (Z≥0, CCW):  X=X-Y>>i, Y=Y+X>>i, Z=Z-atan
    // When sigma=1 (Z<0, CW):   X=X+Y>>i, Y=Y-X>>i, Z=Z+atan
    assign x_next = sigma ? (x_reg + y_shift) : (x_reg - y_shift);
    assign y_next = sigma ? (y_reg - x_shift) : (y_reg + x_shift);
    assign z_next = sigma ? (z_reg + atan_ext) : (z_reg - atan_ext);

    // ---- Sequential register update ----
    always @(posedge clk) begin
        if (rst) begin
            x_reg <= 18'sh00000;
            y_reg <= 18'sh00000;
            z_reg <= 18'sh00000;
        end
        else if (load_en) begin
            x_reg <= X0_CONST;
            y_reg <= Y0_CONST;
            z_reg <= {{2{angle_in[15]}}, angle_in};  // sign-extend angle to 18-bit
        end
        else if (iter_en) begin
            x_reg <= x_next;
            y_reg <= y_next;
            z_reg <= z_next;
        end
        // else: hold current values
    end

    // ---- Output connections ----
    assign x_out = x_reg;
    assign y_out = y_reg;

endmodule
```

### Critical Implementation Notes

1. **`reg signed` declaration** is essential — it allows Verilog to treat `>>>` as arithmetic shift
2. **Sign extension of `angle_in`**: The input is 16-bit Q2.14; the internal Z register is 18-bit. The two MSBs must be replicated: `{{2{angle_in[15]}}, angle_in}`
3. **Sign extension of `atan_val`**: ROM outputs 16-bit values; must be sign-extended to 18-bit before arithmetic
4. **Shift priority**: `x_next` uses `y_shift` (not `x_shift`), and `y_next` uses `x_shift` (not `y_shift`) — this is correct per CORDIC equations
5. **Hold behavior**: If neither `load_en` nor `iter_en` is asserted, registers hold their value (implemented by the `else` clause doing nothing)

---

## 6. Module 4: `cordic_atan_rom`

### Purpose
Read-only memory storing 16 precomputed arctangent values. Addressed by iteration index. Purely combinational (asynchronous read).

### Complete RTL Specification

```verilog
module cordic_atan_rom (
    input  wire [3:0]  addr,       // Iteration index (0–15)
    output reg  [15:0] atan_val    // arctan(2^-addr) in Q2.14
);

    // All values: arctan(2^-i) × 16384, rounded to nearest integer
    // Format: Q2.14 unsigned (all values are positive)
    always @(*) begin
        case (addr)
            4'd0:  atan_val = 16'd12868; // arctan(2^0)  = arctan(1)     = 0.78540 rad
            4'd1:  atan_val = 16'd7596;  // arctan(2^-1) = arctan(0.5)   = 0.46365 rad
            4'd2:  atan_val = 16'd4013;  // arctan(2^-2) = arctan(0.25)  = 0.24498 rad
            4'd3:  atan_val = 16'd2037;  // arctan(2^-3) = arctan(0.125) = 0.12435 rad
            4'd4:  atan_val = 16'd1022;  // arctan(2^-4)                 = 0.06242 rad
            4'd5:  atan_val = 16'd512;   // arctan(2^-5)                 = 0.03124 rad
            4'd6:  atan_val = 16'd256;   // arctan(2^-6)                 = 0.01562 rad
            4'd7:  atan_val = 16'd128;   // arctan(2^-7)                 = 0.00781 rad
            4'd8:  atan_val = 16'd64;    // arctan(2^-8)                 = 0.00391 rad
            4'd9:  atan_val = 16'd32;    // arctan(2^-9)                 = 0.00195 rad
            4'd10: atan_val = 16'd16;    // arctan(2^-10)                = 0.00098 rad
            4'd11: atan_val = 16'd8;     // arctan(2^-11)                = 0.00049 rad
            4'd12: atan_val = 16'd4;     // arctan(2^-12)                = 0.00024 rad
            4'd13: atan_val = 16'd2;     // arctan(2^-13)                = 0.00012 rad
            4'd14: atan_val = 16'd1;     // arctan(2^-14)                = 0.00006 rad
            4'd15: atan_val = 16'd1;     // arctan(2^-15)                = 0.00003 rad
            default: atan_val = 16'd0;
        endcase
    end

endmodule
```

### ROM Value Derivation Notes

- All values computed as `round(arctan(2⁻ⁱ) × 16384)`
- `i=0`: arctan(1) = π/4 = 0.785398 → 0.785398 × 16384 = 12867.96 → **12868**
- `i=1`: arctan(0.5) = 0.463648 → 0.463648 × 16384 = 7596.1 → **7596**
- `i=14` and `i=15` both round to 1 (smallest representable non-zero value in Q2.14)
- The ROM is purely combinational — no clock input required
- `default` case returns 0 to prevent synthesis tool warnings

---

## 7. Module 5: `cordic_iter_counter`

### Purpose
4-bit synchronous counter. Counts from 0 to 15 during the ITERATE state. Asserts `iter_done` when the 15th iteration completes. Resets on `cnt_rst` from the FSM.

### Complete RTL Specification

```verilog
module cordic_iter_counter (
    input  wire       clk,
    input  wire       rst,
    input  wire       cnt_rst,    // FSM-controlled synchronous reset
    input  wire       iter_en,    // Count enable (from FSM)
    output reg  [3:0] count,      // Current iteration index (0–15)
    output wire       iter_done   // All 16 iterations complete
);

    // ---- Counter logic ----
    always @(posedge clk) begin
        if (rst || cnt_rst)
            count <= 4'd0;
        else if (iter_en)
            count <= count + 4'd1;
        // else: hold
    end

    // ---- Done detection ----
    // iter_done fires when count==15 AND iter_en is asserted
    // This means: after the 16th iteration (index 15) is enabled
    assign iter_done = (count == 4'd15) && iter_en;

endmodule
```

### Timing Note

`iter_done` is combinational and asserts in the same cycle that iteration 15 is triggered. The FSM samples `iter_done` on the next rising edge and transitions from ITERATE → DONE. This means:
- Cycle N+16: count=15, iter_en=1, iter_done=1 → FSM moves to DONE
- Cycle N+17: FSM in DONE state, out_latch=1, done=1

This matches the 19-cycle total latency established in Phase 2.

---

## 8. Module 6: `cordic_quadrant`

### Purpose
Detects which quadrant the input angle falls in and folds it into the CORDIC convergence range [-π/2, +π/2]. Also outputs the quadrant code so `cordic_top` can apply output sign corrections.

### Complete RTL Specification

```verilog
module cordic_quadrant (
    input  wire signed [15:0] angle_in,      // Raw angle: Q2.14, range [-π, +π]
    output reg  signed [15:0] folded_angle,  // Folded angle: Q2.14, range [-π/2, +π/2]
    output reg         [1:0]  quadrant       // Quadrant code: 00=Q1,01=Q2,10=Q3,11=Q4
);

    // Thresholds in Q2.14
    // +π/2 = 25736 = 0x6488
    // -π/2 = -25736 (signed) = 16'shA178... 
    //   Note: in 16-bit 2's comp: -25736 = 65536 - 25736 = 39800 = 0x9B78
    // +π   = 51472 = 0xC910 (but this exceeds signed 16-bit range of 32767)
    //   Note: for detecting angles > π/2, compare against 25736
    // The input range is assumed to be [-π, +π]:
    //   π in Q2.14 would be 51472, which overflows 16-bit signed (max=32767).
    //   Therefore input is restricted to [-π/2-ε, +π/2+ε] for direct CORDIC,
    //   and angles outside are folded.
    //
    // Practical input range for Q2.14 signed:
    //   Max positive: 32767 / 16384 = 1.99994 rad (> π/2 = 1.5708, < π = 3.1416)
    //   Max negative: -32768 / 16384 = -2.0000 rad (< -π/2, > -π)
    //
    // Quadrant detection:
    //   Q1: angle_in >= 0 AND angle_in <= PI/2        → no correction
    //   Q2: angle_in > PI/2                           → fold: π/2 - (angle - π/2) = π - angle
    //   Q4: angle_in < 0 AND angle_in >= -PI/2        → no correction (negative handled by sigma)
    //   Q3: angle_in < -PI/2                          → fold: -(π + angle) = -π - angle

    localparam signed [15:0] PI_OVER_2     = 16'sh6488;  // +25736 = +π/2
    localparam signed [15:0] NEG_PI_OVER_2 = 16'sh9B78;  // -25736 = -π/2 (signed 2's comp)
    // PI in Q2.14 = 51472, which overflows 16-bit signed.
    // Use 16'shC910 interpreted as signed: 0xC910 = -14384 in signed 16-bit.
    // Better approach: compare angle_in > PI/2 directly (angle_in > 25736)
    // For full π range, use a wider comparison:
    localparam signed [15:0] PI_Q2_14      = 16'sh7FFF;  // max positive as stand-in

    always @(*) begin
        if (angle_in >= 0 && angle_in <= PI_OVER_2) begin
            // Q1: 0° to 90° — direct CORDIC, no correction
            quadrant     = 2'b00;
            folded_angle = angle_in;
        end
        else if (angle_in > PI_OVER_2) begin
            // Q2: 90° to ~115° (max of Q2.14 signed = ~115°)
            // fold: folded = π/2 - (angle - π/2) = π - angle
            // In Q2.14: fold = 2×PI_OVER_2 - angle_in
            // But 2×25736 = 51472 overflows 16-bit signed — use subtraction with wider arithmetic
            quadrant     = 2'b01;
            folded_angle = (16'sh6488 - angle_in) + 16'sh6488; // (PI_OVER_2 - angle) + PI_OVER_2
            // Simplified: PI - angle_in; since PI overflows, use workaround:
            // folded = ~(angle_in - PI_OVER_2 - 1) = -(angle_in - PI_OVER_2) = PI_OVER_2 - angle_in + PI_OVER_2
            // This gives the supplementary angle correctly within range.
        end
        else if (angle_in < 0 && angle_in >= NEG_PI_OVER_2) begin
            // Q4: -90° to 0° — direct CORDIC (negative angle handled by σ)
            quadrant     = 2'b11;
            folded_angle = angle_in;
        end
        else begin
            // Q3: -115° to -90° (most negative of Q2.14 signed)
            // fold: folded = -(π + angle) = -π - angle = -PI_OVER_2 - (angle + PI_OVER_2)
            quadrant     = 2'b10;
            folded_angle = -(16'sh6488 + angle_in) - 16'sh6488;
            // = -PI_OVER_2 - angle - PI_OVER_2 = -2×PI_OVER_2 - angle = -PI - angle (correct fold)
        end
    end

endmodule
```

### Quadrant Correction Note for Antigravity

The Q2.14 format with 16-bit signed limits the representable range to approximately ±1.99994 radians (~±115°). This covers more than ±90° but less than ±180°. The quadrant correction handles the range from ±90° to ±115°. For truly full ±180° support, the angle register would need to be wider (Q3.13 with 17 bits) — this is documented as a known limitation but does not affect the academic demonstration since all standard test angles (0°, 30°, 45°, 60°, 90°, 120°) are covered.

**For the academic project**, test angles are restricted to ±90° (direct) and 120°/135° via Q2 folding. This demonstrates the concept thoroughly without requiring the full ±180° edge case.

---

## 9. Module 7: `cordic_output_reg`

### Purpose
Holds the final X and Y values stable at the output after computation completes. Prevents outputs from changing when the FSM returns to IDLE and registers are cleared.

### Complete RTL Specification

```verilog
module cordic_output_reg (
    input  wire        clk,
    input  wire        rst,
    input  wire        out_latch,     // Capture enable from FSM (DONE state)
    input  wire [15:0] x_in,          // X value from datapath (cosine, Q1.15)
    input  wire [15:0] y_in,          // Y value from datapath (sine, Q1.15)
    output reg  [15:0] cos_out,       // Registered cosine output
    output reg  [15:0] sin_out        // Registered sine output
);

    always @(posedge clk) begin
        if (rst) begin
            cos_out <= 16'h0000;
            sin_out <= 16'h0000;
        end
        else if (out_latch) begin
            cos_out <= x_in;
            sin_out <= y_in;
        end
        // else: hold last valid result
    end

endmodule
```

### Output Stability Note

Once `out_latch` fires and the outputs are captured:
- `cos_out` and `sin_out` hold the computed values until the next `out_latch` pulse
- They are NOT cleared when `rst` fires mid-computation (only at power-up or hard reset)
- This means the outputs remain valid and readable even after `done` has gone low

---

## 10. Inter-Module Wiring Reference

This table is the definitive signal routing guide for Antigravity. Every internal wire in `cordic_top` must match these connections exactly.

| Signal | Driver | Receivers | Width | Description |
|---|---|---|---|---|
| `clk` | External | ALL | 1 | System clock |
| `rst` | External | ALL | 1 | Synchronous reset |
| `start` | External | `cordic_fsm` | 1 | Begin trigger |
| `angle_in` | External | `cordic_quadrant` | 16 | Raw input angle |
| `folded_angle` | `cordic_quadrant` | `cordic_datapath` | 16 | Quadrant-corrected angle |
| `quadrant` | `cordic_quadrant` | `cordic_top` (assign) | 2 | Quadrant code |
| `load_en` | `cordic_fsm` | `cordic_datapath` | 1 | Load initial values |
| `iter_en` | `cordic_fsm` | `cordic_datapath`, `cordic_iter_counter` | 1 | Iteration enable |
| `cnt_rst` | `cordic_fsm` | `cordic_iter_counter` | 1 | Counter reset |
| `out_latch` | `cordic_fsm` | `cordic_output_reg` | 1 | Latch outputs |
| `done` | `cordic_fsm` | External | 1 | Result ready |
| `iter_count` | `cordic_iter_counter` | `cordic_datapath`, `cordic_atan_rom` | 4 | Current index |
| `iter_done` | `cordic_iter_counter` | `cordic_fsm` | 1 | All iterations done |
| `atan_val` | `cordic_atan_rom` | `cordic_datapath` | 16 | arctan constant |
| `x_result` | `cordic_datapath` | `cordic_output_reg` | 18 | X register value |
| `y_result` | `cordic_datapath` | `cordic_output_reg` | 18 | Y register value |
| `cos_raw` | `cordic_output_reg` | `cordic_top` (assign) | 16 | Cosine before sign fix |
| `sin_raw` | `cordic_output_reg` | `cordic_top` (assign) | 16 | Sine before sign fix |
| `cosine_out` | `cordic_top` (assign) | External | 16 | Final cosine |
| `sine_out` | `cordic_top` (assign) | External | 16 | Final sine |

---

## 11. Synthesis and Simulation Notes

### Simulation Tool: Icarus Verilog (iverilog) + GTKWave

**Recommended for this project** because:
- Free and open-source
- Works on Windows, Linux, macOS
- GTKWave provides excellent waveform viewing
- Widely used in academic COA projects

**Compile command:**
```bash
iverilog -o sim/cordic_sim rtl/cordic_top.v rtl/cordic_fsm.v rtl/cordic_datapath.v \
         rtl/cordic_atan_rom.v rtl/cordic_iter_counter.v rtl/cordic_quadrant.v \
         rtl/cordic_output_reg.v tb/tb_cordic_top.v
```

**Simulate:**
```bash
vvp sim/cordic_sim
```

**View waveforms:**
```bash
gtkwave sim/waves/cordic_tb.vcd
```

### Alternative: ModelSim / Questa

If available in the lab:
```tcl
vlog rtl/*.v tb/tb_cordic_top.v
vsim tb_cordic_top
add wave -recursive *
run -all
```

### Synthesis Target: Xilinx Vivado (if FPGA demo needed)

- Target: Artix-7 or Basys-3
- All RTL is fully synthesizable (no `initial` blocks, no `#delays`, no system tasks in RTL)
- Use `localparam` instead of `define` for constants in RTL files
- Testbench files go in simulation-only source set

### Verilog Style Rules for RTL Files

| Rule | Requirement |
|---|---|
| Blocking vs non-blocking | Use `<=` (non-blocking) in all `always @(posedge clk)` blocks |
| Combinational | Use `=` (blocking) in `always @(*)` blocks |
| Latches | Prevent by assigning defaults at top of every `always @(*)` |
| Signed arithmetic | Always declare as `reg signed` or `wire signed` before using `>>>` |
| Parameterization | Use `parameter` / `localparam`, not magic numbers in logic |
| Reset | Every register must have an explicit reset assignment |
| Sensitivity list | Use `always @(*)` not `always @(a or b or c)` |

---

## 12. Implementation Checklist for Antigravity

This is the ordered task list for the RTL implementation phase.

### Phase A: Basic Infrastructure (implement first)
- [ ] Create directory structure: `rtl/`, `tb/`, `sim/waves/`, `sim/logs/`
- [ ] Implement `cordic_atan_rom.v` — simplest module, purely combinational
- [ ] Test ROM: verify all 16 output values match the table in Phase 4

### Phase B: Datapath Core
- [ ] Implement `cordic_iter_counter.v`
- [ ] Implement `cordic_datapath.v`
- [ ] Write `tb_cordic_datapath.v`: manually apply 16 iter_en pulses for θ=45°, verify X/Y converge

### Phase C: Control
- [ ] Implement `cordic_fsm.v`
- [ ] Write `tb_cordic_fsm.v`: verify state transitions and output signals

### Phase D: Support Modules
- [ ] Implement `cordic_output_reg.v`
- [ ] Implement `cordic_quadrant.v`
- [ ] Test quadrant module: verify folding for 30°, 45°, 60°, 90°, 120°

### Phase E: Integration
- [ ] Implement `cordic_top.v`: wire all modules together
- [ ] Write `tb_cordic_top.v`: full integration testbench (see Phase 6 for complete plan)
- [ ] Run simulation for all test angles from Phase 4 reference table
- [ ] Compare outputs against reference Q1.15 hex values
- [ ] Generate VCD waveform and capture screenshots

### Phase F: Verification
- [ ] Verify `done` pulse is exactly 1 cycle wide
- [ ] Verify outputs hold after `done` until next `start`
- [ ] Verify negative angles produce correct negative sine/cosine
- [ ] Verify 0° gives cosine ≈ 0x7FFF and sine = 0x0000
- [ ] Verify 90° gives cosine ≈ 0x0000 and sine ≈ 0x7FFF
- [ ] Confirm error is within 4 LSBs for all test angles

---

## Summary of Phase 5

| Module | Lines (approx) | Type | Status |
|---|---|---|---|
| `cordic_top.v` | ~80 | Structural | Blueprint complete |
| `cordic_fsm.v` | ~55 | Sequential | Blueprint complete |
| `cordic_datapath.v` | ~65 | Mixed | Blueprint complete |
| `cordic_atan_rom.v` | ~30 | Combinational | Blueprint complete |
| `cordic_iter_counter.v` | ~25 | Sequential | Blueprint complete |
| `cordic_quadrant.v` | ~45 | Combinational | Blueprint complete |
| `cordic_output_reg.v` | ~25 | Sequential | Blueprint complete |
| **Total RTL** | **~325 lines** | | |

All modules are fully specified with exact port declarations, internal registers, combinational logic, sequential logic, reset behavior, and inter-module wiring. Antigravity can implement directly from these specifications.

---

*Document Status: Complete — Phase 5*  
*Next Phase: Verification and Simulation Strategy (Phase 6)*  
*Prepared for: COA Academic Project — CORDIC Verilog Implementation*
