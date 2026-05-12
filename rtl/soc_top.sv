`timescale 1ns / 1ps

// SoC Top Level
// Connects the RISC-V core, ROM, RAM, GPIO, UART, and the system bus.
// Memory map:
//   0x0000–0x0FFF  ROM  (instructions)
//   0x1000         GPIO
//   0x2000–0x2FFF  RAM  (data)
//   0x3000–0x300F  UART (TX data: 0x3000 write, RX data: 0x3000 read, status: 0x3004)
module soc_top (
    input  logic         clk,           
    input  logic         rst_n,          
    output logic [31:0]  soc_gpio_out,   
    output logic         soc_uart_tx,    
    input  logic         soc_uart_rx     
);

    // --- Internal Bus Wires ---
    logic [31:0] instr_addr, instr_data;
    logic [31:0] data_addr, data_wdata, data_rdata;
    logic        data_we;
    logic        data_re; // Read Enable from the CPU (high when a load is in MEM)

    // --- Peripheral Selection Signals ---
    logic ram_sel, ram_we, gpio_sel, gpio_we, uart_sel, uart_we;
    logic [31:0] ram_rdata, gpio_rdata, uart_rdata;

    // --- 1. RISC-V Core ---
    riscv_core u_core (
        .clk              (clk),
        .rst_n            (rst_n),
        .instr_mem_addr   (instr_addr),
        .instr_mem_data   (instr_data),
        .instr_mem_ready  (1'b1),
        .data_mem_addr    (data_addr),
        .data_mem_wr_data (data_wdata),
        .data_mem_wr_en   (data_we),
        .data_mem_rd_en   (data_re),   // Exposed to bus so peripherals know it's a read
        .data_mem_rd_data (data_rdata)
    );

    // --- 2. ROM Model ---
    rom_model u_rom (
        .en      (1'b1),
        .addr    (instr_addr),
        .rd_data (instr_data)
    );

    
    logic [31:0] uart_rdata_raw;
    logic [31:0] uart_rdata_sync;

    // uart_rdata_sync breaks the combinatorial path from uart_rdata_raw back
    // into the CPU's forwarding / hazard logic, preventing a delta-cycle loop.
    //
    // Timing analysis (2-cycle UART stall: wait_q=0 then wait_q=1):
    //
    //   Stall cycle 1 (wait_q=0): uart_rdata_sync holds the value from the
    //     PREVIOUS clock edge — may be stale "ghost" data when the bus address
    //     just changed, but the processor does NOT latch data this cycle.
    //
    //   Stall cycle 2 (wait_q=1): uart_rdata_sync captures the new
    //     uart_rdata_raw (correct for the current address) at the clock edge
    //     between cycles 1 and 2.  This is the value the processor latches.
    //
    // Ghost data in stall cycle 1 is therefore harmless; there is no need to
    // add extra address-comparison logic (which would push the valid data out
    // to a third cycle and break rx_valid detection).
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            uart_rdata_sync <= 32'b0;
        else
            uart_rdata_sync <= (data_re && uart_sel) ? uart_rdata_raw : 32'b0;
    end
    

    // --- 3. System Bus ---
    system_bus u_data_bus (
        .addr       (data_addr), 
        .wdata      (data_wdata), 
        .we         (data_we),
        .re         (data_re),    
        .rdata      (data_rdata),
        .rom_sel    (), 
        .rom_rdata  (32'b0),
        .ram_sel    (ram_sel),   
        .ram_we     (ram_we),   
        .ram_rdata  (ram_rdata),
        .gpio_sel   (gpio_sel), 
        .gpio_we    (gpio_we),  
        .gpio_rdata (gpio_rdata),
        .uart_sel   (uart_sel), 
        .uart_we    (uart_we), 
        .uart_rdata (uart_rdata_sync) // uart_rdata_sync
    );

    // --- 4. Data Memory (RAM) ---
    ram_model u_ram (
        .clk     (clk), 
        .addr    (data_addr), 
        .wr_en   (ram_we),
        .wr_data (data_wdata), 
        .rd_data (ram_rdata)
    );

    // --- 5. GPIO Peripheral ---
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
    uart_wrapper #(
        .CLK_FREQ  (100_000_000), 
        .BAUD_RATE (12_500_000)
    ) u_uart (
        .clk      (clk), 
        .rst_n    (rst_n),
        .sel      (uart_sel), 
        .we       (uart_we),
        .re       (data_re), // Passed so wrapper can detect reads vs writes
        .addr     (data_addr), 
        .wdata    (data_wdata),
        .rdata    (uart_rdata_raw),
        .uart_txd (soc_uart_tx),
        .uart_rxd (soc_uart_rx)
    );

endmodule