# Phase 7: COA Concepts and Viva Preparation
## CORDIC Algorithm — Academic Concepts and Technical Interview Questions

---

## Table of Contents

1. [COA Concepts Demonstrated by This Project](#1-coa-concepts-demonstrated-by-this-project)
2. [Concept 1: ALU Operations](#concept-1-alu-operations)
3. [Concept 2: Shift Registers and Arithmetic Shifts](#concept-2-shift-registers-and-arithmetic-shifts)
4. [Concept 3: Fixed-Point Arithmetic](#concept-3-fixed-point-arithmetic)
5. [Concept 4: Sequential Circuits](#concept-4-sequential-circuits)
6. [Concept 5: FSM Design](#concept-5-fsm-design)
7. [Concept 6: Registers and Counters](#concept-6-registers-and-counters)
8. [Concept 7: Memory and Lookup Tables](#concept-7-memory-and-lookup-tables)
9. [Concept 8: Iterative Computation in Hardware](#concept-8-iterative-computation-in-hardware)
10. [Concept 9: Hardware Resource Optimization](#concept-9-hardware-resource-optimization)
11. [Concept 10: Hardware vs Software Computation](#concept-10-hardware-vs-software-computation)
12. [Viva Questions and Answers](#12-viva-questions-and-answers)

---

## 1. COA Concepts Demonstrated by This Project

The following table maps each COA course concept to its specific demonstration within this CORDIC project:

| COA Concept | Where Demonstrated |
|---|---|
| ALU operations (add, subtract) | `cordic_datapath.v` — X, Y, Z updates each iteration |
| Arithmetic right shift | `cordic_datapath.v` — `$signed(x_reg) >>> iter_count` |
| Shift register | X, Y registers updated by shifted versions of themselves |
| Fixed-point arithmetic | Q1.15 (X/Y) and Q2.14 (Z) throughout the design |
| 2's complement arithmetic | All signed registers: X_reg, Y_reg, Z_reg, angle_in |
| Sequential logic | Registered X, Y, Z, FSM state, counter, output reg |
| Combinational logic | ROM, shifter, next-value computation, sigma detection |
| FSM design | `cordic_fsm.v` — 4-state Moore machine |
| Synchronous design | Single clock domain, all registers clocked on posedge |
| Register file / data registers | X_reg, Y_reg, Z_reg in datapath |
| Counter design | `cordic_iter_counter.v` — 4-bit synchronous counter |
| ROM / lookup table | `cordic_atan_rom.v` — 16-entry arctangent table |
| Iterative computation | 16-cycle loop reusing one datapath |
| Hardware resource optimization | Multiplier-free design using only shifts and adds |
| Latency vs throughput | Serial: 19-cycle latency vs pipelined: 1-cycle throughput |
| Hardware vs software | CORDIC hardware vs Taylor series software |

---

## Concept 1: ALU Operations

### How CORDIC demonstrates it

Every CORDIC iteration performs three arithmetic operations simultaneously:
```
X_new = X ± (Y >> i)    — subtraction or addition
Y_new = Y ± (X >> i)    — addition or subtraction
Z_new = Z ∓ atan[i]     — subtraction or addition
```

This is equivalent to three parallel ALU operations per clock cycle — the hardware equivalent of an ALU computing multiple results in one pass.

### Specific implementation

In `cordic_datapath.v`:
```verilog
assign x_next = sigma ? (x_reg + y_shift) : (x_reg - y_shift);
assign y_next = sigma ? (y_reg - x_shift) : (y_reg + x_shift);
assign z_next = sigma ? (z_reg + atan_ext) : (z_reg - atan_ext);
```

These three lines implement a 3-output ALU that performs signed addition or subtraction based on a single control bit (`sigma`). The operation selection is a 1-bit mux — the same principle as an ALU's opcode-driven operation select.

---

## Concept 2: Shift Registers and Arithmetic Shifts

### How CORDIC demonstrates it

The CORDIC algorithm replaces multiplication by 2⁻ⁱ with an **arithmetic right shift by i bits**. This is the fundamental hardware trick that makes CORDIC multiplier-free.

### Logical vs Arithmetic shift

```
Logical right shift (>>):
  For 8-bit 1111_0000:   >> 2 → 0011_1100  (fills with 0)
  Incorrect for negatives in 2's complement

Arithmetic right shift (>>>):
  For 8-bit 1111_0000:  >>> 2 → 1111_1100  (replicates sign bit)
  Correct for signed 2's complement division by 2
```

### In hardware

An arithmetic right shift by a fixed amount is purely a **wiring operation** — no gates, no delay, zero area cost. A variable shift (barrel shifter) adds a log₂(N) stage multiplexer, but still much cheaper than a multiplier.

In this design: `$signed(x_reg) >>> iter_count` where `iter_count` varies from 0 to 15. This is a 4-to-1 barrel shifter synthesized from multiplexers.

### Why this matters for COA

- Shows how bit manipulation replaces arithmetic
- Demonstrates the relationship between bit position and powers of 2
- Illustrates how hardware leverages number representation for efficiency

---

## Concept 3: Fixed-Point Arithmetic

### How CORDIC demonstrates it

The entire design operates in fixed-point arithmetic. There is no floating-point unit anywhere.

### Q1.15 interpretation

A 16-bit signed integer `V` represents real value `v`:
```
v = V / 32768 = V × 2⁻¹⁵
```

Addition/subtraction of Q1.15 numbers works identically to integer arithmetic. No special instructions needed.

### Q2.14 interpretation

```
v = V / 16384 = V × 2⁻¹⁴
```

Used for the angle register where values can reach ±1.57 (π/2) which exceeds the Q1.15 range of ±1.0.

### Fixed-point overflow

If two Q1.15 numbers are added and the result exceeds ±1.0, overflow occurs. CORDIC prevents this by using 18-bit guard bits internally. The extra 2 bits extend the range to ±4.0, preventing any intermediate overflow.

### Connection to COA

- Fixed-point shows how real-world values (sine, cosine, angles) are encoded in binary
- Demonstrates the trade-off between range and precision
- Shows how the choice of representation affects hardware design

---

## Concept 4: Sequential Circuits

### How CORDIC demonstrates it

The CORDIC hardware is fundamentally a sequential circuit: its outputs depend on both current inputs AND stored state (the X, Y, Z registers from previous iterations).

### State elements in this design

| Register | Width | Role |
|---|---|---|
| X_reg | 18-bit | Stores running X coordinate |
| Y_reg | 18-bit | Stores running Y coordinate |
| Z_reg | 18-bit | Stores remaining angle |
| FSM state | 2-bit | Control flow position |
| iter_count | 4-bit | Iteration progress |
| cosine_out | 16-bit | Output holding register |
| sine_out | 16-bit | Output holding register |

### Mealy vs Moore

The FSM is a **Moore machine**: outputs depend only on the current state, not the current inputs. This is demonstrated by the output table in Phase 2 — each state has fixed outputs regardless of `start` or `iter_done`.

### Synchronous behavior

All state elements update on the **rising edge of the clock**. Between clock edges, the combinational logic computes the next state. This is the textbook definition of a synchronous sequential circuit.

---

## Concept 5: FSM Design

### How CORDIC demonstrates it

The `cordic_fsm` is a clean 4-state Moore machine that controls the entire CORDIC computation. Every textbook FSM design principle is applied here.

### State encoding

```
IDLE    = 2'b00   (power-up state)
LOAD    = 2'b01   (initialize registers)
ITERATE = 2'b10   (run 16 iterations)
DONE    = 2'b11   (capture output, signal completion)
```

### Three-part FSM structure in Verilog

```verilog
// Part 1: State register (sequential)
always @(posedge clk) if (rst) state <= IDLE; else state <= next_state;

// Part 2: Next-state logic (combinational)
always @(*) case(state) ... endcase

// Part 3: Output logic (combinational, Moore)
always @(*) case(state) ... endcase
```

This three-block structure is the standard synthesizable FSM template taught in every digital design course.

### State transition diagram connection

The state diagram (Phase 2, Section 10) maps exactly to the case statements in the Verilog. This demonstrates how abstract state diagrams translate directly into hardware.

---

## Concept 6: Registers and Counters

### Registers (X, Y, Z)

The X, Y, Z registers are 18-bit parallel-load registers with:
- Synchronous reset (clears to 0)
- Parallel load (loads initial values on `load_en`)
- Hold (no change when neither load_en nor iter_en)
- Update (replaces value on `iter_en`)

This demonstrates the complete behavior of a data register: reset, load, hold, update.

### Counter (iter_counter)

The iteration counter is a 4-bit synchronous up-counter with:
- Synchronous reset
- Count enable (`iter_en`)
- Terminal count detection (`iter_done` at count=15)

This is the archetypal synchronous counter — a foundational building block taught in every COA course.

### Connection to COA

- Registers are the fundamental storage elements of a CPU's datapath
- Counters control instruction sequencing, loop iteration, and timing
- The iteration counter here directly controls how many times the arithmetic unit is applied

---

## Concept 7: Memory and Lookup Tables

### How CORDIC demonstrates it

The arctangent ROM (`cordic_atan_rom.v`) is a 16-entry read-only memory. It demonstrates:
- Memory addressing (4-bit address → 16-bit data)
- Read-only memory (values fixed at design time)
- Asynchronous read (output available immediately, no clock required)
- Trade-off between memory size and computation complexity

### ROM vs RAM

```
ROM: Content fixed at synthesis time. Address → data. No write port.
RAM: Content writable at runtime. Address + data + write enable.
```

CORDIC uses ROM because the arctangent values are mathematical constants — they never change during operation. This is an example of **algorithm-specific ROM**: pre-computing expensive values once and storing them permanently.

### Area analysis

The ROM stores 16 × 16-bit = 256 bits. Compare this to computing `arctan(2⁻ⁱ)` at runtime using a Taylor series — that would require a multiplier, adder chain, and approximately 100+ cycles per value. The 256-bit ROM eliminates all of that complexity.

---

## Concept 8: Iterative Computation in Hardware

### How CORDIC demonstrates it

CORDIC is a textbook example of **iterative computation mapped to hardware**. The same arithmetic datapath (adders, shifters) is applied 16 times using a feedback loop: the output of iteration i becomes the input of iteration i+1.

### Software vs hardware iteration

```
Software:          Hardware (CORDIC):
for i in 0..15:    Each clock cycle = one iteration
    x = x - y>>i  Single datapath, reused 16 times
    y = y + x>>i  Registers hold intermediate state
    z = z - a[i]  Counter tracks which iteration
```

The hardware does not unroll the loop (that would be a pipeline). Instead, it **time-multiplexes** the datapath across 16 clock cycles, using registers to maintain state between iterations.

### Convergence

The Z register converges to zero through binary search-like behavior. Each iteration halves the remaining angle error by rotating by ±arctan(2⁻ⁱ). After 16 steps, Z ≈ 0 and X, Y hold the desired result.

---

## Concept 9: Hardware Resource Optimization

### How CORDIC demonstrates it

CORDIC is the classic example of **algorithm-hardware co-optimization**. By choosing an algorithm specifically suited to hardware primitives, the design achieves its goal without expensive resources.

### Optimization 1: Multiplier elimination

Standard rotation requires 4 multiplications per iteration × 16 iterations = 64 multiplications total. CORDIC replaces ALL of them with:
- 48 arithmetic right shifts (wires)
- 48 additions/subtractions
- 16 ROM lookups

### Optimization 2: Single datapath reuse

Instead of 16 parallel datapaths (pipeline), one datapath is reused 16 times (serial). Area savings: 16×. Latency cost: 16× slower than pipeline. This is the fundamental **area-latency trade-off** in digital design.

### Optimization 3: Gain pre-compensation

Instead of multiplying the final output by 1/K (expensive), the initial X₀ is loaded as 1/K (a single constant). Zero runtime cost for what would otherwise require a 16-bit multiplier.

### Hardware cost comparison

| Approach | Multipliers | Adders | Memory | Cycles |
|---|---|---|---|---|
| Floating-point | 4+ | 2+ | Large | 1 |
| Taylor series | 10+ | 8+ | Small | 50+ |
| LUT (full) | 0 | 0 | 64KB+ | 1 |
| CORDIC (serial) | **0** | **3** | **32B** | **19** |
| CORDIC (pipeline) | 0 | 48 | 32B | 1 |

---

## Concept 10: Hardware vs Software Computation

### How CORDIC demonstrates it

The same mathematical function (sin/cos) can be computed in software using a Taylor series or in hardware using CORDIC. The comparison illuminates the fundamental differences between the two paradigms.

### Software (Taylor series)
```python
def sin_taylor(x, terms=10):
    result = 0
    for i in range(terms):
        n = 2*i + 1
        result += ((-1)**i * x**n) / factorial(n)
    return result
```
- Flexible: change `terms` for more/less precision
- Requires floating-point multiplication
- Sequential by nature: each term depends on previous
- Slow on bare hardware (no FPU)

### Hardware (CORDIC)
- Fixed function: designed for exactly this purpose
- No multiplication: shifts and adds only
- Deterministic latency: always 19 cycles
- Massively more efficient on bare hardware
- Not flexible: changing the algorithm requires redesign

### Key insight for COA

Hardware is optimized for **specific, repeated computations** at **high speed** with **low resource usage**. Software is optimized for **flexibility** and **programmability**. CORDIC exists at the boundary — it's an algorithm designed to match hardware capabilities, not hardware designed to execute general software.

---

## 12. Viva Questions and Answers

### Section A: CORDIC Fundamentals (Q1–Q8)

---

**Q1. What does CORDIC stand for and who invented it?**

CORDIC stands for **COordinate Rotation DIgital Computer**. It was invented by **Jack E. Volder in 1959** for computing navigation equations aboard the B-58 Hustler bomber aircraft in real time, without a hardware multiplier.

---

**Q2. What is the core principle behind CORDIC?**

CORDIC decomposes a large rotation into a sequence of smaller micro-rotations, each by an angle whose tangent is a power of two: `arctan(2⁻ⁱ)`. Multiplying by `2⁻ⁱ` is equivalent to an arithmetic right shift by `i` bits — requiring no multiplier hardware. The sum of these micro-rotations converges to the desired angle through a greedy binary search.

---

**Q3. Why does CORDIC not require a hardware multiplier?**

At each iteration, CORDIC multiplies by `tan(αᵢ) = 2⁻ⁱ`. Multiplying a binary number by `2⁻ⁱ` is accomplished by right-shifting the number by `i` bit positions. A bit shift in hardware is simply rewiring — it requires no logic gates. Therefore, the full rotation computation reduces to adders and wiring alone.

---

**Q4. What are the three CORDIC iteration equations?**

```
Xᵢ₊₁ = Xᵢ  −  σᵢ · (Yᵢ >>> i)
Yᵢ₊₁ = Yᵢ  +  σᵢ · (Xᵢ >>> i)
Zᵢ₊₁ = Zᵢ  −  σᵢ · arctan(2⁻ⁱ)
```

Where:
- `>>>` is arithmetic right shift
- `σᵢ = +1` if Zᵢ ≥ 0, else `σᵢ = -1`
- The arctangent values are precomputed constants in ROM

---

**Q5. What is CORDIC Rotation Mode? What is Vectoring Mode?**

**Rotation Mode:** The algorithm drives Z → 0. Starting with a reference vector and a target angle Z₀, it rotates the vector until the residual angle is zero. Output: X = cos(θ), Y = sin(θ).

**Vectoring Mode:** The algorithm drives Y → 0. Starting with an input vector (X₀, Y₀), it rotates the vector until Y is zero. Output: X = magnitude, Z = arctan(Y₀/X₀). Used for computing arctangent and vector magnitude.

---

**Q6. What is the CORDIC gain factor, and why does it arise?**

Each CORDIC pseudo-rotation introduces a scale factor `kᵢ = √(1 + 2⁻²ⁱ)` because we omit the `cos(αᵢ)` normalization factor from each rotation. After N iterations, the total accumulated gain is:

```
Kₙ = ∏ √(1 + 2⁻²ⁱ)  ≈ 1.64676  for N=16
```

This means the output vector is scaled up by ~1.647 compared to the true unit vector. We compensate by pre-scaling the initial X₀ to `1/Kₙ ≈ 0.60725` — so the final result naturally comes out at the correct magnitude.

---

**Q7. What is the convergence range of CORDIC in rotation mode, and why?**

CORDIC rotation mode converges for input angles in **[-π/2, +π/2]** (i.e., ±90°). This is because:
- The first iteration rotates by ±arctan(1) = ±45°
- The remaining iterations can collectively rotate by at most ±(Σarctan(2⁻ⁱ) for i=1..) ≈ ±0.96 rad
- Together, the maximum achievable rotation is arctan(1) + 0.96 = 1.75 rad > π/2

Angles outside ±90° require **quadrant correction**: fold the angle into ±90°, run CORDIC, then negate appropriate output components based on the original quadrant.

---

**Q8. How does the arctangent lookup table work in hardware?**

The ROM stores 16 entries. The address is the current iteration index `i` (0–15). The output is `arctan(2⁻ⁱ)` encoded in Q2.14 fixed-point. It is asynchronous (combinational): the moment the address changes, the output changes. No clock is needed. The 16 entries require only 256 bits (32 bytes) of ROM — an extremely compact implementation.

---

### Section B: Fixed-Point Arithmetic (Q9–Q14)

---

**Q9. What is Q1.15 format? How do you convert a real number to Q1.15?**

Q1.15 is a 16-bit signed fixed-point format where:
- 1 bit represents the integer part (and sign)
- 15 bits represent the fractional part

To convert: `Q1.15_integer = round(real_value × 2¹⁵) = round(real_value × 32768)`

Example: `0.70711 × 32768 = 23169.8 → 23170 = 0x5A82`

To convert back: `real_value = integer / 32768`

Range: [-1.0, +0.999969] with resolution 3.05 × 10⁻⁵.

---

**Q10. Why is Q2.14 used for the angle register instead of Q1.15?**

The CORDIC convergence range requires the angle register to represent values up to π/2 ≈ 1.5708 radians. Q1.15 has a maximum value of +0.999969, which is less than 1.5708. Q2.14 has a maximum value of +1.99994, which easily accommodates π/2. The trade-off is slightly lower fractional resolution (2⁻¹⁴ vs 2⁻¹⁵), but this is acceptable for the angle register.

---

**Q11. What is the difference between arithmetic right shift and logical right shift?**

- **Logical right shift (`>>`):** Fills vacated MSBs with 0. Correct for unsigned numbers.
- **Arithmetic right shift (`>>>`):** Replicates the sign bit (MSB) into vacated positions. Correct for signed 2's complement numbers — equivalent to signed integer division by 2.

Example (8-bit): For `-8 = 1111_1000`:
- `>> 2` → `0011_1110` = +62 ✗ (wrong — changes the sign)
- `>>> 2` → `1111_1110` = -2 ✓ (correct — signed divide by 4)

In Verilog, `$signed(value) >>> n` gives arithmetic shift.

---

**Q12. What is 2's complement representation? Why is it used here?**

2's complement is the standard binary encoding for signed integers:
- Positive numbers: same as unsigned binary
- Negative number `-n`: invert all bits of `n`, then add 1
- Zero has exactly one representation
- Addition/subtraction hardware is identical regardless of sign

It is used in CORDIC because:
- The sign of Z (detected via its MSB) directly gives σᵢ
- Adding and subtracting signed values requires no extra logic
- The arithmetic right shift automatically handles negative numbers correctly

---

**Q13. What is fixed-point overflow and how is it prevented in this design?**

Overflow occurs when an arithmetic result exceeds the representable range. In CORDIC, during intermediate iterations, the X and Y values can temporarily reach up to `Kₙ × 1.0 ≈ 1.647`, exceeding the Q1.15 range of [-1, +1).

Prevention: Internal registers are **18-bit** (not 16-bit). The extra 2 bits extend the representable range to ±4.0. Since 1.647 < 4.0, no overflow can occur. These are called **guard bits**. The final output takes only the lower 16 bits once computation is complete.

---

**Q14. How do you interpret a negative value in Q1.15 hex output?**

For a 16-bit hex value `H` that represents a negative Q1.15 number:
```
real_value = (H − 65536) / 32768
```

Example: `0xC000 = 49152`
```
(49152 − 65536) / 32768 = −16384 / 32768 = −0.5
```
This represents cos(120°) = -0.5. ✓

Alternatively: 0xC000 in signed 16-bit = -16384, and -16384/32768 = -0.5.

---

### Section C: Hardware Architecture (Q15–Q20)

---

**Q15. What is a Moore machine? Why is it used for the CORDIC FSM?**

A **Moore machine** is a finite state machine whose outputs depend only on the current state, not on current inputs. This contrasts with a **Mealy machine** where outputs depend on both state and inputs.

The CORDIC FSM is a Moore machine because:
- Control signals (`load_en`, `iter_en`, `done`, etc.) have fixed values for each state
- This eliminates glitches on outputs (outputs only change when state changes, synchronized to clock)
- Simpler to analyze and implement correctly
- Easier to verify in simulation

---

**Q16. How many clock cycles does this CORDIC design take to produce a result?**

**19 clock cycles** from the assertion of `start` to valid outputs:
- Cycle 1: FSM sees `start`, moves IDLE → LOAD
- Cycle 2: LOAD state — initial X₀, Y₀, Z₀ loaded into registers
- Cycles 3–18: ITERATE state — 16 iterations, one per clock cycle
- Cycle 19: DONE state — `out_latch` asserted, outputs captured, `done` asserted

---

**Q17. Why is the CORDIC datapath 18 bits internally when inputs and outputs are 16 bits?**

Two extra bits (**guard bits**) are added to prevent arithmetic overflow during intermediate iterations. The CORDIC algorithm accumulates rotations that temporarily scale the vector beyond the final output range. Specifically, the X and Y values can reach up to ~1.647 (the CORDIC gain) during computation. A 16-bit Q1.15 register has a maximum of ~2.0, which is technically sufficient, but the 2 guard bits provide margin against accumulated rounding errors in the MSB. After all 16 iterations, the lower 16 bits are taken as the output.

---

**Q18. What is the difference between the serial and pipelined CORDIC architectures?**

**Serial CORDIC (this design):**
- One datapath, reused 16 times
- Latency: 19 clock cycles per result
- Throughput: 1 result per 19 cycles
- Area: 1× datapath + FSM + counter
- Best for: low-area applications, academic demos

**Pipelined CORDIC:**
- 16 datapaths, each handles one stage
- Latency: 16 clock cycles for first result
- Throughput: 1 result per clock cycle (after pipeline fills)
- Area: 16× datapath (much larger)
- Best for: high-throughput signal processing (SDR, FFT)

The area-throughput trade-off is a fundamental concept in digital architecture.

---

**Q19. Explain the role of the quadrant correction module.**

CORDIC rotation mode only converges for angles in ±90°. The quadrant correction module extends the input range to ±180°:

1. **Detection:** Examines the two MSBs of the angle input to determine which quadrant it falls in (Q1: 0°–90°, Q2: 90°–180°, Q3: -180°–90°, Q4: -90°–0°)

2. **Folding:** If the angle is outside ±90°, it folds it: for Q2, θ' = π − θ; for Q3, θ' = −π − θ

3. **Post-correction:** After CORDIC produces cos/sin of the folded angle, the outputs are sign-corrected: negate cosine for Q2 and Q3, negate sine for Q3 and Q4

This works because `cos(π−θ) = −cos(θ)` and `sin(π−θ) = sin(θ)`, so the CORDIC result for the supplementary angle can be trivially transformed to give the correct result for the original angle.

---

**Q20. Why is a synchronous reset preferred over an asynchronous reset?**

**Synchronous reset:** The reset takes effect only on the next rising clock edge. All flip-flops change state simultaneously, in a deterministic, clock-aligned manner.

**Asynchronous reset:** The reset takes effect immediately when asserted, regardless of the clock.

Synchronous reset is preferred because:
- Cleaner timing analysis (reset is just another data input)
- No setup/hold violation risk with synchronous reset
- Better compatibility with FPGA architectures (Xilinx/Intel recommend synchronous)
- Easier static timing analysis during synthesis
- Prevents glitches from asynchronous assertions during metastable conditions

---

### Section D: Implementation and Verification (Q21–Q25)

---

**Q21. How does the testbench verify that the CORDIC output is correct?**

The testbench applies a known input angle, waits for `done`, then:
1. Reads `cosine_out` and `sine_out`
2. Compares each against a precomputed reference value (from Phase 4 table)
3. Calculates absolute error: `|output − expected|`
4. Passes if error ≤ 4 LSBs (i.e., ≤ 4 × 3.05e-5 ≈ 1.22e-4)

The reference values are computed by multiplying the mathematical result by 32768 and rounding to the nearest integer. This converts the real-valued expected output into the same Q1.15 integer representation as the hardware output.

---

**Q22. What would happen if you forgot to use an arithmetic right shift (used >> instead of >>>)?**

For positive X or Y values, no difference — the MSB is 0, so shifting in 0s is correct.

For negative X or Y values, `>>` shifts in 0s instead of 1s:
- `-8 = 1111_1000` shifted right by 2
- Logical: `0011_1110` = +62 (completely wrong — sign flipped)
- Arithmetic: `1111_1110` = -2 (correct)

This bug would cause the CORDIC iterations to diverge or produce incorrect results whenever X or Y becomes negative — which happens frequently during the computation of angles in the second half of the iteration sequence.

---

**Q23. How do you detect a bug in the FSM during simulation?**

Check the following in the waveform:
1. **State signal**: Does it follow the sequence IDLE→LOAD→ITERATE→DONE→IDLE?
2. **load_en**: Is it exactly 1 cycle wide (LOAD state only)?
3. **iter_en**: Does it stay high for exactly 16 cycles (ITERATE state only)?
4. **done**: Is it exactly 1 cycle wide (DONE state only)?
5. **cnt_rst**: Is it high in IDLE and LOAD, low in ITERATE?

Common FSM bugs:
- Missing `default` in `next_state` logic → latch inferred
- Forgetting to default outputs to 0 → latch in output logic
- `done` staying high → FSM stuck in DONE (next_state not wired correctly)
- `start` not causing state transition → sensitivity list issue or `start` not actually pulsing

---

**Q24. What is the significance of the constant 0x4DBA in this design?**

`0x4DBA = 19898` in decimal. In Q1.15 fixed-point:
```
19898 / 32768 = 0.607239 ≈ 0.607253 = 1/K₁₆
```

Where K₁₆ ≈ 1.64676 is the CORDIC gain after 16 iterations.

This constant is the **pre-scaled initial X value** loaded into the X register at the start of every computation. It compensates for the accumulated scale factor introduced by 16 CORDIC pseudo-rotations, so the final output is correctly scaled to [-1, +1] range without any post-multiplication.

If X₀ were set to 0x7FFF (≈1.0) instead, the outputs would be approximately 1.64676× larger than the correct sine and cosine values.

---

**Q25. Compare CORDIC hardware implementation with a software Taylor series implementation. Which is better, and when?**

| Criterion | CORDIC Hardware | Taylor Series Software |
|---|---|---|
| Multiplier required | No | Yes |
| Precision control | Fixed at design time | Adjust terms at runtime |
| Latency | Fixed (19 cycles) | Variable |
| Power consumption | Low | Higher (multiplier active) |
| Area | Small | Large (FPU) |
| Flexibility | Fixed function | Any function |
| Error type | Systematic (gain) | Convergence error |
| Best for | Real-time signal processing | General-purpose computation |

**CORDIC is better** when:
- No hardware multiplier is available (microcontrollers, early FPGAs)
- Fixed latency is required (real-time systems)
- The same function (sin/cos) is computed millions of times (DSP)

**Taylor series is better** when:
- Arbitrary functions are needed (general purpose)
- A floating-point unit is already available
- High precision (>16 bits) is required without redesigning hardware
- The algorithm needs to change at runtime

In a dedicated FPGA or ASIC for signal processing, CORDIC wins decisively.

---

### Bonus Questions

**Q26. What would change if you wanted 32-bit output precision?**

- Data registers: Q1.31 (32-bit) for X/Y
- Angle register: Q2.30 (32-bit) for Z
- Internal registers: 34-bit (2 guard bits)
- Iterations: N = 32 (for 32-bit precision)
- ROM: 32 entries of 32-bit each
- Counter: 5-bit (counts 0–31)
- Latency: 35 clock cycles
- Gain constant: same 0.60725 but stored to 31 fractional bits
- Everything else: identical structure — the design scales perfectly

---

**Q27. If angle_in = 0x3244 (45°) and after 16 iterations Z_reg ≠ 0, what are the possible causes?**

1. **Wrong atan_val for some iteration:** ROM entry incorrect, causing incorrect Z subtraction
2. **Wrong sigma polarity:** MSB of Z being read incorrectly — sigma inverted causes Z to diverge instead of converge
3. **Sign extension error:** atan_val not sign-extended to 18-bit before Z subtraction — incorrect Z_next
4. **Non-arithmetic shift in Z:** If Z is shifted instead of atan — conceptual error in the equations
5. **Load not working:** Z₀ not loaded correctly (angle_in not sign-extended properly, so Z starts at wrong value)
6. **Iteration count wrong:** If iter_count is off by 1, wrong atan values are applied

---

*Document Status: Complete — Phase 7*  
*Next Phase: Demonstration and Documentation Plan (Phase 8)*  
*Prepared for: COA Academic Project — CORDIC Verilog Implementation*
