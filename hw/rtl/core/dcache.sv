`timescale 1ns / 1ps

/**
 * ============================================================================
 * Module      : dcache
 * Description : 32-bit Write-Back Data Cache for a RISC-V SoC.
 * * Features    : 
 * - Direct-Mapped architecture with 8 lines (CACHE_DEPTH = 8).
 * - 4-word block size (16 bytes / 128 bits per line).
 * - Write-Back policy with Dirty-Bit tracking to minimize 
 * external memory bus traffic.
 * - Byte-Enable support allowing sub-word memory operations 
 * like sb (Store Byte) and sh (Store Halfword).
 *
 * Timing Note : The attached RAM has ASYNCHRONOUS (combinational) read output. 
 * The FETCH state samples 'ram_data' on the same cycle the 
 * 'ram_addr' is driven.
 * ============================================================================
 */
module dcache (
    input  logic         clk,
    input  logic         rst_n,

    // --------------------------------------------------
    // CPU Interface (From MEM Stage)
    // --------------------------------------------------
    input  logic [31:0]  cpu_addr,   // Memory address requested by the ALU
    input  logic [31:0]  wr_data,    // Data to be written (from rs2)
    input  logic         we_en,      // Write Enable (High for Store instructions)
    input  logic         rd_en,      // Read Enable (High for Load instructions)
    input  logic [3:0]   byte_en,    // Byte mask for partial writes (sb, sh, sw)

    output logic [31:0]  cpu_data,   // Data routed back to the CPU pipeline
    output logic         cpu_stall,  // Freezes the entire pipeline on a cache miss

    // --------------------------------------------------
    // RAM / System Bus Interface (32-bit wide)
    // --------------------------------------------------
    output logic [31:0]  ram_addr,   // Address bus to Main Memory
    output logic [31:0]  ram_wr_data,// Data bus to Main Memory
    output logic         ram_wr_en,  // RAM Write Enable
    output logic         ram_rd_en,  // RAM Read Enable
    input  logic [31:0]  ram_data    // Data bus from Main Memory
);

    // ==================================================
    // Parameters & Data Structures
    // ==================================================
    localparam TAG_BITS     = 25; // 32 - 4 (offset) - 3 (index) = 25 bits
    localparam INDEX_BITS   = 3;  // 2^3 = 8 cache lines
    localparam OFFSET_BITS  = 4;  // 16 bytes per line = 4 words
    localparam DCACHE_DEPTH = 8;

    // Cache Line Structure
    typedef struct packed {
        logic                dirty; // 1 = modified by CPU, differs from RAM
        logic                valid; // 1 = contains valid data
        logic [TAG_BITS-1:0] tag;   // Address tag
        logic [127:0]        data;  // Payload: 4 words (16 bytes)
    } dcache_line_t;

    dcache_line_t dcache_mem [DCACHE_DEPTH-1:0];

    // ==================================================
    // Internal Signals & Address Decoding
    // ==================================================
    logic [24:0] req_tag;
    logic [2:0]  req_index;
    logic [3:0]  req_offset;

    assign req_tag    = cpu_addr[31:7];
    assign req_index  = cpu_addr[6:4];
    assign req_offset = cpu_addr[3:0];

    dcache_line_t current_line;
    assign current_line = dcache_mem[req_index];

    // Hit detection: Line must be valid and tags must match
    logic dcache_hit;
    assign dcache_hit = (current_line.tag == req_tag) && (current_line.valid == 1'b1);

    // Assert stall immediately if an active memory operation misses
    assign cpu_stall = (rd_en || we_en) ? !dcache_hit : 1'b0;

    // ==================================================
    // Combinational: CPU Read Routing (Hit Only)
    // ==================================================
    always_comb begin
        cpu_data = 32'b0; // Default assignment
        if (dcache_hit) begin
            // Extract the specific 32-bit word from the 128-bit block based on offset
            case (req_offset[3:2])
                2'b00: cpu_data = current_line.data[31:0];
                2'b01: cpu_data = current_line.data[63:32];
                2'b10: cpu_data = current_line.data[95:64];
                2'b11: cpu_data = current_line.data[127:96];
            endcase
        end
    end

    // ==================================================
    // FSM State Definitions
    // ==================================================
    typedef enum logic [1:0] {
        COMPARE    = 2'b00, // Check hit/miss, serve data, or write to cache
        WRITE_BACK = 2'b01, // Evict a dirty line to RAM before fetching
        FETCH      = 2'b10, // Bring 4 words from RAM to cache
        ALLOCATE   = 2'b11  // Write the new line into SRAM array
    } my_state_type_t;

    my_state_type_t state, next_state;
    logic [2:0]     fetch_counter;
    logic [127:0]   line_buffer;

    // ==================================================
    // FSM Combinational Logic — Drives RAM Interface
    // ==================================================
    always_comb begin
        // Default outputs
        ram_wr_en   = 1'b0;
        ram_rd_en   = 1'b0;
        ram_wr_data = 32'b0;
        ram_addr    = 32'b0;
        next_state  = state;

        case (state)
            COMPARE: begin
                if (dcache_hit || (!we_en && !rd_en)) begin
                    // Hit, or no active memory request (pipeline bubble / bypass).
                    // Stay idle — never fetch for a garbage/suppressed address.
                    next_state = COMPARE;
                end else if (current_line.valid && current_line.dirty) begin
                    // Conflict Miss on a Dirty Line: Must evict old data to RAM first.
                    next_state = WRITE_BACK;
                end else begin
                    // Clean/Invalid Miss: Safe to immediately fetch new data.
                    next_state = FETCH;
                end
            end

            WRITE_BACK: begin
                // Evict 4 words to RAM sequentially
                if (fetch_counter <= 3'd3) begin
                    ram_wr_en   = 1'b1;
                    ram_wr_data = current_line.data[fetch_counter * 32 +: 32];
                    
                    // Reconstruct the memory address from the OLD (evicted) tag
                    ram_addr    = {current_line.tag, req_index, fetch_counter[1:0], 2'b00};
                    next_state  = WRITE_BACK;
                end else begin
                    // Eviction complete — proceed to fetch the new line
                    next_state  = FETCH;
                end
            end

            FETCH: begin
                // Drive read address for words 0-3 (async RAM: data valid same cycle)
                if (fetch_counter <= 3'd3) begin
                    ram_rd_en = 1'b1;
                    ram_addr  = {cpu_addr[31:4], fetch_counter[1:0], 2'b00};
                end

                // After 4 address/data beats, move to ALLOCATE
                if (fetch_counter == 3'd4) begin
                    next_state = ALLOCATE;
                end else begin
                    next_state = FETCH;
                end
            end

            ALLOCATE: begin
                // FSM step to write the fully assembled buffer into cache array
                next_state = COMPARE;
            end

            default: next_state = COMPARE;
        endcase
    end

    // ==================================================
    // FSM Sequential Logic — Updates State, Counters, SRAM
    // ==================================================
    integer i;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < DCACHE_DEPTH; i++) begin
                dcache_mem[i].valid <= 1'b0;
                dcache_mem[i].dirty <= 1'b0;
            end
            state         <= COMPARE;
            fetch_counter <= 3'd0;
        end else begin
            state <= next_state;

            case (state)
                COMPARE: begin
                    if (!dcache_hit) begin
                        // Reset counter for the upcoming FETCH or WRITE_BACK state
                        fetch_counter <= 3'd0;
                    end else if (we_en) begin
                        // --- CACHE WRITE HIT ---
                        // Flag the line as modified
                        dcache_mem[req_index].dirty <= 1'b1;

                        // Apply byte-granular write using the byte_en mask (supports sb, sh, sw)
                        case (req_offset[3:2])
                            2'b00: begin
                                if (byte_en[0]) dcache_mem[req_index].data[7:0]   <= wr_data[7:0];
                                if (byte_en[1]) dcache_mem[req_index].data[15:8]  <= wr_data[15:8];
                                if (byte_en[2]) dcache_mem[req_index].data[23:16] <= wr_data[23:16];
                                if (byte_en[3]) dcache_mem[req_index].data[31:24] <= wr_data[31:24];
                            end
                            2'b01: begin
                                if (byte_en[0]) dcache_mem[req_index].data[39:32] <= wr_data[7:0];
                                if (byte_en[1]) dcache_mem[req_index].data[47:40] <= wr_data[15:8];
                                if (byte_en[2]) dcache_mem[req_index].data[55:48] <= wr_data[23:16];
                                if (byte_en[3]) dcache_mem[req_index].data[63:56] <= wr_data[31:24];
                            end
                            2'b10: begin
                                if (byte_en[0]) dcache_mem[req_index].data[71:64] <= wr_data[7:0];
                                if (byte_en[1]) dcache_mem[req_index].data[79:72] <= wr_data[15:8];
                                if (byte_en[2]) dcache_mem[req_index].data[87:80] <= wr_data[23:16];
                                if (byte_en[3]) dcache_mem[req_index].data[95:88] <= wr_data[31:24];
                            end
                            2'b11: begin
                                if (byte_en[0]) dcache_mem[req_index].data[103:96]  <= wr_data[7:0];
                                if (byte_en[1]) dcache_mem[req_index].data[111:104] <= wr_data[15:8];
                                if (byte_en[2]) dcache_mem[req_index].data[119:112] <= wr_data[23:16];
                                if (byte_en[3]) dcache_mem[req_index].data[127:120] <= wr_data[31:24];
                            end
                        endcase
                    end
                end

                WRITE_BACK: begin
                    // Advance counter sequentially for 4 words
                    if (fetch_counter <= 3'd3) begin
                        fetch_counter <= fetch_counter + 3'd1;
                    end else begin
                        fetch_counter <= 3'd0; // Reset before FETCH begins
                    end
                end

                FETCH: begin
                    // Capture incoming async RAM data into the 128-bit line buffer
                    if (fetch_counter <= 3'd3) begin
                        line_buffer[fetch_counter * 32 +: 32] <= ram_data;
                    end

                    // Manage counter
                    if (fetch_counter <= 3'd4) begin
                        fetch_counter <= fetch_counter + 3'd1;
                    end else begin
                        fetch_counter <= 3'd0;
                    end
                end

                ALLOCATE: begin
                    // Install the filled line buffer into the cache array.
                    // The line is clean (dirty=0) because it matches main memory.
                    dcache_mem[req_index] <= '{
                        valid: 1'b1,
                        dirty: 1'b0,
                        tag:   req_tag,
                        data:  line_buffer
                    };
                end
            endcase
        end
    end

endmodule