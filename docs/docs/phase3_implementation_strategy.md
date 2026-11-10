# Phase 3: Implementation Strategy Selection
## CORDIC Algorithm — Design Decisions, Trade-off Analysis, and Final Configuration

---

## Table of Contents

1. [Decision 1: Operating Mode](#1-decision-1-operating-mode)
2. [Decision 2: Fixed-Point Representation (Q-Format)](#2-decision-2-fixed-point-representation-q-format)
3. [Decision 3: Input Angle Representation](#3-decision-3-input-angle-representation)
4. [Decision 4: Internal Precision and Bit Width](#4-decision-4-internal-precision-and-bit-width)
5. [Decision 5: Number of CORDIC Iterations](#5-decision-5-number-of-cordic-iterations)
6. [Decision 6: Signed Arithmetic Strategy](#6-decision-6-signed-arithmetic-strategy)
7. [Decision 7: Arithmetic Right Shift Implementation](#7-decision-7-arithmetic-right-shift-implementation)
8. [Decision 8: Gain Compensation Strategy](#8-decision-8-gain-compensation-strategy)
9. [Decision 9: FSM vs Pipelined Architecture](#9-decision-9-fsm-vs-pipelined-architecture)
10. [Decision 10: Reset and Initialization Strategy](#10-decision-10-reset-and-initialization-strategy)
11. [Decision 11: Quadrant Handling Strategy](#11-decision-11-quadrant-handling-strategy)
12. [Final Configuration Summary](#12-final-configuration-summary)
13. [Trade-off Summary Table](#13-trade-off-summary-table)

---

## 1. Decision 1: Operating Mode

### Options Considered

**Option A: Rotation Mode**
- Start with a known vector `(X₀, Y₀)` and a target angle `Z₀`
- Rotate the vector until `Z → 0`
- Outputs: `X = cos(θ)`, `Y = sin(θ)`

**Option B: Vectoring Mode**
- Start with an arbitrary vector `(X₀, Y₀)`
- Drive `Y → 0`
- Outputs: `X = magnitude`, `Z = arctan(Y/X)`
- Used for: phase detection, polar conversion, inverse tangent

### Trade-offs

| Criterion | Rotation Mode | Vectoring Mode |
|---|---|---|
| Purpose | sin/cos from angle | atan, magnitude from vector |
| Input | scalar angle θ | 2D vector (X₀, Y₀) |
| HW complexity | Same | Same |
| Useful for this project | Yes | No |

### Decision: **Rotation Mode**

Rotation mode directly computes `sin(θ)` and `cos(θ)` from an input angle. This is the primary deliverable of the project. Vectoring mode would require a different input interface and produces different outputs.

---

## 2. Decision 2: Fixed-Point Representation (Q-Format)

### Background

CORDIC requires:
- Data registers (X, Y) to hold values in range [-1.0, +1.0]
- Angle register (Z) to hold values in range [-π/2, +π/2] ≈ [-1.5708, +1.5708]

### Options for X/Y Data Registers

**Option A: Q0.15 (1 sign bit + 15 fractional bits = 16-bit)**
- Range: [-1.0, +0.999969]
- Resolution: 3.05 × 10⁻⁵
- Problem: cannot represent exactly +1.0; limited headroom

**Option B: Q1.15 (1 integer+sign bit + 15 fractional bits = 16-bit)**
- Range: [-2.0, +1.999969]
- Resolution: 3.05 × 10⁻⁵
- Sufficient range for [-1, +1], with slight headroom

**Option C: Q1.14 (16-bit with less fractional precision)**
- Range: wider, but resolution drops to 6.1 × 10⁻⁵
- Less precise output — not preferred

### Decision for X/Y: **Q1.15**

Q1.15 is the industry-standard choice for fixed-point DSP and CORDIC. The MSB acts as sign+integer, the remaining 15 bits are fractional. Values are stored as 16-bit 2's complement integers. Resolution ≈ 3.05e-5 is sufficient for this academic project.

Formula: `real_value = integer_value / 32768`

### Options for Angle Register (Z)

**Option A: Q2.14 (16-bit)**
- Range: [-2.0, +1.99994]
- Can represent ±π/2 ≈ ±1.5708 comfortably
- Resolution: 6.1 × 10⁻⁵ rad ≈ 0.0035°

**Option B: Q1.15 (same as data)**
- Range: [-2.0, +1.99969]
- Slightly higher resolution
- Requires careful scaling since angle and data are mixed

**Option C: Degrees-based representation (integer)**
- Range 0–359 directly; easy to understand
- Loses precision; requires degree-to-radian conversion in hardware
- Non-standard for CORDIC

### Decision for Z: **Q2.14**

Q2.14 provides adequate range and precision for the angle register. The higher integer range (vs Q1.15) is necessary because intermediate Z values during the arctangent subtraction can briefly exceed ±1.0 before converging.

Formula: `real_angle_rad = integer_value / 16384`

---

## 3. Decision 3: Input Angle Representation

### Problem

Users typically think in degrees (0°–360°). Hardware prefers radians. We need a clean, unambiguous interface.

### Options

**Option A: Input in radians as Q2.14**
- Direct feed into CORDIC Z register
- No conversion needed
- Less intuitive for manual testbench writing

**Option B: Input in degrees as integer (0–359)**
- Intuitive for manual testing
- Requires a degree-to-radian conversion unit in hardware
- Adds logic, introduces rounding error

**Option C: Input as Q2.14 radians, normalized to [-π/2, +π/2] by user**
- Simplest hardware: no conversion, no quadrant logic internally
- Restricts input range; quadrant handling must be done externally or documented as a limitation

**Option D: Input in Q2.14 with built-in quadrant correction (full ±π range)**
- Accepts any angle in [-π, +π]
- Hardware detects quadrant and corrects inputs/outputs
- Best overall solution for practical use

### Decision: **Q2.14 radians with quadrant correction**

For this academic project, input is accepted as a **16-bit Q2.14 signed integer representing radians**. A lightweight quadrant correction block handles angles in the full range [-π, +π]. Angles outside this range are considered out-of-spec (documented limitation).

**Input encoding examples:**

| Angle | Radians | Q2.14 Integer | Hex |
|---|---|---|---|
| 0° | 0.0000 | 0 | 0x0000 |
| 30° | 0.5236 | 8581 | 0x2185 |
| 45° | 0.7854 | 12868 | 0x3244 |
| 60° | 1.0472 | 17157 | 0x4305 |
| 90° | 1.5708 | 25736 | 0x6488 |
| 120° | 2.0944 | 34315 | 0x860B |
| 180° | 3.1416 | 51472 | 0xC910 |
| -45° | -0.7854 | -12868 | 0xCDBC |
| -90° | -1.5708 | -25736 | 0x9B78 |

---

## 4. Decision 4: Internal Precision and Bit Width

### Problem

CORDIC intermediate values (X, Y, Z during iteration) can temporarily exceed the range of the Q1.15 format due to accumulated partial rotations. Without extra bits, this causes **overflow**, corrupting the computation.

### Analysis

The intermediate X and Y values during CORDIC stay bounded by approximately ±1.65 (the CORDIC gain factor). With Q1.15 (range ±2.0), this is technically within range, but to provide safety margin and avoid rounding errors propagating, the standard practice is to add **guard bits**.

### Options

**Option A: 16-bit throughout (no guard bits)**
- Risk of overflow at iteration 0 where X jumps from ~0.607 toward ~0.858
- Acceptable only if input is tightly constrained
- Not recommended for robust design

**Option B: 18-bit internal, 16-bit output (2 guard bits)**
- Internal registers are 18-bit: format is Q3.15 (3 integer bits + 15 fractional)
- Overflow headroom: range ±4.0 — more than sufficient
- Output is truncated to 16-bit at the end
- Adds minimal hardware (2 extra bits per register)
- Industry-standard approach

**Option C: 20-bit internal, 16-bit output (4 guard bits)**
- Overkill for this application
- Wastes area

### Decision: **18-bit internal datapath, 16-bit outputs**

Two guard bits provide ample overflow protection while keeping the design lean. All three registers (X, Y, Z) are 18-bit internally. The iteration counter and shift amounts remain 4-bit. Outputs are taken as `[15:0]` of the 18-bit registers (sign-extended Q1.15 equivalent).

**Internal register formats:**

| Register | Width | Format | Range |
|---|---|---|---|
| X_reg | 18-bit | Q3.15 | ±4.0 |
| Y_reg | 18-bit | Q3.15 | ±4.0 |
| Z_reg | 18-bit | Q4.14 | ±8.0 |

---

## 5. Decision 5: Number of CORDIC Iterations

### Relationship Between Iterations and Precision

The error in CORDIC output after N iterations is approximately:

```
error ≈ 2^(-(N-1))
```

For Q1.15 (15 fractional bits), the LSB has weight `2⁻¹⁵`. There is no point running more iterations than can improve the precision beyond the LSB.

### Options

| N iterations | Approx error | Decimal digits | Hardware cost |
|---|---|---|---|
| 8 | ~0.004 | ~2 digits | Low |
| 12 | ~0.0002 | ~3 digits | Medium |
| 16 | ~0.000015 | ~4–5 digits | Medium |
| 20 | ~0.0000009 | ~6 digits | High (exceeds 16-bit precision) |
| 24 | diminishing returns | ~7 digits | Too high |

### Decision: **N = 16 iterations**

16 iterations gives error ≈ 1.5 × 10⁻⁵, which matches the resolution of 16-bit Q1.15 format (LSB ≈ 3.05 × 10⁻⁵). Running more than 16 iterations with 16-bit registers adds no benefit — the extra precision is lost in truncation.

16 also aligns cleanly with a 4-bit counter (counts 0–15).

**Latency:** 16 iterations + 1 load + 1 output = **18 active clock cycles, 19 total from start pulse.**

---

## 6. Decision 6: Signed Arithmetic Strategy

### Options

**Option A: Sign-Magnitude representation**
- Separate sign bit and magnitude
- Simple to understand conceptually
- Awkward to add/subtract; requires extra logic to handle sign

**Option B: 2's Complement**
- Standard binary representation for signed integers
- Addition and subtraction are identical operations regardless of sign
- Right shift of negative numbers automatically replicates sign bit (arithmetic shift)
- Natively supported by all synthesis tools and Verilog

**Option C: 1's Complement**
- Two representations of zero (+0 and -0)
- Never used in modern digital design

### Decision: **2's Complement throughout**

2's complement is the universal standard for signed arithmetic in digital hardware. It eliminates the need for separate sign handling in the adder, simplifies the shift unit (arithmetic right shift is built-in), and is directly supported by Verilog's `signed` type system.

**CORDIC sigma control in 2's complement:**
```
sigma = z_reg[MSB]
// MSB = 0 → Z is positive → rotate CCW (σ = +1)
// MSB = 1 → Z is negative → rotate CW  (σ = -1)
```

---

## 7. Decision 7: Arithmetic Right Shift Implementation

### Problem

The CORDIC iteration requires shifting X and Y right by `i` positions (`>>> i`). For negative numbers in 2's complement, this must be an **arithmetic shift** (sign bit replicated), not a logical shift (zeros inserted).

Incorrect: `1111_0000 >> 2 = 0011_1100` (logical — wrong for negatives)
Correct:   `1111_0000 >>> 2 = 1111_1100` (arithmetic — correct)

### Options

**Option A: Use Verilog `signed` cast with `>>>` operator**
```verilog
assign x_shift = $signed(x_reg) >>> iter_count;
```
- Cleanest approach
- Relies on synthesis tool to correctly infer arithmetic shift
- Works in all modern tools (Xilinx Vivado, Intel Quartus, ModelSim, Icarus)

**Option B: Manual sign extension**
```verilog
// Manually replicate sign bit before shifting
wire [35:0] extended = {{18{x_reg[17]}}, x_reg};
assign x_shift = extended[35:18] >> iter_count;
```
- More verbose, error-prone
- Not recommended unless tool support is uncertain

**Option C: Parameterized barrel shifter module**
- Overkill for this design
- Adds unnecessary complexity

### Decision: **Verilog `$signed()` cast with `>>>` operator**

This is the standard synthesizable approach. The synthesis tool generates the correct arithmetic right shift hardware (which, for fixed shifts, is literally just rewiring — no actual gates needed for the shift itself).

**Critical rule in Verilog:** Always cast to `signed` before using `>>>`. Without the cast, `>>>` may behave as a logical shift on `wire` or `reg` types.

```verilog
// CORRECT:
wire signed [17:0] x_reg_s = x_reg;
wire signed [17:0] x_shift = x_reg_s >>> iter_count;

// INCORRECT (if x_reg is unsigned reg):
wire [17:0] x_shift = x_reg >>> iter_count;  // may not sign-extend
```

---

## 8. Decision 8: Gain Compensation Strategy

### Problem

Each CORDIC pseudo-rotation introduces a scale factor. After N iterations, the output is scaled by:

```
Kₙ ≈ 1.64676   (for N=16)
```

So without correction: `X_final ≈ 1.64676 × cos(θ)`, not `cos(θ)`.

We must divide by Kₙ (or equivalently, multiply by 1/Kₙ ≈ 0.60725).

### Options

**Option A: Pre-scale the initial X₀ (multiply once at the start)**
- Set `X₀ = 1/Kₙ ≈ 0.60725` instead of `X₀ = 1.0`
- The gain is absorbed into the initial condition
- No post-processing needed
- Hardware: just change the hardwired constant loaded into X_reg

**Option B: Post-scale the final output (multiply at the end)**
- Run CORDIC with `X₀ = 1.0`
- After iteration 16: `cosine_out = X_final × (1/Kₙ)`
- Requires a multiplier (expensive hardware)

**Option C: Ignore gain (no compensation)**
- Output is scaled by Kₙ
- Application layer must know this and compensate
- Acceptable only if Kₙ is documented clearly

**Option D: Partial gain correction (mix of iterations)**
- Some CORDIC implementations insert extra "dummy" rotations with δᵢ=0 to reach exactly the desired gain
- Complex, not needed for academic project

### Decision: **Pre-scale X₀ — Option A**

This is the canonical CORDIC approach. Load `X₀ = 0x4DBA` (Q1.15 representation of 0.60725) instead of `0x7FFF` (1.0). The gain is transparently compensated with zero additional hardware cost.

**The hardware constant:**
```verilog
parameter X0_INIT = 18'sh04DBA;  // 0.60725 in Q1.15, sign-extended to 18-bit
parameter Y0_INIT = 18'sh00000;
```

**Verification:** After 16 iterations with `θ = 0°`:
- Expected: `cos(0) = 1.0`, `sin(0) = 0.0`
- With pre-scaling: `X_final = 0.60725 × Kₙ = 0.60725 × 1.64676 ≈ 1.0` ✓

---

## 9. Decision 9: FSM vs Pipelined Architecture

### Option A: Serial Iterative FSM Architecture (Proposed)

A single CORDIC datapath is reused for all N iterations under FSM control.

```
Latency:      N + overhead clock cycles per result
Throughput:   1 result per N cycles
Area:         1× datapath + FSM + counter
Power:        Lower (single datapath)
```

**Pros:**
- Compact, low area
- Easy to understand and debug
- Natural for academic projects
- One clock cycle per iteration — easy to trace in simulation
- 16 iterations → deterministic latency

**Cons:**
- Not high-throughput (one result at a time)
- Cannot start a new computation until current one finishes

---

### Option B: Pipelined Architecture

Each of the N stages has its own dedicated datapath. All stages operate simultaneously on different inputs.

```
Latency:      N clock cycles for first result, then 1 result per cycle
Throughput:   1 result per clock cycle (after initial fill)
Area:         N× datapath (much larger)
Power:        Higher (all stages active always)
```

**Pros:**
- Maximum throughput (1 result/cycle after pipeline filled)
- Ideal for streaming applications (SDR, signal processing)

**Cons:**
- 16× more hardware (16 copies of X/Y/Z registers and arithmetic)
- Harder to debug — 16 independent pipeline stages
- Excessive complexity for an academic project
- Impractical for FPGA lab demos

---

### Option C: Unrolled Combinational Architecture

All 16 iterations computed in a single massive combinational block.

```
Latency:      Sub-clock (purely combinational)
Throughput:   Continuous (new result every cycle with registered I/O)
Area:         Same as pipeline but with longer critical path
```

**Pros:** Lowest latency

**Cons:**
- Very long combinational chain → may violate timing at higher clock frequencies
- Impossible to pipeline externally
- Debugging is extremely difficult
- Not synthesizable at high clock speeds

---

### Decision: **Serial Iterative FSM Architecture**

For an academic COA project with the goal of clear demonstration, simulation, and viva explanation:

- The FSM approach maps directly to textbook CORDIC descriptions
- Each iteration is visible in waveforms as a separate clock cycle
- Only one copy of the arithmetic unit needed — much easier to explain
- Latency of 19 cycles is perfectly acceptable for an academic demo
- Straightforward RTL synthesis on any FPGA or simulator

The pipelined version, while impressive, obscures the fundamental operation and is over-engineered for a COA course project.

---

## 10. Decision 10: Reset and Initialization Strategy

### Options

**Option A: Asynchronous reset**
- Registers clear immediately when `rst=1`, regardless of clock
- Good for FPGAs where power-up state is undefined
- Slightly harder to analyze timing in synthesis

**Option B: Synchronous reset**
- Registers clear on the **next rising clock edge** when `rst=1`
- Cleaner timing analysis
- Industry-standard for FPGA-targeted designs (Xilinx/Intel both prefer synchronous)
- More predictable simulation behavior

### Decision: **Synchronous active-high reset**

```verilog
always @(posedge clk) begin
    if (rst) begin
        // clear all registers
    end else begin
        // normal operation
    end
end
```

On reset, all registers go to 0 (including X₀ — the computation only loads X₀ when `load_en` asserts, not at reset). This prevents spurious outputs from appearing at power-up.

---

## 11. Decision 11: Quadrant Handling Strategy

### The Problem

CORDIC rotation mode converges only for input angles in `[-π/2, +π/2]` (i.e., ±90°).

For angles outside this range (Q2 and Q3 — 90° to 270°), the direct CORDIC iteration diverges. We need **quadrant correction**.

### Quadrant Correction Rules

```
θ in [0°, 90°]      → Q1: feed θ directly, no correction
θ in (90°, 180°]    → Q2: feed θ' = π - θ, negate cosine_out
θ in (-90°, 0°]     → Q4: feed θ directly (negative angle handled by sigma)
θ in [-180°, -90°)  → Q3: feed θ' = -π - θ, negate both outputs
```

After quadrant folding, the effective angle passed to CORDIC core is always in [-π/2, +π/2].

### Options

**Option A: Include quadrant correction in hardware (full ±π range)**
- Detect quadrant from the two MSBs of the angle input
- Fold angle and correct output accordingly
- Input range: ±π (±3.14159 radians)
- Requires a small conditional subtractor and output inversion

**Option B: No quadrant correction (restrict to ±90° input)**
- Simplest hardware
- Input range: [-π/2, +π/2] = [-90°, +90°] only
- Document this as a known limitation
- Testbench handles only angles in this range

### Decision: **Include quadrant correction for full ±π/2 range, document ±π as a future extension**

For this academic project, implement quadrant correction as a **preprocessing stage** that:
1. Detects if `|angle_in| > π/2`
2. Folds the angle into the CORDIC convergence range
3. Records a quadrant flag
4. Post-processes the output by negating as needed

This is straightforward hardware that makes the project much more complete and demonstrates a deeper understanding.

**Quadrant correction module interface:**
```
Input:  raw_angle[15:0]   (Q2.14, range [-π, +π])
Output: folded_angle[15:0] (Q2.14, range [-π/2, +π/2])
Output: quadrant[1:0]     (00=Q1, 01=Q2, 10=Q3, 11=Q4)
```

**Output correction table:**

| quadrant | cosine_final | sine_final |
|---|---|---|
| 00 (Q1, 0–90°) | +X_out | +Y_out |
| 01 (Q2, 90–180°) | -X_out | +Y_out |
| 10 (Q3, -180° to -90°) | -X_out | -Y_out |
| 11 (Q4, -90° to 0°) | +X_out | -Y_out |

---

## 12. Final Configuration Summary

This table consolidates every design decision made in Phase 3. All future implementation work must use these parameters without deviation.

| Parameter | Decision | Rationale |
|---|---|---|
| Operating mode | Rotation mode | Computes sin/cos from input angle |
| X/Y data format | Q1.15 (16-bit) | Industry standard, range ±2.0, resolution 3.05e-5 |
| Angle Z format | Q2.14 (16-bit) | Sufficient range for ±π/2 with fractional precision |
| Internal width | 18-bit (2 guard bits) | Prevents overflow during intermediate iterations |
| Input angle | Q2.14 radians, ±π range | Quadrant correction applied before CORDIC core |
| CORDIC iterations | N = 16 | Matches Q1.15 precision, 4-bit counter |
| Signed arithmetic | 2's complement | Universal standard, native Verilog support |
| Right shift | Arithmetic (`$signed()` + `>>>`) | Preserves sign for negative numbers |
| Gain compensation | Pre-scale X₀ = 0x4DBA | Zero hardware overhead, canonical method |
| Architecture | Serial iterative FSM | Compact, clear, demonstrable, debuggable |
| FSM type | Moore, synchronous, 4-state | Clean outputs, predictable behavior |
| Reset | Synchronous active-high | Industry standard for FPGA, clean timing |
| Quadrant handling | Built-in pre/post correction | Supports full ±π input range |
| Clock | Single synchronous domain | No CDC complications |
| Total latency | 19 clock cycles | 1 load + 16 iterate + 1 output + 1 overhead |
| Output format | Q1.15 (16-bit signed) | Directly usable, matches input precision |

---

## 13. Trade-off Summary Table

| Feature | Chosen Approach | Alternative | Why Not Alternative |
|---|---|---|---|
| Architecture | Serial FSM | Pipelined | Too much area, complex for academic use |
| Gain | Pre-scale X₀ | Post-multiply | Post-multiply needs hardware multiplier |
| Q-format | Q1.15 / Q2.14 | Floating-point | FP requires FPU, defeats CORDIC's purpose |
| Iterations | 16 | 8 or 24 | 8 = low precision; 24 = wasted with 16-bit |
| Shift | Arithmetic `>>>` | Logical `>>` | Logical shift wrong for negative values |
| Reset | Synchronous | Asynchronous | Sync preferred on FPGAs, cleaner timing |
| Angles | Radians (Q2.14) | Integer degrees | Degrees need hardware conversion unit |
| Range | Full ±π | ±90° only | Full range more complete, practical |

---

*Document Status: Complete — Phase 3*  
*Next Phase: Mathematical and Numerical Validation (Phase 4)*  
*Prepared for: COA Academic Project — CORDIC Verilog Implementation*
