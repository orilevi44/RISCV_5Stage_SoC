`timescale 1ns / 1ps

// SoC Top Level
// Memory map:
//   0x0000–0x0FFF  ROM
//   0x1000         GPIO
//   0x2000–0x2FFF  RAM   ← accessed through D-Cache inside riscv_core
//   0x3000–0x300F  UART
//   0x4000–0x400F  PIC
//
// D-Cache integration note:
//   The core no longer exposes raw MEM-stage signals.  Instead it exposes the
//   D-Cache's RAM bus (dcache_ram_*).  Only RAM-window traffic (0x2000–0x2FFF)
//   passes through the D-Cache FSM; MMIO addresses (GPIO, UART, PIC) bypass
//   the cache entirely and go directly to the system bus.
//   The D-Cache implements a WRITE-BACK policy with dirty-bit tracking:
//     - Write hits update the cache line only (dirty bit set); RAM is NOT written.
//     - On a conflict miss with a dirty victim, the FSM evicts the dirty line to
//       RAM (WRITE_BACK state) before fetching the new line (FETCH → ALLOCATE).
//   Evictions always write full 32-bit words to the bus (byte_en = 4'b1111),
//   because cache lines are allocated and evicted at word granularity.
module soc_top (
    input  logic         clk,
    input  logic         rst_n,
    output logic [31:0]  soc_gpio_out,
    output logic         soc_uart_tx,
    input  logic         soc_uart_rx
);

    // --- Instruction Bus ---
    logic [31:0] instr_addr, instr_data;

    // --- Data Bus (sourced from D-Cache inside core) ---
    logic [31:0] data_addr;        // dcache_ram_addr
    logic [31:0] data_wdata;       // dcache_ram_wr_data
    logic        data_we;          // dcache_ram_wr_en
    logic        data_re;          // dcache_ram_rd_en
    logic [31:0] data_rdata;       // → dcache_ram_data (back into core)

    // --- Peripheral Selection Signals ---
    logic ram_sel, ram_we, gpio_sel, gpio_we, uart_sel, uart_we, pic_sel, pic_we;
    logic [31:0] ram_rdata, gpio_rdata, uart_rdata, pic_rdata;

    // --- Interrupt Wires ---
    logic uart_irq;
    logic ext_intr;

    // --- 1. RISC-V Core (D-Cache integrated inside) ---
    (* dont_touch = "true" *)
    riscv_core u_core (
        .clk              (clk),
        .rst_n            (rst_n),
        .ext_intr         (ext_intr),

        // Legacy direct-memory interface — unused because the I-Cache inside
        // the core handles all instruction fetches via rom_addr/rom_data below.
        // Tie inputs to safe constants to silence vopt-2718 port warnings.
        .instr_mem_data   (32'b0),  // unused: I-Cache fetches via rom_*
        .instr_mem_ready  (1'b0),   // unused: I-Cache fetches via rom_*
        .instr_mem_addr   (),       // unused output — left open

        // ROM Interface (I-Cache inside core → ROM)
        .rom_addr         (instr_addr),
        .rom_data         (instr_data),
        .rom_read_en      (),

        // D-Cache → System Bus Interface
        .dcache_ram_addr    (data_addr),
        .dcache_ram_wr_data (data_wdata),
        .dcache_ram_wr_en   (data_we),
        .dcache_ram_rd_en   (data_re),
        .dcache_ram_data    (data_rdata)
    );

    // --- 1.5 Programmable Interrupt Controller (PIC) ---
    (* dont_touch = "true" *)
    pic u_pic (
        .clk         (clk),
        .rst_n       (rst_n),
        .sel         (pic_sel),
        .we          (pic_we),
        .addr        (data_addr),
        .wdata       (data_wdata),
        .rdata       (pic_rdata),
        .irq_uart_rx (uart_irq),
        .irq_uart_tx (1'b0),
        .irq_timer   (1'b0),
        .ext_intr    (ext_intr)
    );

    // --- 2. ROM Model ---
    (* dont_touch = "true" *)
    rom_model u_rom (
        .addr    (instr_addr),
        .en      (1'b1),
        .rd_data (instr_data)
    );

    // UART read-data synchroniser (one-cycle registered to align with bus)
    logic [31:0] uart_rdata_raw;
    logic [31:0] uart_rdata_sync;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            uart_rdata_sync <= 32'b0;
        else
            uart_rdata_sync <= (data_re && uart_sel) ? uart_rdata_raw : 32'b0;
    end

    // --- 3. System Bus ---
    // The D-Cache uses a Write-Back policy. When the FSM evicts a dirty cache
    // line it writes one 32-bit word per cycle to RAM; byte_en is always
    // 4'b1111 because the cache works at word granularity during eviction.
    (* dont_touch = "true" *)
    system_bus u_data_bus (
        .addr         (data_addr),
        .wdata        (data_wdata),
        .we           (data_we),
        .re           (data_re),
        .rdata        (data_rdata),
        .rom_sel      (),
        .rom_rdata    (32'b0),
        .ram_sel      (ram_sel),
        .ram_we       (ram_we),
        .ram_rdata    (ram_rdata),
        .gpio_sel     (gpio_sel),
        .gpio_we      (gpio_we),
        .gpio_rdata   (gpio_rdata),
        .uart_sel     (uart_sel),
        .uart_we      (uart_we),
        .uart_rdata   (uart_rdata_sync),
        // D-Cache write-back evictions are always full 32-bit words
        .data_byte_en (4'b1111),
        .ram_byte_en  (),          // driven by system_bus internally; RAM uses it directly
        .pic_sel      (pic_sel),
        .pic_we       (pic_we),
        .pic_rdata    (pic_rdata)
    );

    // --- 4. Data Memory (RAM) ---
    (* dont_touch = "true" *)
    ram_model u_ram (
        .clk     (clk),
        .addr    (data_addr),
        .wr_en   (ram_we),
        .wr_data (data_wdata),
        // Write-Back evictions drive full-word beats (byte_en=4'b1111).
        // Sub-word byte masking (sb/sh) is applied inside the D-Cache itself
        // at write-hit time, so the system bus always sees complete 32-bit words.
        .byte_en (4'b1111),
        .rd_data (ram_rdata)
    );

    // --- 5. GPIO Peripheral ---
    (* dont_touch = "true" *)
    gpio u_gpio (
        .clk       (clk),
        .rst_n     (rst_n),
        .sel       (gpio_sel),
        .we        (gpio_we),
        .wdata     (data_wdata),
        .rdata     (gpio_rdata),
        .gpio_pins (soc_gpio_out)
    );

    // --- 6. UART Peripheral ---
    (* dont_touch = "true" *)
    uart_wrapper #(
        .CLK_FREQ  (100_000_000),
        .BAUD_RATE (12_500_000)
    ) u_uart (
        .clk      (clk),
        .rst_n    (rst_n),
        .sel      (uart_sel),
        .we       (uart_we),
        .re       (data_re),
        .addr     (data_addr),
        .wdata    (data_wdata),
        .rdata    (uart_rdata_raw),
        .uart_txd (soc_uart_tx),
        .uart_rxd (soc_uart_rx),
        .uart_irq (uart_irq)
    );

endmodule