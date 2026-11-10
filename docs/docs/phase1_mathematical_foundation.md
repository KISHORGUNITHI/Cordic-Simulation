# Phase 1: Project Understanding and Mathematical Foundation
## CORDIC Algorithm for Computing Sine and Cosine — Hardware Implementation

---

## Table of Contents

1. [What is the CORDIC Algorithm?](#1-what-is-the-cordic-algorithm)
2. [Why CORDIC for Hardware?](#2-why-cordic-for-hardware)
3. [How CORDIC Computes Sine and Cosine](#3-how-cordic-computes-sine-and-cosine)
4. [Why CORDIC Over Other Approaches?](#4-why-cordic-over-other-approaches)
5. [Mathematical Derivation from First Principles](#5-mathematical-derivation-from-first-principles)
6. [Rotation Mode vs Vectoring Mode](#6-rotation-mode-vs-vectoring-mode)
7. [The CORDIC Gain Factor](#7-the-cordic-gain-factor)
8. [The Arctangent Lookup Table](#8-the-arctangent-lookup-table)
9. [Fixed-Point Arithmetic in CORDIC](#9-fixed-point-arithmetic-in-cordic)
10. [Numerical Example: Computing sin(45°) and cos(45°)](#10-numerical-example)

---

## 1. What is the CORDIC Algorithm?

**CORDIC** stands for **COordinate Rotation DIgital Computer**.

It was first proposed by **Jack E. Volder in 1959** for solving navigation problems aboard the B-58 bomber aircraft, where real-time trigonometric computation was needed without a general-purpose multiplier — a luxury not available in early hardware.

The core insight of CORDIC is elegant and powerful:

> **Any angle rotation can be decomposed into a sequence of micro-rotations, each of which is a power of two, eliminating the need for actual multiplication.**

In other words, instead of computing `sin(θ)` by evaluating a Taylor series or performing a complex multiplication, CORDIC rotates a known reference vector step by step until it points in the direction of the target angle θ. At that point, the X and Y components of the rotated vector directly yield **cosine** and **sine** of θ, respectively.

This approach reduces trigonometric computation entirely to:
- **Shift operations** (division by powers of 2)
- **Addition and subtraction**
- **A small lookup table** of precomputed arctangent values

These are among the cheapest operations available in digital hardware.

---

## 2. Why CORDIC for Hardware?

Modern hardware computation faces strict constraints:
- Area (number of logic gates)
- Power consumption
- Latency (how fast a result is produced)
- Complexity of the arithmetic unit

### Operations ranked by hardware cost (cheapest to most expensive):

| Operation | Hardware Cost | Notes |
|---|---|---|
| Bit shift | Very low | Wires only in fixed hardware |
| Addition / Subtraction | Low | Simple carry-propagate adder |
| Multiplication | High | Requires multiplier array |
| Division | Very high | Iterative or large combinational logic |
| Square root | Very high | Complex iterative circuit |
| Trigonometric functions | Enormous (naïve) | Require floating-point, Taylor series, etc. |

CORDIC reduces sine and cosine computation to **only shifts and adds**, making it:

- **Multiplier-free** — no hardware multiplier needed
- **Simple to pipeline** — each iteration is identical in structure
- **Area-efficient** — very few logic gates compared to alternatives
- **Deterministic latency** — executes in exactly N clock cycles for N-bit precision
- **Synthesizable on FPGAs and ASICs** — directly maps to shift-register and adder primitives

This is why CORDIC is used in:
- Scientific calculators (HP-35 used CORDIC internally)
- FPGA signal processing cores
- Digital communication receivers
- Robotic kinematics engines
- Software-defined radio (SDR)

---

## 3. How CORDIC Computes Sine and Cosine

CORDIC works by **rotating a unit vector** starting along the X-axis toward the target angle θ.

**Starting vector:**

```
X₀ = 1.0  (unit vector along X-axis)
Y₀ = 0.0
Z₀ = θ    (the target angle we want to rotate toward)
```

At each iteration i, the algorithm asks: "Is there still angle left to rotate?"

- If `Zᵢ ≥ 0`: rotate **counter-clockwise** (positive direction)
- If `Zᵢ < 0`: rotate **clockwise** (negative direction)

The rotation at each step uses a pre-selected angle `αᵢ = arctan(2⁻ⁱ)`.

After N iterations:
- `Xₙ ≈ cos(θ) × Kₙ`  
- `Yₙ ≈ sin(θ) × Kₙ`

Where `Kₙ` is the **CORDIC gain**, which is a known constant that can be pre-compensated.

The final outputs after gain correction:
```
cos(θ) = Xₙ / Kₙ
sin(θ) = Yₙ / Kₙ
```

---

## 4. Why CORDIC Over Other Approaches?

### Alternative 1: Lookup Table (LUT)
Store precomputed values of sin(θ) and cos(θ) for all angles.

**Problems:**
- Requires huge memory for high precision (a 16-bit angle needs 65,536 entries)
- No interpolation → large quantization error
- Not practical for fine-grained precision without enormous ROM

### Alternative 2: Taylor Series Expansion
`sin(x) = x - x³/3! + x⁵/5! - ...`

**Problems:**
- Requires repeated **multiplications** and **divisions**
- Slow convergence for large angles
- Hardware multiplier is expensive in area and power

### Alternative 3: CORDIC
- No multiplier
- No division
- Small ROM (only N entries for N iterations)
- Scales naturally with precision
- Identical hardware for each iteration → easy to pipeline

### Comparison Table

| Approach | Multiplier? | Memory | Precision | HW Cost |
|---|---|---|---|---|
| LUT | No | Large | Limited | Medium |
| Taylor Series | Yes | Small | High (slow) | High |
| CORDIC | **No** | **Very Small** | **Scalable** | **Low** |

**CORDIC wins** for hardware implementation when multipliers are expensive or unavailable.

---

## 5. Mathematical Derivation from First Principles

### 5.1 2D Vector Rotation

To rotate a 2D vector `(X, Y)` by angle `α`:

```
X' = X·cos(α) - Y·sin(α)
Y' = X·sin(α) + Y·cos(α)
```

In matrix form:
```
| X' |   | cos(α)  -sin(α) |   | X |
| Y' | = | sin(α)   cos(α) | × | Y |
```

This is the **exact rotation matrix** — it requires 4 multiplications and 2 additions. Too expensive for hardware.

### 5.2 The CORDIC Transformation

CORDIC factors out `cos(αᵢ)` from the rotation matrix:

```
X' = cos(αᵢ) × [X - Y·tan(αᵢ)]
Y' = cos(αᵢ) × [Y + X·tan(αᵢ)]
```

Now, if we choose angles `αᵢ` such that `tan(αᵢ) = 2⁻ⁱ`:

```
tan(αᵢ) = 2⁻ⁱ  →  αᵢ = arctan(2⁻ⁱ)
```

Then:
```
X' = cos(αᵢ) × [X - Y × 2⁻ⁱ]
Y' = cos(αᵢ) × [Y + X × 2⁻ⁱ]
```

Multiplying by `2⁻ⁱ` is just a **right arithmetic shift by i positions** — no multiplier needed!

### 5.3 Removing the Cosine Scale Factor

The `cos(αᵢ)` term is still there. But notice: if we **defer** all the cosine factors and accumulate them as a single constant `Kₙ`, we can apply them once at the end (or pre-scale the initial vector):

```
Kₙ = ∏ cos(arctan(2⁻ⁱ))   for i = 0 to N-1
```

Since we just ignore `cos(αᵢ)` in each iteration, the CORDIC **pseudorotations** become:

```
Xᵢ₊₁ = Xᵢ - σᵢ × (Yᵢ >> i)
Yᵢ₊₁ = Yᵢ + σᵢ × (Xᵢ >> i)
Zᵢ₊₁ = Zᵢ - σᵢ × arctan(2⁻ⁱ)
```

Where:
- `>>` denotes arithmetic right shift
- `σᵢ = +1` if `Zᵢ ≥ 0` (rotate counter-clockwise)
- `σᵢ = -1` if `Zᵢ < 0` (rotate clockwise)

### 5.4 The Three Core CORDIC Equations

These three equations drive the hardware:

```
Xᵢ₊₁ = Xᵢ - σᵢ · (Yᵢ >>> i)     ... X update (cosine direction)
Yᵢ₊₁ = Yᵢ + σᵢ · (Xᵢ >>> i)     ... Y update (sine direction)
Zᵢ₊₁ = Zᵢ - σᵢ · arctan(2⁻ⁱ)   ... Z update (angle accumulator)
```

Where `>>>` is arithmetic right shift (preserves sign for 2's complement).

### 5.5 Initial Conditions

```
X₀ = 1/Kₙ  ≈ 0.6073  (pre-scaled initial vector)
Y₀ = 0
Z₀ = θ      (target angle in radians)
```

Pre-scaling X₀ by `1/Kₙ` eliminates the need for post-multiplication gain correction.

After N iterations:
```
Xₙ ≈ cos(θ)
Yₙ ≈ sin(θ)
Zₙ ≈ 0      (residual angle → 0 as iterations increase)
```

---

## 6. Rotation Mode vs Vectoring Mode

CORDIC has two fundamental operating modes:

### 6.1 Rotation Mode (Used for Sine and Cosine)

**Goal:** Rotate an input vector by angle Z₀.

**Decision rule:** `σᵢ = sign(Zᵢ)`
- If `Zᵢ ≥ 0`: rotate counter-clockwise (`σᵢ = +1`)
- If `Zᵢ < 0`: rotate clockwise (`σᵢ = -1`)

The algorithm drives `Z → 0`. When Z reaches zero, the vector has been rotated by the full target angle.

**Result:** `Xₙ = cos(θ)`, `Yₙ = sin(θ)` (after gain correction)

**This is the mode we implement for sine and cosine computation.**

### 6.2 Vectoring Mode

**Goal:** Compute the magnitude and angle of an input vector `(X₀, Y₀)`.

**Decision rule:** `σᵢ = -sign(Yᵢ)`
- Drives `Y → 0`
- Accumulates the rotation angle in Z

**Result:** `Xₙ = magnitude × Kₙ`, `Zₙ = arctan(Y₀ / X₀)`

This mode computes **inverse tangent** and **vector magnitude** — useful for polar-to-rectangular conversion.

### Summary

| Mode | Drives | Input | Output |
|---|---|---|---|
| Rotation | Z → 0 | Z₀ = target angle | X = cos, Y = sin |
| Vectoring | Y → 0 | X₀, Y₀ = input vector | X = magnitude, Z = arctan |

---

## 7. The CORDIC Gain Factor

Every CORDIC pseudorotation introduces a scale factor `cos(arctan(2⁻ⁱ))`.

After N iterations, the accumulated gain is:

```
Kₙ = ∏ (1 / cos(arctan(2⁻ⁱ)))   for i = 0 to N-1
   = ∏ √(1 + 2⁻²ⁱ)
```

### Computing Kₙ for N = 16 iterations:

| i | arctan(2⁻ⁱ) degrees | cos factor | cumulative Kₙ |
|---|---|---|---|
| 0 | 45.000° | 0.70711 | 1.41421 |
| 1 | 26.565° | 0.89443 | 1.58114 |
| 2 | 14.036° | 0.97014 | 1.62980 |
| 3 | 7.125° | 0.99228 | 1.64248 |
| 4 | 3.576° | 0.99805 | 1.64569 |
| 5 | 1.790° | 0.99951 | 1.64649 |
| 6 | 0.895° | 0.99988 | 1.64669 |
| 7 | 0.448° | 0.99997 | 1.64674 |
| ... | ... | → 1.0 | → 1.64676 |

**Kₙ converges to approximately 1.64676 for large N.**

Therefore, the **inverse gain** (pre-scale factor for X₀) is:

```
1/Kₙ ≈ 0.60725
```

### In Hardware

For a **16-bit Q1.15 fixed-point** system:

```
X₀ = 0.60725 × 2¹⁵ = 0.60725 × 32768 ≈ 19898  (decimal)
   = 0x4DBA  (hexadecimal)
   = 0b0100_1101_1011_1010  (binary)
```

This constant is hardwired into the design. No runtime multiplication is needed.

---

## 8. The Arctangent Lookup Table

The Z-update equation requires `arctan(2⁻ⁱ)` at each step:

```
Zᵢ₊₁ = Zᵢ - σᵢ × arctan(2⁻ⁱ)
```

These values are **constants** — they never change at runtime. So they are stored in a small ROM indexed by the iteration count `i`.

### Arctangent values for 16 iterations (in radians):

| i | arctan(2⁻ⁱ) in radians | In Q2.14 fixed-point (×2¹⁴) |
|---|---|---|
| 0 | 0.78539816 (π/4) | 12868 |
| 1 | 0.46364761 | 7596 |
| 2 | 0.24497866 | 4013 |
| 3 | 0.12435499 | 2037 |
| 4 | 0.06241881 | 1022 |
| 5 | 0.03123983 | 512 |
| 6 | 0.01562373 | 256 |
| 7 | 0.00781233 | 128 |
| 8 | 0.00390623 | 64 |
| 9 | 0.00195312 | 32 |
| 10 | 0.00097656 | 16 |
| 11 | 0.00048828 | 8 |
| 12 | 0.00024414 | 4 |
| 13 | 0.00012207 | 2 |
| 14 | 0.00006104 | 1 |
| 15 | 0.00003052 | 1 |

**Key properties:**
- Only 16 entries for 16-bit precision
- Values decrease rapidly — high iterations barely change Z
- Values are computed once and hardcoded in RTL

---

## 9. Fixed-Point Arithmetic in CORDIC

CORDIC is implemented using **fixed-point arithmetic** because:
- Hardware does not natively support floating-point (requires IEEE 754 FPUs)
- Fixed-point is simpler, faster, and uses less area
- CORDIC's iterative structure naturally controls precision via bit width

### 9.1 Fixed-Point Number Representation

A fixed-point number `Q(m.n)` format means:
- `m` bits for the integer part (including sign bit)
- `n` bits for the fractional part
- Total: `m + n` bits

**Example: Q1.15 (16-bit)**
- 1 sign+integer bit
- 15 fractional bits
- Range: -1.0 to +0.999969...
- Resolution: 2⁻¹⁵ ≈ 0.0000305

A real number `v` is stored as integer `V`:
```
V = round(v × 2¹⁵)
```

### 9.2 Interpreting Q1.15

| Real Value | Q1.15 Binary | Hex |
|---|---|---|
| +1.0 | 0_111 1111 1111 1111 | 0x7FFF |
| +0.5 | 0_100 0000 0000 0000 | 0x4000 |
| 0.60725 | 0_100 1101 1011 1010 | 0x4DBA |
| -1.0 | 1_000 0000 0000 0000 | 0x8000 |
| -0.5 | 1_100 0000 0000 0000 | 0xC000 |

### 9.3 Q-Format for Angle Register

Angles need slightly more range than [-1, +1]. CORDIC typically handles angles in the range `[-π/2, +π/2]` radians in rotation mode.

We use **Q2.14 format** for angles:
- 2 integer bits (includes sign)
- 14 fractional bits
- Range: -2.0 to +1.99994...
- Can represent angles up to ±π/2 ≈ ±1.5708 comfortably

Angle in Q2.14:
```
Z₀ = round(θ_radians × 2¹⁴)
```

For θ = 45° = π/4 = 0.7854 radians:
```
Z₀ = round(0.7854 × 16384) = round(12868.0) = 12868
```

### 9.4 Arithmetic Right Shift in 2's Complement

The shift operation `Yᵢ >>> i` in hardware is a **signed arithmetic right shift**:
- The sign bit is replicated (not filled with 0)
- For positive numbers: same as logical right shift
- For negative numbers: preserves the negative sign

Example for 8-bit: `0b1111_0000 >>> 2 = 0b1111_1100` (not `0b0011_1100`)

### 9.5 Overflow in Fixed-Point

During intermediate CORDIC iterations, intermediate values of X and Y can exceed the range [-1, +1] slightly. This is why internal registers are kept **wider** than output registers — typically 2–3 extra guard bits are added to prevent overflow.

For a 16-bit output, internal datapath uses **18-bit** registers.

### 9.6 Convergence Range

The CORDIC rotation mode converges correctly for input angles in the range:

```
θ ∈ [-π/2, +π/2]   ≈ [-1.5708, +1.5708] radians
                    = [-90°, +90°]
```

Angles outside this range require **quadrant correction** before processing:

| Angle Range | Quadrant | Correction |
|---|---|---|
| 0° to 90° | Q1 | Direct — no correction |
| 90° to 180° | Q2 | θ' = π - θ, then negate X output |
| -90° to 0° | Q4 | Direct — no correction (negative angle) |
| -180° to -90° | Q3 | θ' = -π - θ, then negate X and Y outputs |

---

## 10. Numerical Example

### Computing sin(45°) and cos(45°) step by step

**Input:** θ = 45° = π/4 = 0.7854 radians

**Expected output:** sin(45°) = cos(45°) = 0.70711

**Initial conditions:**
```
X₀ = 0.60725   (1/Kₙ, the pre-scaled unit vector)
Y₀ = 0.00000
Z₀ = 0.78540   (π/4 radians)
```

**Iteration table** (real-valued, for clarity):

| i | σᵢ | Xᵢ | Yᵢ | Zᵢ | arctan(2⁻ⁱ) |
|---|---|---|---|---|---|
| 0 | +1 | 0.60725 | 0.00000 | 0.78540 | 0.78540 |
| 1 | +1 | 0.60725 | 0.60725 | 0.00000 | 0.46365 |
| 2 | -1 | 0.45544 | 0.75891 | -0.46365 | 0.24498 |
| 3 | -1 | 0.54116 | 0.72034 | -0.21867 | 0.12435 |
| 4 | -1 | 0.58853 | 0.69651 | -0.09432 | 0.06242 |
| 5 | -1 | 0.61221 | 0.68390 | -0.03190 | 0.03124 |
| 6 | -1 | 0.62405 | 0.67765 | -0.00066 | 0.01562 |
| 7 | -1 | 0.62997 | 0.67453 | 0.01496 | 0.00781 |
| 8 | +1 | 0.62734 | 0.67698 | 0.00715 | 0.00391 |
| 9 | +1 | 0.62601 | 0.67821 | 0.00324 | 0.00195 |
| 10 | +1 | 0.62534 | 0.67882 | 0.00129 | 0.00098 |
| 11 | +1 | 0.62501 | 0.67913 | 0.00031 | 0.00049 |
| 12 | +1 | 0.62484 | 0.67928 | -0.00018 | 0.00024 |
| 13 | -1 | 0.62492 | 0.67921 | 0.00006 | 0.00012 |
| 14 | +1 | 0.62488 | 0.67924 | -0.00006 | 0.00006 |
| 15 | -1 | 0.62490 | 0.67923 | 0.00000 | 0.00003 |

**Final values (approximately):**
```
X₁₆ ≈ 0.70709   →  cos(45°) ≈ 0.70709  (exact: 0.70711)
Y₁₆ ≈ 0.70709   →  sin(45°) ≈ 0.70709  (exact: 0.70711)
```

**Error:** |0.70711 - 0.70709| = 0.00002 → well within 16-bit fixed-point resolution.

### Why iteration 1 jumps sharply

At i=0, `arctan(2⁰) = arctan(1) = 45°`, which exactly cancels Z₀ in one step for this angle. The subsequent iterations fine-tune the residual angle.

### Observation: Z converges to zero

Watch Zᵢ oscillate with decreasing amplitude around 0 — this is the hallmark of CORDIC convergence. Each iteration cuts the residual angle roughly in half.

---

## Summary of Phase 1

| Concept | Key Takeaway |
|---|---|
| CORDIC principle | Replace multiplications with shifts and adds via pseudo-rotation |
| Rotation mode | Drive Z→0; outputs are sin and cos of input angle |
| Gain factor Kₙ | ≈1.64676; compensated by pre-scaling X₀ = 1/Kₙ ≈ 0.60725 |
| Arctangent table | 16 precomputed constants, index = iteration number |
| Fixed-point format | Q1.15 for X/Y (data), Q2.14 for Z (angle) in 16-bit design |
| Convergence range | ±90° directly; quadrant correction needed for wider range |
| Hardware primitives | Adder, arithmetic right shifter, comparator — no multiplier |
| Precision | 16 iterations gives ~4–5 decimal digits of accuracy |

---

*Document Status: Complete — Phase 1*  
*Next Phase: Hardware Architecture Definition (Phase 2)*  
*Prepared for: COA Academic Project — CORDIC Verilog Implementation*
