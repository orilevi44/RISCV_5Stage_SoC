module soc_top (
    input  logic clk,
    input  logic rst_n,
    output logic [31:0] soc_gpio_out
);

    // --- Internal Wires ---
    logic [31:0] instr_addr, instr_data;
    logic [31:0] data_addr, data_wdata, data_rdata;
    logic        data_we;

    logic ram_sel, ram_we, gpio_sel, gpio_we;
    logic [31:0] ram_rdata, gpio_rdata;

    // 1. RISC-V Core (5-Stage Pipeline)
    riscv_core u_core (
        .clk(clk), .rst_n(rst_n),
        .instr_mem_addr(instr_addr),
        .instr_mem_data(instr_data),
        .instr_mem_ready(1'b1),
        .data_mem_addr(data_addr),
        .data_mem_wr_data(data_wdata),
        .data_mem_wr_en(data_we),
        .data_mem_rd_data(data_rdata)
    );

    // 2. ROM Model (Instructions)
    rom_model u_rom (
        .en(1'b1),
        .addr(instr_addr),
        .rd_data(instr_data)
    );

    // 3. System Bus (Memory Map Control)
    system_bus u_data_bus (
        .addr(data_addr), .wdata(data_wdata), .we(data_we), .rdata(data_rdata),
        .rom_sel(), 
        .rom_rdata(32'b0),
        .ram_sel(ram_sel),   .ram_we(ram_we),   .ram_rdata(ram_rdata),
        .gpio_sel(gpio_sel), .gpio_we(gpio_we), .gpio_rdata(gpio_rdata)
    );

    // 4. Peripherals (RAM & GPIO)
    ram_model u_ram (
        .clk(clk), 
        .addr(data_addr), 
        .wr_en(ram_we),      // Connected to Bus WE
        .wr_data(data_wdata), 
        .rd_data(ram_rdata)
    );

    gpio u_gpio (
        .clk(clk), .rst_n(rst_n), 
        .sel(gpio_sel), 
        .we(gpio_we),        // Connected to Bus WE
        .wdata(data_wdata), 
        .rdata(gpio_rdata), 
        .gpio_pins(soc_gpio_out)
    );

endmodule