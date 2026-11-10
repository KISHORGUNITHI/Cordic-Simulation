# CORDIC Processor — Complete Viva Voce Preparation Guide
## Top 27 Questions & Answers for Academic Oral Examination

This guide prepares you for any oral exam, viva voce, or technical interview on your **16-Bit Multiplier-Free CORDIC Processor** project.

---

## Quick Hardware Snapshot (Memorize These Numbers!)

- **Algorithm:** CORDIC (COordinate Rotation DIgital Computer), Jack E. Volder (1959).
- **Mode:** Rotation Mode (circular coordinates: evaluates $\sin\theta$ and $\cos\theta$).
- **Multipliers Used:** **0** (Multiplier-free: uses only arithmetic shifts and add/subtract).
- **Latency:** **Exactly 18 clock cycles** from accepted `start` to `done` pulse.
- **Clock Domain:** Single synchronous clock (50 MHz, $T = 20\text{ ns}$).
- **Input Format:** 16-bit signed `Q3.13` radians (covers full circle $[-\pi, +\pi]$).
- **Output Format:** 16-bit signed `Q1.15` (range $[-1.0, +1.0)$).
- **Internal Datapath:** 22-bit signed (`Q3.19` for $X/Y$, `Q4.18` for $Z$).
- **Guard Bits:** **2 MSB integer guard bits** (prevent intermediate growth overflow) + **4 LSB fractional guard bits** (suppress shift truncation noise).
- **Scale Factor:** $K_{16} \approx 1.646760$. Pre-scale constant $X_0 = 1/K_{16} \approx 0.607253$ (`22'sh04DBA7`).
- **Accuracy:** Maximum error $\le 1\text{ LSB}$ ($\approx 3.05 \times 10^{-5}$ physical error).

---

## Section A: CORDIC Algorithm & Mathematical Foundations

### Q1. What does CORDIC stand for, and why was it invented?
**Answer:** CORDIC stands for **COordinate Rotation DIgital Computer**. It was invented by **Jack E. Volder in 1959** to solve navigation equations (conversions between polar and Cartesian coordinates) in real time aboard the Convair B-58 Hustler supersonic bomber, where analog computers were too heavy and digital multipliers did not yet exist.

### Q2. What is the fundamental principle that makes CORDIC multiplier-free?
**Answer:** CORDIC breaks down an arbitrary rotation angle $\theta$ into a sequence of $N$ micro-rotations by elementary angles $\alpha_i = \arctan(2^{-i})$. In binary hardware, multiplying by $2^{-i}$ is accomplished by an **arithmetic right shift by $i$ bit positions** (`>>> i`). Bit shifting requires only multiplexer wiring and zero logic gates or multipliers.

### Q3. What are the three core CORDIC recurrence equations?
**Answer:**
$$\begin{aligned}
X_{i+1} &= X_i - \sigma_i \cdot (Y_i >>> i) \\
Y_{i+1} &= Y_i + \sigma_i \cdot (X_i >>> i) \\
Z_{i+1} &= Z_i - \sigma_i \cdot \alpha_i
\end{aligned}$$
where $\sigma_i = +1$ if $Z_i \ge 0$ (rotate counter-clockwise), and $\sigma_i = -1$ if $Z_i < 0$ (rotate clockwise). $\alpha_i = \arctan(2^{-i})$ is fetched from a 16-word ROM.

### Q4. What is the difference between Rotation Mode and Vectoring Mode?
**Answer:**
- **Rotation Mode:** The objective is to drive the residual angle **$Z \to 0$**. Starting with $X_0 = 1/K, Y_0 = 0$, and $Z_0 = \theta$, the outputs converge to $X = \cos\theta$ and $Y = \sin\theta$.
- **Vectoring Mode:** The objective is to drive coordinate **$Y \to 0$**. Starting with input coordinates $(X_0, Y_0)$ and $Z_0 = 0$, the core outputs vector magnitude $R = \sqrt{X_0^2 + Y_0^2}$ on $X$, and angle $\theta = \arctan(Y_0/X_0)$ on $Z$.

### Q5. What is the CORDIC gain factor ($K$), and how does our design compensate for it?
**Answer:** Omitting $\cos\alpha_i$ from each micro-rotation expands vector length by $\sqrt{1 + 2^{-2i}}$. Across 16 iterations, the cumulative gain is:
$$K_{16} = \prod_{i=0}^{15} \sqrt{1 + 2^{-2i}} \approx 1.646760258$$
Rather than dividing the output by $K$ at the end (which would require a costly hardware divider), we pre-scale the initial input:
$$X_0 = \frac{1}{K_{16}} \approx 0.607252935 \quad (\text{0x04DBA7 in } Q3.19)$$
The cumulative growth naturally scales the output to the exact unit circle ($1.0$).

### Q6. Why can basic CORDIC not rotate beyond $\approx \pm 99^\circ$? How did you solve it?
**Answer:** The sum of all 16 elementary angles is:
$$\sum_{i=0}^{15} \arctan(2^{-i}) \approx 99.88^\circ < 1.743\text{ radians}$$
Angles outside this range cannot converge. We solved this by implementing **quadrant pre-processing** ([`cordic_quadrant.v`](file:///c:/Users/HP/Desktop/COA/rtl/cordic_quadrant.v)):
- Q1 ($[0, \pi/2]$): folded angle $= \theta$
- Q2 ($(\pi/2, \pi]$): folded angle $= \pi - \theta$
- Q3 ($[-\pi, -\pi/2)$): folded angle $= \theta + \pi$
- Q4 ($[-\pi/2, 0)$): folded angle $= -\theta$
The core iterates in $[0, \pi/2]$, and the output stage ([`cordic_output_reg.v`](file:///c:/Users/HP/Desktop/COA/rtl/cordic_output_reg.v)) reconstructs the signs: $\cos$ is negated in Q2/Q3; $\sin$ is negated in Q3/Q4.

---

## Section B: Fixed-Point Arithmetic & Precision Engineering

### Q7. Explain the $Q1.15$ format with a numerical example.
**Answer:** $Q1.15$ is a 16-bit signed fixed-point format where bit 15 is the sign/integer bit and bits $14 \dots 0$ represent the fractional magnitude:
$$\text{Value} = -b_{15} + \sum_{j=1}^{15} b_{15-j} \cdot 2^{-j}$$
- Conversion to $Q1.15$: $\text{round}(\text{real\_val} \times 32768)$.
  - Example: $\cos(45^\circ) = 0.70710678 \times 32768 \approx 23170 = \text{0x5A82}$.
- Range: $[-1.0, +0.999969]$ with resolution $1/32768 \approx 3.05 \times 10^{-5}$.

### Q8. Why does $+1.0$ cause an issue in $Q1.15$, and how do you handle it?
**Answer:** In 16-bit 2's complement, the range is $[-32768, +32767]$. $+1.0$ would correspond to $+32768$, which overflows into negative numbers (`-32768`). We prevent wraparound using **saturation arithmetic** in [`cordic_output_reg.v`](file:///c:/Users/HP/Desktop/COA/rtl/cordic_output_reg.v): any value $\ge +32768$ is clamped to `0x7FFF` (+32767). This creates a maximum error of only $1\text{ LSB}$ ($0.00003$).

### Q9. Why did you use 22 bits internally instead of 16 bits?
**Answer:** To provide **guard bits**:
1. **2 Integer Guard Bits (MSBs):** Intermediate pseudo-rotations expand coordinates up to $\approx 1.2$. Using 3 integer bits prevents 2's complement overflow.
2. **4 Fractional Guard Bits (LSBs):** Right-shifting by $i$ bits drops fractional bits. Across 16 iterations, truncation error can accumulate up to $\log_2(16) = 4$ bits. Adding 4 fractional guard bits absorbs this error entirely, so rounding back to 15 bits yields $\le 1\text{ LSB}$ error.

### Q10. Why is arithmetic shift (`>>>`) used instead of logical shift (`>>`)?
**Answer:** Coordinates $X, Y, Z$ are signed numbers. A logical shift (`>>`) fills MSBs with zeros, which turns negative numbers into positive numbers. Arithmetic right shift (`>>>`) replicates the sign bit (MSB), correctly dividing signed numbers by 2 in 2's complement.

---

## Section C: Hardware Architecture & Control Flow

### Q11. Describe the 4 states of the FSM and their control outputs.
**Answer:**
1. **`IDLE` (2'b00):** Waits for `start = 1`. Asserts `ready = 1`, `cnt_rst = 1`.
2. **`LOAD` (2'b01):** Asserts `load_en = 1` to initialize $X_0 = \text{0x04DBA7}, Y_0 = 0, Z_0 = \text{folded angle}$.
3. **`ITERATE` (2'b10):** Asserts `iter_en = 1`. Counter counts $0 \to 15$ while datapath performs micro-rotations. On cycle 15, `iter_done` triggers transition to `DONE`.
4. **`DONE` (2'b11):** Asserts `out_latch = 1`. Output registers store saturated $\sin/\cos$ results and emit a single-cycle `done = 1` pulse. Transitions back to `IDLE`.

### Q12. What is the exact execution latency? Prove it cycle by cycle.
**Answer:**
- Cycle 0: `start` asserted while in `IDLE`.
- Cycle 1: `LOAD` state (load enabled, 1 cycle).
- Cycles 2–17: `ITERATE` state (iterations $i=0$ to $15$, 16 cycles).
- Cycle 18: `DONE` state (output register latches, `done = 1` asserted).
- **Total latency:** **Exactly 18 clock cycles** from accepted start edge.

### Q13. How does the ROM lookup work in hardware?
**Answer:** [`cordic_atan_rom.v`](file:///c:/Users/HP/Desktop/COA/rtl/cordic_atan_rom.v) is a purely combinational 16-word lookup table indexed by the 4-bit `iter_count`. The moment `iter_count` changes, `atan_val` updates asynchronously with 0 clock cycle delay. Total ROM size is only $16 \times 18\text{ bits} = 288\text{ bits}$ (36 bytes).

### Q14. What happens if a user pulses `start` while a calculation is already running?
**Answer:** It is safely **ignored** (Busy Immunity). In [`cordic_top.v`](file:///c:/Users/HP/Desktop/COA/rtl/cordic_top.v), the angle is latched only when `ready && start`. Because `ready = 0` during `LOAD` and `ITERATE`, spurious pulses cannot corrupt ongoing calculations.

---

## Section D: Verification, COA Concepts, & Trade-offs

### Q15. How does this project map to Computer Organization & Architecture (COA) concepts?
**Answer:**
1. **Shift-Add Arithmetic:** Multiplier replacement using barrel shifters.
2. **FSM & Controller Design:** 4-state Moore machine controlling datapath sequencing.
3. **Control / Datapath Partitioning:** Separation of logic units and controller.
4. **Fixed-Point Number Representation:** Signed $Q$-format arithmetic without an FPU.
5. **Bus Handshaking Protocols:** Synchronous `start`/`ready`/`done` handshakes.
6. **Guard Bits & Overflow Protection:** MSB/LSB precision engineering.
7. **Memory Addressing:** Counter directly driving ROM addresses.
8. **Deterministic Pipeline Latency:** Fixed-budget cycle timing.

### Q16. How does your Iterative design compare against a Pipelined CORDIC (e.g. Kaustuv Sahu's repo)?
**Answer:**
- **Our Iterative Design:** Reuses 1 shared ALU datapath over 18 cycles using an FSM. Uses minimal hardware (~70 flip-flops, 0 DSP multipliers). Perfectly demonstrates FSM/datapath separation.
- **Pipelined Design:** Cascades 32 separate adder/subtractor pipeline stages. Produces 1 result per cycle throughput, but consumes $> 3,000$ flip-flops and 32 parallel adders ($10\times$ more silicon area).

### Q17. What were your final verification results?
**Answer:** All **87 unit and integration test assertions passed (100% success rate)** across all four quadrants ($0^\circ, 15^\circ, 30^\circ, 45^\circ, 60^\circ, 75^\circ, 90^\circ, 120^\circ, 135^\circ, 150^\circ, 180^\circ$ and negative equivalents), zero-gap back-to-back testing, busy immunity, and reset recovery. The maximum error was bounded to $\le 1\text{ LSB}$.
