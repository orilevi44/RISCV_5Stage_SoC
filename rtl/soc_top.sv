/**
 * SoC Top-Level Module
 * Integrates the RISC-V Core with System Bus, ROM, RAM, GPIO, and UART.
 */
module soc_top (
    input  logic        clk,          // System Clock
    input  logic        rst_n,        // Active Low Reset
    output logic [31:0] soc_gpio_out, // GPIO Output Pins
    output logic        soc_uart_tx   // UART Transmit Pin
);

    // --- Internal Bus Wires ---
    logic [31:0] instr_addr, instr_data;
    logic [31:0] data_addr, data_wdata, data_rdata;
    logic        data_we;

    // --- Peripheral Selection Signals ---
    logic ram_sel, ram_we, gpio_sel, gpio_we, uart_sel, uart_we;
    logic [31:0] ram_rdata, gpio_rdata, uart_rdata;

    // --- 1. RISC-V Core (5-Stage Pipeline) ---
    riscv_core u_core (
        .clk              (clk),
        .rst_n            (rst_n),
        .instr_mem_addr   (instr_addr),
        .instr_mem_data   (instr_data),
        .instr_mem_ready  (1'b1),
        .data_mem_addr    (data_addr),
        .data_mem_wr_data (data_wdata),
        .data_mem_wr_en   (data_we),
        .data_mem_rd_data (data_rdata)
    );

    // --- 2. ROM Model (Instruction Storage) ---
    rom_model u_rom (
        .en      (1'b1),
        .addr    (instr_addr),
        .rd_data (instr_data)
    );

    // --- 3. System Bus (Interconnect Logic) ---
    system_bus u_data_bus (
        .addr       (data_addr), 
        .wdata      (data_wdata), 
        .we         (data_we), 
        .rdata      (data_rdata),
        .rom_sel    (),           // ROM is on instruction bus, usually ignored here
        .rom_rdata  (32'b0),
        .ram_sel    (ram_sel),   
        .ram_we     (ram_we),   
        .ram_rdata  (ram_rdata),
        .gpio_sel   (gpio_sel), 
        .gpio_we    (gpio_we),  
        .gpio_rdata (gpio_rdata),
        .uart_sel   (uart_sel), 
        .uart_we    (uart_we), 
        .uart_rdata (uart_rdata)
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
        .BAUD_RATE (115_200)
    ) u_uart (
        .clk      (clk), 
        .rst_n    (rst_n),
        .sel      (uart_sel), 
        .we       (uart_we),
        .addr     (data_addr), 
        .wdata    (data_wdata),
        .rdata    (uart_rdata),
        .uart_txd (soc_uart_tx) // Physical UART TX pin
    );

endmodule