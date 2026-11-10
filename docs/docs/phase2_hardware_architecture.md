# Phase 2: Hardware Architecture Definition
## CORDIC Algorithm — RTL Hardware Architecture for Sine and Cosine

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Top-Level Block Diagram](#2-top-level-block-diagram)
3. [Module Hierarchy](#3-module-hierarchy)
4. [Data Flow Diagram](#4-data-flow-diagram)
5. [Module-by-Module Specification](#5-module-by-module-specification)
6. [Signal-Level Interface Specifications](#6-signal-level-interface-specifications)
7. [Module Interaction Diagram](#7-module-interaction-diagram)
8. [Clock-Cycle-Level Execution Flow](#8-clock-cycle-level-execution-flow)
9. [Combinational vs Sequential Logic Separation](#9-combinational-vs-sequential-logic-separation)
10. [FSM State Diagram](#10-fsm-state-diagram)

---

## 1. Architecture Overview

The hardware implementation follows a **serial iterative FSM-based architecture**. A single CORDIC iteration unit is reused 16 times under FSM control, making the design compact, low-area, and easy to verify.

### Design Philosophy

- One shared CORDIC datapath executes all 16 iterations sequentially
- An FSM orchestrates loading, iteration, and output
- The arctangent ROM is indexed by the iteration counter
- All arithmetic is fixed-point (no floating-point units)
- The design is fully synchronous (single clock domain)

### Key Design Parameters (Established in Phase 1)

| Parameter | Value |
|---|---|
| X/Y register format | Q1.15 (16-bit) |
| Angle (Z) register format | Q2.14 (16-bit) |
| Internal datapath width | 18-bit (2 guard bits) |
| Number of iterations | 16 |
| Initial X₀ | 0x4DBA (≈0.60725 in Q1.15) |
| Initial Y₀ | 0x0000 |
| Arctangent ROM depth | 16 entries |
| Clock | Single synchronous clock |
| Reset | Active-high synchronous reset |

---

## 2. Top-Level Block Diagram

```
                        ┌─────────────────────────────────────────────────┐
                        │              cordic_top (Top Module)             │
                        │                                                   │
   clk  ───────────────►│                                                   │
   rst  ───────────────►│  ┌──────────┐    ┌─────────────────────────┐    │
   start ──────────────►│  │          │    │                         │    │
   angle_in[15:0] ─────►│  │  FSM /   │───►│   CORDIC Iteration      │    │
                        │  │ Control  │    │      Datapath            │    │
                        │  │  Unit    │◄───│                         │    │
                        │  │          │    │  ┌─────┐  ┌──────────┐  │    │
                        │  └────┬─────┘    │  │X Reg│  │ Shift &  │  │    │
                        │       │          │  │Y Reg│  │  Add     │  │    │
                        │       │          │  │Z Reg│  │  Unit    │  │    │
                        │       │          │  └─────┘  └──────────┘  │    │
                        │       │          │                         │    │
                        │       │          │  ┌──────────────────┐   │    │
                        │       └─────────►│  │  Iteration       │   │    │
                        │                  │  │  Counter [3:0]   │   │    │
                        │                  │  └──────────────────┘   │    │
                        │                  │                         │    │
                        │                  │  ┌──────────────────┐   │    │
                        │                  │  │  Arctangent ROM  │   │    │
                        │                  │  │  (16 × 16-bit)   │   │    │
                        │                  │  └──────────────────┘   │    │
                        │                  └─────────────────────────┘    │
                        │                                                   │
                        │  ┌──────────────────────────────────────────┐   │
                        │  │         Output Register Block            │   │
                        │  │   sine_out[15:0]    cosine_out[15:0]     │   │
                        │  └──────────────────────────────────────────┘   │
                        │                                                   │
   done ◄───────────────│                                                   │
   sine_out[15:0] ◄─────│                                                   │
   cosine_out[15:0] ◄───│                                                   │
                        └─────────────────────────────────────────────────┘
```

---

## 3. Module Hierarchy

```
cordic_top
├── cordic_fsm              (Control Unit / FSM)
├── cordic_datapath         (CORDIC Iteration Unit)
│   ├── cordic_atan_rom     (Arctangent Lookup Table)
│   ├── cordic_shifter      (Arithmetic Right Shift Unit)
│   └── cordic_addsub       (Add/Subtract Unit)
├── cordic_iter_counter     (Iteration Counter)
└── cordic_output_reg       (Output Register Block)
```

### Module Responsibilities

| Module | Type | Primary Function |
|---|---|---|
| `cordic_top` | Structural | Wires all sub-modules, top-level I/O |
| `cordic_fsm` | Sequential | State machine — controls load/iterate/done |
| `cordic_datapath` | Mixed | X/Y/Z register update logic, one iteration |
| `cordic_atan_rom` | Combinational | Returns arctan(2⁻ⁱ) for iteration index i |
| `cordic_shifter` | Combinational | Performs arithmetic right shift by i bits |
| `cordic_addsub` | Combinational | Adds or subtracts based on σ (sigma) control |
| `cordic_iter_counter` | Sequential | Counts 0 to 15, signals completion at 16 |
| `cordic_output_reg` | Sequential | Latches final X, Y into output ports |

---

## 4. Data Flow Diagram

```
  INPUTS
  ──────
  angle_in[15:0]          start
       │                    │
       ▼                    ▼
  ┌────────────────────────────────┐
  │           cordic_fsm           │
  │  IDLE → LOAD → ITERATE → DONE  │
  └──┬─────────────┬───────────────┘
     │             │
     │load_en      │iter_en
     ▼             ▼
  ┌────────────────────────────────────────────────────────┐
  │                    cordic_datapath                      │
  │                                                         │
  │  On LOAD:                                               │
  │    X_reg ← X0_CONST (0x4DBA)                           │
  │    Y_reg ← 0                                            │
  │    Z_reg ← angle_in                                     │
  │                                                         │
  │  On ITERATE (each clock):                               │
  │                                                         │
  │    sigma  = sign(Z_reg)    ──────────────────────────┐  │
  │                                                       │  │
  │    X_shift = X_reg >>> iter_count ──────────────────┐│  │
  │    Y_shift = Y_reg >>> iter_count ────────────────┐ ││  │
  │                                                    │ ││  │
  │    atan_val = ROM[iter_count]  ────────────────┐   │ ││  │
  │                                                │   │ ││  │
  │    X_next = X_reg - sigma × Y_shift ◄──────────┼───┘ ││  │
  │    Y_next = Y_reg + sigma × X_shift ◄──────────┼─────┘│  │
  │    Z_next = Z_reg - sigma × atan_val ◄──────────┘      │  │
  │                                                         │  │
  │    X_reg ← X_next                                       │  │
  │    Y_reg ← Y_next                                       │  │
  │    Z_reg ← Z_next                                       │  │
  │                                                         │  │
  │    iter_count ← iter_count + 1  ◄───────────────────────┘  │
  │                                                         │
  └──────────────────────────┬──────────────────────────────┘
                             │  (when iter_count == 16)
                             ▼
  ┌──────────────────────────────────────┐
  │         cordic_output_reg            │
  │   cosine_out ← X_reg (Q1.15)         │
  │   sine_out   ← Y_reg (Q1.15)         │
  └───────────────┬──────────────────────┘
                  │
                  ▼
         OUTPUTS: sine_out, cosine_out, done
```

---

## 5. Module-by-Module Specification

---

### 5.1 Module: `cordic_top`

**Purpose:** Top-level structural module. Instantiates and interconnects all sub-modules. Exposes the primary interface to the outside world.

**Type:** Structural (no logic of its own — purely wiring)

**Inputs:**

| Port | Width | Direction | Description |
|---|---|---|---|
| `clk` | 1 | Input | System clock |
| `rst` | 1 | Input | Active-high synchronous reset |
| `start` | 1 | Input | Pulse to begin computation |
| `angle_in` | 16 | Input | Input angle in Q2.14 fixed-point |

**Outputs:**

| Port | Width | Direction | Description |
|---|---|---|---|
| `done` | 1 | Output | High for one cycle when result is valid |
| `sine_out` | 16 | Output | sin(θ) in Q1.15 fixed-point |
| `cosine_out` | 16 | Output | cos(θ) in Q1.15 fixed-point |

**Internal Wires (interconnects):**

```
load_en        — FSM → datapath: load initial values
iter_en        — FSM → datapath: perform one iteration
iter_count[3:0] — counter → datapath + ROM: current iteration index
sigma          — datapath → addsub: rotation direction (+1/-1)
atan_val[15:0] — ROM → datapath: arctan(2^-i) for current i
x_reg[17:0]    — datapath internal: X register (18-bit)
y_reg[17:0]    — datapath internal: Y register (18-bit)
z_reg[17:0]    — datapath internal: Z register (18-bit)
done_flag      — counter → FSM: all 16 iterations complete
```

---

### 5.2 Module: `cordic_fsm`

**Purpose:** Controls the overall sequencing of the CORDIC computation — when to load inputs, when to iterate, and when to signal completion.

**Type:** Sequential (registered state, combinational next-state logic)

**States:**

| State | Encoding | Description |
|---|---|---|
| `IDLE` | 2'b00 | Waiting for `start` signal |
| `LOAD` | 2'b01 | Load X₀, Y₀, Z₀ into registers |
| `ITERATE` | 2'b10 | Execute iterations (16 cycles) |
| `DONE` | 2'b11 | Assert `done`, return to IDLE |

**Inputs:**

| Port | Width | Description |
|---|---|---|
| `clk` | 1 | Clock |
| `rst` | 1 | Reset |
| `start` | 1 | Begin trigger |
| `iter_done` | 1 | All 16 iterations finished |

**Outputs:**

| Port | Width | Description |
|---|---|---|
| `load_en` | 1 | Enable register loading |
| `iter_en` | 1 | Enable one iteration step |
| `cnt_rst` | 1 | Reset the iteration counter |
| `out_latch` | 1 | Latch output registers |
| `done` | 1 | Computation complete |

**State Transition Logic:**

```
IDLE    → LOAD      when start = 1
LOAD    → ITERATE   always (next cycle after load)
ITERATE → DONE      when iter_done = 1 (counter reached 16)
DONE    → IDLE      always (next cycle after done)
```

**Output table (Moore machine):**

| State | load_en | iter_en | cnt_rst | out_latch | done |
|---|---|---|---|---|---|
| IDLE | 0 | 0 | 1 | 0 | 0 |
| LOAD | 1 | 0 | 1 | 0 | 0 |
| ITERATE | 0 | 1 | 0 | 0 | 0 |
| DONE | 0 | 0 | 0 | 1 | 1 |

---

### 5.3 Module: `cordic_datapath`

**Purpose:** The core CORDIC arithmetic unit. On each `iter_en` pulse, it computes one iteration of the X, Y, Z updates.

**Type:** Mixed (sequential registers + combinational update logic)

**Inputs:**

| Port | Width | Description |
|---|---|---|
| `clk` | 1 | Clock |
| `rst` | 1 | Reset |
| `load_en` | 1 | Load initial values |
| `iter_en` | 1 | Perform one iteration |
| `angle_in` | 16 | Input angle Z₀ |
| `iter_count` | 4 | Current iteration index (0–15) |
| `atan_val` | 16 | arctan(2⁻ⁱ) from ROM |

**Outputs:**

| Port | Width | Description |
|---|---|---|
| `x_out` | 16 | Final X value (cosine) after 16 iterations |
| `y_out` | 16 | Final Y value (sine) after 16 iterations |
| `sigma` | 1 | Sign of Z for current iteration |

**Internal Registers (18-bit to prevent overflow):**

```
x_reg [17:0]   — X coordinate register
y_reg [17:0]   — Y coordinate register
z_reg [17:0]   — Z angle accumulator register
```

**Constants (hardwired):**

```
X0_INIT = 18'h04DBA   // 0.60725 in Q1.15, sign-extended to 18 bits
Y0_INIT = 18'h00000
```

**Combinational Logic (each iteration):**

```
sigma    = z_reg[17]           // MSB = sign bit (0=positive, 1=negative)
                                // sigma=0 → counter-clockwise (+)
                                // sigma=1 → clockwise (-)

x_shift  = x_reg >>> iter_count  // arithmetic right shift
y_shift  = y_reg >>> iter_count

x_next   = (sigma==0) ? (x_reg - y_shift) : (x_reg + y_shift)
y_next   = (sigma==0) ? (y_reg + x_shift) : (y_reg - x_shift)
z_next   = (sigma==0) ? (z_reg - atan_val_ext) : (z_reg + atan_val_ext)
```

**Sequential Logic (clock edge):**

```
if (rst) begin
    x_reg <= 0; y_reg <= 0; z_reg <= 0;
end else if (load_en) begin
    x_reg <= X0_INIT;
    y_reg <= Y0_INIT;
    z_reg <= sign_extend(angle_in);
end else if (iter_en) begin
    x_reg <= x_next;
    y_reg <= y_next;
    z_reg <= z_next;
end
```

**Output:** `x_out` = `x_reg[15:0]`, `y_out` = `y_reg[15:0]` (truncate guard bits)

---

### 5.4 Module: `cordic_atan_rom`

**Purpose:** Stores the 16 precomputed arctangent values. Provides `arctan(2⁻ⁱ)` for iteration index `i`. This is purely combinational (asynchronous read ROM).

**Type:** Combinational (lookup table / ROM)

**Inputs:**

| Port | Width | Description |
|---|---|---|
| `addr` | 4 | Iteration index (0–15) |

**Outputs:**

| Port | Width | Description |
|---|---|---|
| `atan_val` | 16 | arctan(2⁻ᵃᵈᵈʳ) in Q2.14 |

**ROM Contents (Q2.14 fixed-point, 16384 = 2¹⁴):**

```
addr 0:  16'd12868   // arctan(1)      = 0.78540 rad
addr 1:  16'd7596    // arctan(0.5)    = 0.46365 rad
addr 2:  16'd4013    // arctan(0.25)   = 0.24498 rad
addr 3:  16'd2037    // arctan(0.125)  = 0.12435 rad
addr 4:  16'd1022    // arctan(0.0625) = 0.06242 rad
addr 5:  16'd512     // arctan(...)    = 0.03124 rad
addr 6:  16'd256     // ...            = 0.01562 rad
addr 7:  16'd128     //                = 0.00781 rad
addr 8:  16'd64      //                = 0.00391 rad
addr 9:  16'd32      //                = 0.00195 rad
addr 10: 16'd16      //                = 0.00098 rad
addr 11: 16'd8       //                = 0.00049 rad
addr 12: 16'd4       //                = 0.00024 rad
addr 13: 16'd2       //                = 0.00012 rad
addr 14: 16'd1       //                = 0.00006 rad
addr 15: 16'd1       //                = 0.00003 rad
```

**Implementation:** `case(addr)` or `always @(*)` with 16 assignments. No clock needed.

---

### 5.5 Module: `cordic_shifter`

**Purpose:** Performs arithmetic right shift of a signed value by a variable shift amount. This is the hardware implementation of `>>> i`.

**Type:** Combinational

**Inputs:**

| Port | Width | Description |
|---|---|---|
| `data_in` | 18 | Signed value to shift |
| `shift_amt` | 4 | Shift amount (0–15) |

**Outputs:**

| Port | Width | Description |
|---|---|---|
| `data_out` | 18 | Arithmetic right-shifted result |

**Implementation:** Use a barrel shifter or Verilog's `>>>` operator on a `signed` type:

```verilog
assign data_out = $signed(data_in) >>> shift_amt;
```

**Note on arithmetic shift:** For negative numbers, the sign bit (MSB) is replicated as bits are shifted right. This preserves the sign of the number and is equivalent to division by 2ⁿ with floor rounding.

---

### 5.6 Module: `cordic_addsub`

**Purpose:** Performs signed addition or subtraction based on the `sigma` control signal. Shared logic for all three register updates (X, Y, Z).

**Type:** Combinational

**Inputs:**

| Port | Width | Description |
|---|---|---|
| `operand_a` | 18 | First operand (base register value) |
| `operand_b` | 18 | Second operand (shifted value or atan) |
| `sigma` | 1 | 0 = subtract B from A; 1 = add B to A |

Wait — to match CORDIC equations exactly, the control is:

```
X update: sigma=0 → X - Y_shift;  sigma=1 → X + Y_shift
Y update: sigma=0 → Y + X_shift;  sigma=1 → Y - X_shift
Z update: sigma=0 → Z - atan;     sigma=1 → Z + atan
```

In implementation, this is handled directly in the datapath combinational block rather than a separate add/sub module. The `cordic_addsub` is therefore abstracted as part of the datapath.

---

### 5.7 Module: `cordic_iter_counter`

**Purpose:** Counts iterations from 0 to 15. Provides current iteration index to the datapath and ROM. Asserts `iter_done` when count reaches 16.

**Type:** Sequential

**Inputs:**

| Port | Width | Description |
|---|---|---|
| `clk` | 1 | Clock |
| `rst` | 1 | Reset |
| `cnt_rst` | 1 | Counter reset from FSM |
| `iter_en` | 1 | Count enable |

**Outputs:**

| Port | Width | Description |
|---|---|---|
| `count` | 4 | Current iteration (0–15) |
| `iter_done` | 1 | High when count == 15 (last iteration done) |

**Behavior:**

```
if (rst || cnt_rst):  count ← 0
else if (iter_en):    count ← count + 1
iter_done = (count == 4'd15) && iter_en
```

---

### 5.8 Module: `cordic_output_reg`

**Purpose:** Latches the final X and Y register values when computation is complete. Holds the output stable while FSM returns to IDLE.

**Type:** Sequential

**Inputs:**

| Port | Width | Description |
|---|---|---|
| `clk` | 1 | Clock |
| `rst` | 1 | Reset |
| `out_latch` | 1 | Latch enable from FSM (DONE state) |
| `x_in` | 16 | X register value (cosine) |
| `y_in` | 16 | Y register value (sine) |

**Outputs:**

| Port | Width | Description |
|---|---|---|
| `cosine_out` | 16 | Latched cosine value |
| `sine_out` | 16 | Latched sine value |

**Behavior:**

```
if (rst):          cosine_out ← 0; sine_out ← 0
else if (out_latch): cosine_out ← x_in; sine_out ← y_in
```

---

## 6. Signal-Level Interface Specifications

### 6.1 Complete Signal List: `cordic_top`

```
// External Ports
input  wire        clk          // System clock (50 MHz or simulation)
input  wire        rst          // Synchronous active-high reset
input  wire        start        // Pulse: begin computation
input  wire [15:0] angle_in     // Input angle, Q2.14 fixed-point
output reg         done         // Computation complete (one cycle pulse)
output reg  [15:0] sine_out     // sin(θ), Q1.15 fixed-point
output reg  [15:0] cosine_out   // cos(θ), Q1.15 fixed-point

// Internal Control Signals
wire        load_en    // FSM → datapath: load initial conditions
wire        iter_en    // FSM → datapath + counter: do one iteration
wire        cnt_rst    // FSM → counter: reset count
wire        out_latch  // FSM → output reg: latch final result
wire        iter_done  // Counter → FSM: all iterations done

// Internal Data Signals
wire [3:0]  iter_count  // Counter → ROM + datapath: iteration index
wire [15:0] atan_val    // ROM → datapath: arctan(2^-i)
wire [17:0] x_dp        // Datapath → output reg (internal X)
wire [17:0] y_dp        // Datapath → output reg (internal Y)
```

### 6.2 Fixed-Point Encoding Reference

| Signal | Format | Range | Resolution |
|---|---|---|---|
| `angle_in` | Q2.14 | ±1.9999 rad (~±114°) | 6.1e-5 rad |
| `sine_out` | Q1.15 | ±0.9999 | 3.05e-5 |
| `cosine_out` | Q1.15 | ±0.9999 | 3.05e-5 |
| Internal X/Y | Q1.17 (18-bit) | ±0.9999 + guard | ~7.6e-6 |
| Internal Z | Q2.16 (18-bit) | ±1.9999 | ~1.5e-5 |

### 6.3 Timing Constraints

| Parameter | Value |
|---|---|
| Clock period | 20 ns (50 MHz) |
| Reset assertion | Minimum 2 clock cycles |
| Start pulse | Minimum 1 clock cycle |
| Latency from start to done | 18 clock cycles (1 LOAD + 16 ITERATE + 1 DONE) |
| Output valid | On `done` high and held until next `start` |

---

## 7. Module Interaction Diagram

```
         ┌──────────────────────────────────────────────────────────────┐
         │                                                              │
  start ─►  cordic_fsm                                                  │
         │   │                                                          │
         │   ├── load_en ─────────────────────► cordic_datapath         │
         │   ├── iter_en ──────────┬───────────► (X,Y,Z update logic)  │
         │   ├── cnt_rst ─────────►│             │                      │
         │   └── out_latch ──────────────────────────► cordic_output_reg│
         │                        │             │                      │
         │                        ▼             │                      │
         │               cordic_iter_counter    │                      │
         │                  │ count[3:0] ───────►(shift amount)        │
         │                  │ count[3:0] ───────────────────────────►  │
         │                  │                   │      cordic_atan_rom  │
         │                  │                   │         │             │
         │                  │                   │◄ atan_val[15:0] ──────┘
         │                  │                   │                      │
         │                  └── iter_done ──────► cordic_fsm (back)     │
         │                                                              │
         └──────────────────────────────────────────────────────────────┘
```

### Signal Flow Summary

```
clk, rst         → ALL modules
start            → cordic_fsm
angle_in         → cordic_datapath (registered on load_en)
load_en          → cordic_datapath
iter_en          → cordic_datapath, cordic_iter_counter
cnt_rst          → cordic_iter_counter
iter_count[3:0]  → cordic_datapath (shift amount), cordic_atan_rom (address)
atan_val[15:0]   → cordic_datapath
iter_done        → cordic_fsm
out_latch        → cordic_output_reg
x_dp[17:0]       → cordic_output_reg
y_dp[17:0]       → cordic_output_reg
done             → external
sine_out         → external
cosine_out       → external
```

---

## 8. Clock-Cycle-Level Execution Flow

### Waveform Timeline

```
Cycle:   1      2      3      4 ... 19     20     21
         │      │      │      │ ...  │      │      │
clk:  ─┐_┌─┐_┌─┐_┌─┐_┌─┐... ─┐_┌─┐_┌─┐_┌─┐_
         │      │      │      │       │      │
start:   ┌┐
         ──┘└──────────────────────────────────

State:  IDLE  LOAD  ITER  ITER ... ITER  DONE  IDLE
               i=0   i=1  i=2   i=15

load_en: ──┌──┐──────────────────────────────
iter_en: ─────┌──┬──┬── ... ──┬──┐──────────
               i0 i1  i2      i15

iter_count:  x   0   1   2  ...  14  15   x

atan_val: valid for each iter_count

x_reg: X0  →  X1  →  X2  → ... →  X16
y_reg: 0   →  Y1  →  Y2  → ... →  Y16
z_reg: θ   →  Z1  →  Z2  → ... →  Z16≈0

out_latch: ──────────────────────────┌──┐──
done:      ──────────────────────────┌──┐──

sine_out:  valid ─────────────────────────►
cosine_out:valid ─────────────────────────►
```

### Cycle-by-Cycle Description

| Cycle | FSM State | Action |
|---|---|---|
| 1 | IDLE | Waiting. `start` arrives. |
| 2 | LOAD | X_reg←X0, Y_reg←0, Z_reg←angle_in. cnt_rst=1. |
| 3 | ITERATE | i=0: compute X₁,Y₁,Z₁ from X₀,Y₀,Z₀ using atan[0] |
| 4 | ITERATE | i=1: compute X₂,Y₂,Z₂ from X₁,Y₁,Z₁ using atan[1] |
| 5 | ITERATE | i=2: ... |
| ... | ... | ... |
| 18 | ITERATE | i=15: compute X₁₆,Y₁₆,Z₁₆. iter_done=1. |
| 19 | DONE | out_latch=1: capture X₁₆→cosine, Y₁₆→sine. done=1. |
| 20 | IDLE | Back to idle. Outputs remain valid. |

**Total latency: 19 clock cycles from start to valid output (18 cycles computation + 1 cycle output latch).**

---

## 9. Combinational vs Sequential Logic Separation

### Sequential Logic (Clocked, Flip-Flop based)

| Component | What is Registered |
|---|---|
| FSM state register | `state[1:0]` |
| X register | `x_reg[17:0]` |
| Y register | `y_reg[17:0]` |
| Z register | `z_reg[17:0]` |
| Iteration counter | `count[3:0]` |
| Output registers | `sine_out[15:0]`, `cosine_out[15:0]` |
| Done flip-flop | `done` |

### Combinational Logic (No clock, purely logical)

| Component | What it Computes |
|---|---|
| Arctangent ROM | `atan_val = f(iter_count)` |
| Shifter | `x_shift = x_reg >>> count`, `y_shift = y_reg >>> count` |
| Sigma detection | `sigma = z_reg[17]` (MSB is sign bit) |
| X next-state logic | `x_next = x_reg ± y_shift` |
| Y next-state logic | `y_next = y_reg ± x_shift` |
| Z next-state logic | `z_next = z_reg ± atan_val` |
| FSM next-state | `next_state = f(state, start, iter_done)` |
| FSM output decode | `load_en, iter_en, etc. = f(state)` |
| iter_done | `(count == 4'd15) && iter_en` |

---

## 10. FSM State Diagram

```
                          rst=1
                            │
                            ▼
                    ┌───────────────┐
               ┌──► │     IDLE      │ ◄────────┐
               │    │  (cnt_rst=1)  │          │
               │    └──────┬────────┘          │
               │           │ start=1           │
               │           ▼                   │
               │    ┌───────────────┐          │
               │    │     LOAD      │          │
               │    │  (load_en=1,  │          │
               │    │   cnt_rst=1)  │          │
               │    └──────┬────────┘          │
               │           │ (next cycle)      │
               │           ▼                   │
               │    ┌───────────────┐          │
               │    │    ITERATE    │          │
               │    │  (iter_en=1)  │──┐       │
               │    └──────┬────────┘  │       │
               │           │           │iter_done=0
               │           │iter_done=1│(stay) │
               │           ▼           └───────┘
               │    ┌───────────────┐
               │    │     DONE      │
               │    │ (out_latch=1, │
               │    │   done=1)     │
               │    └──────┬────────┘
               │           │ (next cycle)
               └───────────┘
```

**Key properties of this FSM:**
- **Moore machine** — outputs depend only on current state, not inputs
- **4 states** — encoded in 2 bits
- **Deterministic** — no combinational loops, no hazards
- **Self-resetting** — DONE always returns to IDLE in one cycle

---

## Summary of Phase 2

| Decision | Value |
|---|---|
| Architecture type | Serial iterative FSM |
| Number of modules | 6 leaf + 1 top = 7 total |
| Total latency | 19 clock cycles |
| FSM type | Moore, 4-state, 2-bit encoding |
| Datapath width | 18-bit internal, 16-bit outputs |
| ROM size | 16 × 16-bit = 256 bits |
| Reset type | Synchronous active-high |
| Clock domains | Single (fully synchronous) |
| Handshake | start (input pulse), done (output pulse) |

---

*Document Status: Complete — Phase 2*  
*Next Phase: Implementation Strategy Selection (Phase 3)*  
*Prepared for: COA Academic Project — CORDIC Verilog Implementation*
