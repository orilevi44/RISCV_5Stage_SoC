int main() {
    // --------------------------------------------------------
    // Micro-Benchmark: Load-Use Hazard Detection
    // --------------------------------------------------------
    // We bypass the C compiler's optimization using pure inline
    // assembly to guarantee back-to-back execution.
    
    __asm__ volatile (
        "li x10, 0x2000 \n\t"     // Load address 0x2000 into register x10
        "li x11, 42 \n\t"         // Load value 42 into register x11
        "sw x11, 0(x10) \n\t"     // STORE: Write 42 to memory at [0x2000]
        
        // --- THE HAZARD ZONE ---
        "lw x12, 0(x10) \n\t"     // LOAD: Read from memory at [0x2000] into x12
        "add x13, x12, x12 \n\t"  // USE: Immediately use x12! (Must stall here)
        // -----------------------
    );

    // Infinite loop to keep the processor running
    while(1);
    return 0;
}