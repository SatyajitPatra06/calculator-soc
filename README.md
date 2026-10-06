# Calculator SoC — Digital Design (Verilog)

A small processor-style digital system that performs 8-bit arithmetic and logic operations, driven by
push buttons and slide switches and shown on a 6-digit multiplexed 7-segment display.
It integrates an **ALU**, **operand registers** and an **FSM controller** that sequences multi-step user input into an
operation, plus a **debounced button interface** and a **7-segment display driver** for real-time result output.

**Tools:** Verilog, SystemVerilog, Cadence Xcelium, EDA Playground

---

## Features

- 8-bit operands, **16-bit result** (so `255 × 255 = 65025` is displayed correctly)
- 8 operations: `ADD`, `SUB`, `MUL`, `DIV`, `AND`, `OR`, `XOR`, `MOD`
- **Negative results** for subtraction (`20 − 50` shows `-30`)
- **Divide / modulo by zero** is detected and the display shows `Err`
- FSM-based, step-by-step data entry with live echo of the switch value on the display
- Button **debouncing** (2-FF synchroniser + stable-time filter + edge detector)
- Binary-to-decimal conversion (double-dabble) and **leading-zero blanking** on the display
- Self-checking SystemVerilog testbench with a reference model and random regression

## Architecture

```
                  +--------------------------- calculator_top ----------------------------+
  sw[7:0]  ----+->|  2-FF sync                                                            |
  op_sel[2:0] -+  |      |                                                                |
                  |      v                  +-----------+                                |
  btn_enter --->[debounce]--enter-->+--------| calc_ctrl |--reg_a/reg_b/reg_op-->+-----+  |
  btn_clear --->[debounce]--clear-->|        |   (FSM)   |<--result/neg/err------|ALU  |  |
                  |                 |        +-----------+                       +-----+  |
                  |                 |            | disp_value / neg / err                 |
                  |                 |            v                                        |
                  |                 |        [bin2bcd] --> [seg7_driver] --> seg[6:0], an[5:0]
                  |                 |            |
                  |                 +--> led_state[2:0] (current FSM step)
                  +---------------------------------------------------------------------+
```

### Controller FSM

```
          ENTER                ENTER               ENTER
 ENTER_A ---------> ENTER_OP ---------> ENTER_B ---------> COMPUTE --(1 clk)--> RESULT
    ^  (latch A)     (latch op)          (latch B)        (latch ALU result)       |
    |                                                                              |
    +------------------------------------ ENTER -----------------------------------+
    CLEAR (from any state) --> ENTER_A, all registers cleared
```

| `led_state` | State        | What the display shows           |
|-------------|--------------|----------------------------------|
| `000`       | `ENTER_A`    | live value of `sw[7:0]`          |
| `001`       | `ENTER_OP`   | live opcode on `op_sel[2:0]`     |
| `010`       | `ENTER_B`    | live value of `sw[7:0]`          |
| `011`       | `COMPUTE`    | result (one clock only)          |
| `100`       | `RESULT`     | result, `-` sign or `Err`        |

## Operations

| `op_sel` | Operation | Notes |
|----------|-----------|-------|
| `000`    | `A + B`   | up to 510 |
| `001`    | `A − B`   | if `A < B` the magnitude is shown with a `-` sign |
| `010`    | `A × B`   | up to 65025 |
| `011`    | `A ÷ B`   | integer division, `Err` if `B = 0` |
| `100`    | `A AND B` | bitwise |
| `101`    | `A OR B`  | bitwise |
| `110`    | `A XOR B` | bitwise |
| `111`    | `A MOD B` | remainder, `Err` if `B = 0` |

## How to use it (on a board)

1. Set `sw[7:0]` to operand **A**, press **ENTER**.
2. Set `op_sel[2:0]` to the operation, press **ENTER**.
3. Set `sw[7:0]` to operand **B**, press **ENTER** — the result appears on the display.
4. Press **ENTER** again for a new calculation, or **CLEAR** at any time to abort.

Example: `20 − 50` → A = `00010100`, op = `001`, B = `00110010` → display shows `-30`.

## Interface (`calculator_top`)

| Port         | Dir | Width | Description |
|--------------|-----|-------|-------------|
| `clk`        | in  | 1     | System clock (default parameters assume 50 MHz) |
| `rst_n`      | in  | 1     | Active-low asynchronous reset |
| `sw`         | in  | 8     | Operand switches |
| `op_sel`     | in  | 3     | Operation select switches |
| `btn_enter`  | in  | 1     | Confirm current step |
| `btn_clear`  | in  | 1     | Clear everything |
| `seg`        | out | 7     | Segments `{g,f,e,d,c,b,a}` |
| `an`         | out | 6     | Digit enables (digit 0 = `an[0]`) |
| `led_state`  | out | 3     | Current FSM state |
| `dbg_result`, `dbg_neg`, `dbg_err` | out | 16 / 1 / 1 | Result register and flags (observation / debug LEDs) |

| Parameter         | Default   | Meaning |
|-------------------|-----------|---------|
| `DEBOUNCE_CYCLES` | 500 000   | Stable time before a button change is accepted (10 ms @ 50 MHz) |
| `REFRESH_CYCLES`  | 50 000    | Clocks per displayed digit (1 kHz digit rate @ 50 MHz) |
| `ACTIVE_LOW`      | 1         | 1 for common-anode displays (Basys 3, Nexys, …) |

For a different clock frequency set `DEBOUNCE_CYCLES = CLK_HZ/100` and `REFRESH_CYCLES = CLK_HZ/1000`.

## Repository layout

```
.
├── rtl/
│   ├── debounce.v         # synchroniser + debounce filter + edge detector
│   ├── alu.v              # 8 operations, 16-bit result, neg / err flags
│   ├── calc_ctrl.v        # FSM + operand / opcode / result registers
│   ├── bin2bcd.v          # 16-bit binary -> 5-digit BCD (double dabble)
│   ├── seg7_driver.v      # 6-digit multiplexed 7-segment driver
│   └── calculator_top.v   # top level
├── tb/
│   └── tb_calculator.sv   # self-checking testbench
├── Makefile
├── LICENSE
└── README.md
```

## Verification

`tb/tb_calculator.sv` drives the design exactly like a user would (switches + bouncing buttons) and ends with
`TEST PASSED` or `TEST FAILED`.

| Area | What is checked |
|------|-----------------|
| Sequencing | FSM state after every ENTER press; full `A → op → B → result → new calculation` loop |
| ALU | All 8 operations, 16-bit results, negative subtraction, divide/modulo by zero, compared with a behavioural reference model |
| Debouncing | Every press is applied with contact bounce (1-0-1-0-1); a glitch shorter than the debounce window must be ignored |
| Clear / reset | CLEAR mid-sequence and from the result state; asynchronous reset during an operation |
| Display | The testbench decodes the real `seg` / `an` pins over two full scans and compares them with the expected decimal string (blank leading zeros, `-` sign digit, `Err`); also checks `an` is always one-hot |
| Regression | 16 directed corner cases + 300 constrained-random operations (operands biased towards 0, 1, 255 and small values) |

Sample output (Icarus Verilog 12):

```
Directed tests ...
Debounce glitch test ...
Clear / reset tests ...
Random regression (300 ops) ...
--------------------------------------------------
Calculations run : 317
Op coverage      : ADD=37 SUB=40 MUL=45 DIV=44 AND=39 OR=41 XOR=38 MOD=33
Negative results : 21,  Div/Mod-by-zero errors: 9
Errors           : 0
TEST PASSED
--------------------------------------------------
```

## How to run

### Cadence Xcelium

```bash
make xcelium
# = xrun -sv -access +rwc rtl/*.v tb/tb_calculator.sv -top tb_calculator
```

### Icarus Verilog (open source)

```bash
make sim          # compile + run
make wave         # open calculator_tb.vcd in GTKWave
```

### Synopsys VCS

```bash
make vcs
```

### EDA Playground

1. Open <https://edaplayground.com> and choose **SystemVerilog/Verilog** as the language.
2. Paste `tb/tb_calculator.sv` in the **testbench** pane and all six files from `rtl/` in the **design** pane.
3. Select **Cadence Xcelium** (or any other simulator) and tick **Open EPWave after run**.
4. Run.

### Synthesis sanity check (optional)

```bash
make synth        # runs Yosys; the design synthesises without errors or warnings
```

> **Note:** `DIV` and `MOD` use the `/` and `%` operators for clarity. They synthesise to a purely combinational
> divider, which is fine for this demo clock rate; for a higher clock a multi-cycle (restoring) divider would be
> the next step.

## Waveforms

<!-- Add screenshots here, e.g.:
![Calculation waveform](docs/waveform.png)
-->

## Possible extensions

- Chained calculations (use the previous result as operand A)
- Sequential (multi-cycle) divider and multiplier for timing closure at higher clocks
- Signed operands (two's complement) and overflow flag
- FPGA bring-up with pin constraints for a development board (Basys 3 / Nexys / DE10-Lite)
- UART interface to enter expressions from a PC (see the companion UART core repository)

## License

Released under the MIT License — see [LICENSE](LICENSE).

## Author

**Satyajit Patra** — B.Tech, Electrical Engineering, Odisha University of Technology and Research
[GitHub](https://github.com/SatyajitPatra06) · [LinkedIn](https://linkedin.com/in/satyajit-patra-460541212/)
