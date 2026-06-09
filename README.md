# RISC-V RV32I SoC — 5-Stage Pipelined Processor on Basys 3 FPGA

A fully synthesizable, single-core System-on-Chip implemented in SystemVerilog, targeting the Digilent Basys 3 (Xilinx Artix-7). The processor implements the RV32I base integer instruction set with a classic 5-stage in-order pipeline, a two-level memory hierarchy (I-Cache + D-Cache), a UART/GPIO peripheral subsystem, and a machine-mode interrupt controller.

---

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [Pipeline Stages](#pipeline-stages)
- [Memory Hierarchy](#memory-hierarchy)
- [Key Implementation Details](#key-implementation-details)
- [Peripheral Subsystem](#peripheral-subsystem)
- [Repository Structure](#repository-structure)
- [Getting Started](#getting-started)
- [Testing & Verification](#testing--verification)
- [UVM Verification Environment](#uvm-verification-environment)
- [Future Improvements](#future-improvements)

---

## Architecture Overview

```
 ┌────────────────────────────────────────────────────────────────┐
 │                          SoC Top                               │
 │                                                                │
 │   ┌──────────┐    ┌────────────────────────────────────────┐   │
 │   │   ROM    │◄───│                                        │   │
 │   │(Instr.   │    │            RISC-V Core                 │   │
 │   │ Memory)  │    │         (5-Stage Pipeline)             │   │
 │   └──────────┘    │                                        │   │
 │                   │   IF → ID → EX → MEM → WB              │   │
 │   ┌──────────┐    │                                        │   │
 │   │   RAM    │◄──►│   I-Cache          D-Cache             │   │
 │   │  (Data   │    │  (Direct-Map)    (Write-Back)          │   │
 │   │ Memory)  │    │                                        │   │
 │   └──────────┘    └──────────────────┬─────────────────────┘   │
 │                                      │ System Bus              │
 │              ┌───────────────────────┼────────────────┐        │
 │              │                       │                │        │
 │         ┌────▼────┐            ┌─────▼───┐      ┌─────▼───┐    │
 │         │  UART   │            │  GPIO   │      │   PIC   │    │
 │         │(TX/RX)  │            │(32-bit) │      │ (Intr.) │    │
 │         └─────────┘            └─────────┘      └─────────┘    │
 └────────────────────────────────────────────────────────────────┘
```

---

## Pipeline Stages

The processor implements the classic 5-stage RISC pipeline. Each stage is separated by a registered pipeline latch (`IF/ID`, `ID/EX`, `EX/MEM`, `MEM/WB`), allowing a new instruction to be issued every cycle under ideal conditions.

| Stage | Module | Description |
|-------|--------|-------------|
| **IF** — Instruction Fetch | `fetch_stage.sv` | Drives the PC, interfaces with the I-Cache. On a cache miss, the Hazard Unit freezes this stage until the line is filled. |
| **ID** — Instruction Decode | `decode_stage.sv` | Decodes the instruction, reads the register file, and generates all pipeline control signals and the sign-extended immediate. |
| **EX** — Execute | `execute_stage.sv` | Runs the ALU, resolves branch/jump targets, and applies operand forwarding from MEM/WB. Also interfaces with the CSR unit for interrupt handling. |
| **MEM** — Memory Access | `memory_stage.sv` | Issues load/store requests to the D-Cache. Computes branch-taken decisions and drives the memory bus byte-enable signals. |
| **WB** — Write-Back | `writeback_stage.sv` | Selects between the ALU result and the loaded memory value, writing the final result back to the register file. |

---

## Memory Hierarchy

### Instruction Cache (`icache.sv`)

A direct-mapped, read-only cache that sits between the Fetch stage and the ROM.

- **Organization:** 8 sets × 1 way × 128-bit cache lines (4 × 32-bit words per line)
- **Address breakdown:** `TAG[31:7]` | `INDEX[6:4]` | `OFFSET[3:0]`
- **Miss policy:** 3-state FSM — `COMPARE → FETCH → ALLOCATE`. On a miss the FSM issues four sequential word reads from ROM to fill the line buffer, then writes the complete line in one clock cycle.
- **Pipeline integration:** A `cpu_stall` signal is routed to the Hazard Detection Unit, which freezes the PC and the IF/ID register, injecting a NOP bubble into the ID/EX stage to prevent data corruption during the fill.

### Data Cache (`dcache.sv`)

A direct-mapped, read/write cache that sits between the Memory stage and the RAM.

- **Organization:** 8 sets × 1 way × 128-bit cache lines
- **Write policy:** **Write-Back with a dirty bit.** Writes hit the cache immediately and mark the line dirty; the modified line is only evicted to RAM when a conflicting miss occurs.
- **Byte-enable support:** Per-byte write masking (`byte_en[3:0]`) ensures `SB`, `SH`, and `SW` instructions all update only their target bytes within the cached line, preserving the integrity of neighbouring bytes.
- **Miss policy:** 4-state FSM — `COMPARE → WRITE_BACK → FETCH → ALLOCATE`. If the evicted line is dirty, its four words are written back to RAM before fetching the new line.

---

## Key Implementation Details

### Hazard Detection Unit (`hazard_detection_unit.sv`)

The unit resolves four distinct hazard classes in strict priority order:

1. **Branch/Jump Flush** — On a taken branch (resolved in MEM), flushes the three speculatively-fetched instructions by asserting `if_id_flush`, `id_ex_flush`, and `ex_mem_flush` simultaneously.
2. **I-Cache Miss Stall** — Freezes the PC (`if_pc_en = 0`) and the IF/ID latch (`id_reg_en = 0`), while flushing the ID/EX latch to prevent the stale instruction from propagating.
3. **UART Wait-State** — Detects a load targeting the UART address window (`0x3000–0x300F`) and inserts exactly one stall cycle to guarantee the peripheral's read data is stable.
4. **Load-Use Stall** — Detects when an instruction in EX is a load whose destination matches a source register of the instruction in ID. Stalls fetch/decode for one cycle and injects a NOP bubble.

All flush signals are ORed with the trap/`mret` flush from the CSR unit, ensuring interrupt entry and return cleanly drain the pipeline.

### Forwarding Unit (`forwarding_unit.sv`)

Resolves RAW (Read-After-Write) data hazards for back-to-back ALU instructions without stalling the pipeline.

- **MEM → EX forward** (`forward_sel = 2'b10`): highest priority; used when the instruction two stages ahead wrote a register the current EX stage reads.
- **WB → EX forward** (`forward_sel = 2'b01`): used for the three-stage gap case.
- **Guard conditions:** Forwarding is suppressed for writes to `x0` and for source registers that the current instruction does not actually read (`rs1_used` / `rs2_used` flags from the decoder), preventing spurious forwarding on instructions like `LUI` or `AUIPC`.

### CSR Unit & Interrupt Handling (`csr_unit.sv`)

Implements a subset of the RISC-V machine-mode privileged architecture:

- **Registers:** `mstatus` (MIE/MPIE), `mtvec` (ISR vector), `mepc` (exception PC), `mcycle` (64-bit cycle counter), `minstret` (64-bit retired-instruction counter).
- **Trap entry:** When an external interrupt is asserted and `mstatus.MIE` is set, `take_trap` is raised, the current PC is saved to `mepc`, MIE is cleared, and the PC mux jumps to `mtvec`.
- **Trap return:** The `mret` instruction is detected in EX. The pipeline is flushed and the PC is restored from `mepc`.

---

## Peripheral Subsystem

All peripherals are memory-mapped and accessed via a central system bus (`system_bus.sv`).

| Peripheral | Base Address | Description |
|------------|-------------|-------------|
| UART | `0x3000` | 8-N-1 serial transceiver (configurable baud rate). Supports interrupt-driven RX via the PIC. |
| GPIO | `0x4000` | 32-bit output register driving external SoC pins. |
| PIC | — | Programmable Interrupt Controller; routes peripheral IRQs to the CSR unit's `ext_intr` input. |

---

## Repository Structure

```
.
├── src/
│   ├── core/
│   │   ├── fetch_stage.sv
│   │   ├── decode_stage.sv
│   │   ├── execute_stage.sv
│   │   ├── memory_stage.sv
│   │   ├── writeback_stage.sv
│   │   ├── forwarding_unit.sv
│   │   ├── hazard_detection_unit.sv
│   │   ├── csr_unit.sv
│   │   ├── alu.sv
│   │   ├── alu_control.sv
│   │   ├── reg_file.sv
│   │   ├── imm_gen.sv
│   │   └── riscv_core.sv
│   ├── cache/
│   │   ├── icache.sv
│   │   └── dcache.sv
│   ├── peripherals/
│   │   ├── uart_tx.sv
│   │   ├── uart_rx.sv
│   │   ├── uart_wrapper.sv
│   │   ├── gpio.sv
│   │   └── pic.sv
│   └── soc_top.sv
├── tb/
│   ├── soc_tb.sv
│   ├── riscv_tb.sv
│   ├── icache_tb.sv
│   ├── memory_tb.sv
│   ├── alu_basic_tb.sv
│   ├── alu_branch_tb.sv
│   ├── alu_forwarding_tb.sv
│   ├── echo_test_tb.sv
│   └── echo_intr_tb.sv
├── tests/
│   ├── c_tests/
│   │   ├── add_test.c
│   │   ├── branch_test.c
│   │   ├── hazard_test.c
│   │   ├── load_branch_hazard.c
│   │   ├── double_hazard_test.c
│   │   ├── isa_test.c
│   │   ├── icache_stress.c
│   │   └── test_fibonacci.c
│   └── asm_tests/
│       └── cache_loop.asm
├── sim/
│   └── program.hex
├── build.bat           (C firmware build script)
├── build_asm.bat       (Assembly firmware build script)
└── link.ld
```

---

## Getting Started

### Prerequisites

- **Xilinx Vivado** (2020.x or later) with XSim for simulation
- **RISC-V GNU Toolchain** — `riscv-none-elf-gcc`, `riscv-none-elf-objcopy`, `riscv-none-elf-objdump`

### 1. Compile Firmware

Build a C test and generate the memory image:

```bat
:: Compile a C test (defaults to tests/c_tests/add_test.c)
build.bat tests/c_tests/hazard_test.c

:: Outputs:
::   firmware.mem  — Verilog $readmemh-compatible hex image
::   asm.txt       — disassembly for debug reference
```

Or assemble a raw assembly test directly:

```bat
build_asm.bat tests/asm_tests/cache_loop.asm
```

Both scripts use `rv32i` / `ilp32` ABI and link at address `0x00000000`.

### 2. Run Simulation in Vivado / XSim

1. Open or create a Vivado project and add all `.sv` files from `src/` and `tb/`.
2. Set `soc_tb.sv` as the simulation top module.
3. The testbench auto-loads `sim/program.hex` into the ROM model at time 0:
   ```systemverilog
   $readmemh("sim/program.hex", uut.u_rom.mem);
   ```
4. Copy your compiled `firmware.mem` to `sim/program.hex`, then launch simulation:
   ```
   Vivado → Flow → Run Simulation → Run Behavioral Simulation
   ```
5. Waveforms are dumped to `sim/waves.fst` for offline viewing (e.g., GTKWave).

---

## Testing & Verification

The project includes **9 targeted testbenches** covering the full design stack, from individual units up to full SoC integration:

| Testbench | Scope |
|-----------|-------|
| `alu_basic_tb` | ALU arithmetic and logic operations |
| `alu_branch_tb` | Branch condition evaluation |
| `alu_forwarding_tb` | Operand forwarding path correctness |
| `icache_tb` | I-Cache hit/miss FSM, line fill, stall signalling |
| `memory_tb` | D-Cache write-back and byte-enable correctness |
| `riscv_tb` | Core-level integration: hazards, forwarding, branches |
| `soc_tb` | Full SoC: UART I/O, memory-mapped peripherals, interrupts |
| `echo_test_tb` | UART echo loop (polling mode) |
| `echo_intr_tb` | UART echo loop (interrupt-driven mode) |

**8 cache-consistency integration tests** have been verified, confirming correct behaviour across I-Cache cold-start misses, D-Cache write-back eviction, and concurrent pipeline stalls from both caches.

---

## UVM Verification Environment

The RISC-V SoC is verified using a full **UVM 1.2** testbench running on Siemens Questa 2025.2. The environment provides a self-checking, reusable verification infrastructure with a built-in golden reference model (ISS), backdoor ROM loading, and an in-order scoreboard.

---

### Testbench Architecture

```
riscv_uvm_tb  (Top-level HDL module — instantiates DUT + virtual interface)
│
│   ┌─────────────────────────────────────────────┐
│   │  riscv_if  (SystemVerilog Virtual Interface) │
│   │  • clocking block (monitor_cb)               │
│   │  • DUT control signals: clk, rst_n           │
│   │  • Probed signals: we, write_reg, write_data │
│   └─────────────────────────────────────────────┘
│
└── uvm_test_top : riscv_load_store_test  (extends riscv_test)
    │
    └── env : riscv_env
        │
        ├── agent : riscv_agent
        │   │
        │   ├── sequencer : uvm_sequencer #(riscv_seq_item)
        │   │
        │   ├── driver : riscv_driver
        │   │   ├── Backdoor ROM load  (uvm_hdl_deposit)
        │   │   ├── Reset lifecycle    (uvm_hdl_force / uvm_hdl_release)
        │   │   └── analysis port  ──────────────────────────────────────┐
        │   │                                                             │
        │   └── monitor : riscv_monitor                                  │
        │       ├── Clocking-block sampling of reg_file write port        │
        │       └── analysis port  ──────────────────────────────────┐   │
        │                                                             │   │
        └── scoreboard : riscv_scoreboard                            │   │
            ├── observed_imp  ◄───────────────────────────────────────┘   │
            └── expected_imp  ◄───────────────────────────────────────────┘
```

---

### Component Overview

| Component | Role |
|-----------|------|
| **`riscv_uvm_tb`** | Top-level **HDL wrapper**. Instantiates the `soc_top` DUT and the `riscv_if` virtual interface, drives the clock, and maps the interface handle into `uvm_config_db` so all UVM components can access DUT signals without a direct hierarchical reference. |
| **`riscv_test`** | **Test orchestration layer** (abstract base). Builds the environment, starts the target sequence on the sequencer, and controls the run-phase timeout budget. Concrete test classes (e.g. `riscv_load_store_test`) extend this base and supply the sequence under test. |
| **`riscv_env`** | **Environment container**. Constructs and connects all sub-components. Wires the driver's `analysis_port` to the scoreboard's `expected_imp` TLM port, and the monitor's `analysis_port` to the scoreboard's `observed_imp` TLM port. |
| **`riscv_agent`** | **Active agent**. Encapsulates the sequencer, driver, and monitor into a single reusable unit. The sequencer arbitrates sequence items from the active test and forwards them to the driver via a standard TLM pull interface. |
| **`riscv_driver`** | **Stimulus executor**. Receives a `riscv_seq_item` containing the assembled program words and expected register writes. Performs the full reset lifecycle (assert reset → backdoor-load ROM → publish expected writes to scoreboard → release reset → wait for program completion). |
| **`riscv_monitor`** | **Passive observer**. Samples the register file's synchronous write port (`we`, `write_reg`, `write_data`) on every rising clock edge using a **clocking block**, making all sampling race-free. Whenever `we=1` and `write_reg≠x0`, it packages the observed write into a `riscv_seq_item` and broadcasts it to the scoreboard via its analysis port. |
| **`riscv_scoreboard`** | **In-order checker**. Maintains two TLM analysis-imp ports: `expected_imp` (fed by the driver before reset is released) and `observed_imp` (fed by the monitor during execution). Expected writes are held in a FIFO queue. Each observed write is dequeued and compared against the next expected entry — checking both the destination register number and the data value. Reports `PASS`/`FAIL` per write and a final summary at end-of-test. |
| **`riscv_iss`** | **Golden Reference Model** (Instruction Set Simulator), embedded directly inside the test sequence. Before the program is sent to the driver, the ISS executes the same instruction stream in software and produces the authoritative list of `(register, value)` pairs that the real hardware must match. This list is what the driver forwards to the scoreboard's expected queue. |

---

### Backdoor ROM Loading Mechanism

On remote simulation platforms such as EDA Playground, the ROM model's `$readmemh` call fails because the local firmware path does not exist on the server's filesystem:

```
Warning: Failed to open readmem file ".../firmware.mem"  (ENOENT)
```

To work around this without modifying the RTL, the UVM driver uses **runtime VPI backdoor access** via the UVM standard `uvm_hdl_deposit` API instead of a compile-time `force` statement.

**Why `force` cannot be used inside a UVM package:**

Questa resolves hierarchical paths in `force` statements at **compile time**, before the module hierarchy exists. A path such as `riscv_uvm_tb.uut.u_rom.mem[i]` inside a package triggers a fatal `vlog-7027` error because the package is compiled before the testbench module is elaborated.

**The `uvm_hdl_deposit` solution:**

```systemverilog
// In riscv_driver — called before reset is released
localparam string ROM_PATH = "riscv_uvm_tb.uut.u_rom.mem";

task backdoor_load_rom(input logic [31:0] words[$]);
    string elem_path;
    logic [31:0] word;
    for (int i = 0; i < 1024; i++) begin
        word      = (i < int'(words.size())) ? words[i] : 32'h00000013; // NOP padding
        elem_path = $sformatf("%s[%0d]", ROM_PATH, i);
        if (!uvm_hdl_deposit(elem_path, word))
            `uvm_error("DRV", $sformatf("uvm_hdl_deposit FAILED: %s", elem_path))
    end
endtask
```

| Property | Detail |
|----------|--------|
| **Path resolution** | String evaluated at **runtime** by the VPI layer — no compile-time hierarchy dependency |
| **Access grant** | Questa's `-access=rw+/.` flag (passed automatically by EDA Playground) enables full VPI read/write access to all signals |
| **Reset signal** | `rst_n` is controlled the same way via `uvm_hdl_force` / `uvm_hdl_release` using the path `"riscv_uvm_tb.rst_n"` |
| **Portability** | Works on any UVM-compliant simulator that supports the `uvm_hdl_*` DPI-C backdoor API |

The complete load sequence in the driver's `run_phase` is:

```
1. uvm_hdl_force  rst_n = 0        (hold reset)
2. uvm_hdl_deposit mem[0..1023]    (write program words into ROM)
3. write_expected_to_scoreboard()  (publish golden results before reset release)
4. wait 10 clock cycles
5. uvm_hdl_release rst_n           (release reset — pipeline begins fetching)
6. wait run_cycles clock cycles    (allow program to complete)
```

This approach fully decouples the verification environment from the host filesystem and makes the testbench portable to any remote simulator or CI environment.

---

### Verification Results

| Test | Instructions | Expected Writes | Result |
|------|-------------|-----------------|--------|
| `riscv_load_store_test` | 10 (LUI, ADDI, SW, LW, SB, LBU, LB, SH, LHU, JAL) | 6 | ✅ **6 / 6 PASSED** |

Verified register writes:

| Register | Instruction | Value | Notes |
|----------|------------|-------|-------|
| `x1` | `LUI x1, 2` | `0x00002000` | Base address |
| `x2` | `ADDI x2, x0, 171` | `0x000000AB` | Byte value |
| `x3` | `LW x3, 0(x1)` | `0x000000AB` | 32-bit word load |
| `x4` | `LBU x4, 4(x1)` | `0x000000AB` | Byte load — zero extended |
| `x5` | `LB x5, 4(x1)` | `0xFFFFFFAB` | Byte load — **sign extended** (bit 7 = 1) |
| `x6` | `LHU x6, 8(x1)` | `0x000000AB` | Halfword load — zero extended |

---

## Future Improvements

**1. Dynamic Branch Prediction (2-bit Saturating Counter)**
The current design resolves branches in the MEM stage, incurring a 3-cycle penalty on every taken branch. A BTB (Branch Target Buffer) with 2-bit saturating counters in the Fetch stage would eliminate most of this penalty for loop-heavy workloads, significantly improving IPC.

**2. AXI4-Lite Bus Interface**
The custom system bus could be replaced with an industry-standard AXI4-Lite interconnect. This would make the SoC immediately compatible with Xilinx IP (DDR controllers, DMA engines, Ethernet MACs) and is the natural next step toward a production-quality embedded system.

**3. Instruction and Data TLB / Virtual Memory (Sv32)**
Adding a 16-entry fully-associative TLB and implementing the RISC-V Sv32 page-table walker would bring the design to a supervisor-capable (S-mode) processor, enabling it to run a lightweight RTOS or a bare-metal port of Linux.
