`timescale 1ns / 1ps

// SoC Top Level
// Memory map:
//   0x0000–0x0FFF  ROM 
//   0x1000         GPIO
//   0x2000–0x2FFF  RAM 
//   0x3000–0x300F  UART 
//   0x4000-0x400F  PIC  <-- NEW
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
    logic        data_re; 

    // --- Peripheral Selection Signals ---
    logic ram_sel, ram_we, gpio_sel, gpio_we, uart_sel, uart_we, pic_sel, pic_we;
    logic [31:0] ram_rdata, gpio_rdata, uart_rdata, pic_rdata;

    // --- Interrupt Wires ---
    logic uart_irq;
    logic ext_intr;

    // --- 1. RISC-V Core ---
    riscv_core u_core (
        .clk              (clk),
        .rst_n            (rst_n),
        .ext_intr         (ext_intr),
        .instr_mem_addr   (instr_addr),
        .instr_mem_data   (instr_data),
        .instr_mem_ready  (1'b1),
        .data_mem_addr    (data_addr),
        .data_mem_wr_data (data_wdata),
        .data_mem_wr_en   (data_we),
        .data_mem_rd_en   (data_re),   
        .data_mem_rd_data (data_rdata)
    );

    // --- 1.5 Programmable Interrupt Controller (PIC) ---
    pic u_pic (
        .clk         (clk),
        .rst_n       (rst_n),
        .sel         (pic_sel),
        .we          (pic_we),
        .addr        (data_addr),
        .wdata       (data_wdata),
        .rdata       (pic_rdata),
        .irq_uart_rx (uart_irq),         // <-- From UART rx_valid
        .irq_uart_tx (1'b0),             // Tied to 0 for now
        .irq_timer   (1'b0),             // Tied to 0 for now
        .ext_intr    (ext_intr)          // To CPU
    );

    // --- 2. ROM Model ---
    rom_model u_rom (
        .en      (1'b1),
        .addr    (instr_addr),
        .rd_data (instr_data)
    );

    logic [31:0] uart_rdata_raw;
    logic [31:0] uart_rdata_sync;

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
        .uart_rdata (uart_rdata_sync),
        .pic_sel    (pic_sel),     // <-- CONNECTED TO PIC
        .pic_we     (pic_we),      // <-- CONNECTED TO PIC
        .pic_rdata  (pic_rdata)    // <-- CONNECTED TO PIC
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
        .re       (data_re), 
        .addr     (data_addr), 
        .wdata    (data_wdata),
        .rdata    (uart_rdata_raw),
        .uart_txd (soc_uart_tx),
        .uart_rxd (soc_uart_rx), 
        .uart_irq (uart_irq)  
    );

endmodule