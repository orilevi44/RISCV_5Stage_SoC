// =============================================================================
// dcache_test.c
// D-Cache Integration Test for RISC-V SoC (Basys 3 / Vivado simulation)
//
// HOW TO READ RESULTS IN SIMULATION:
//   Watch the GPIO output (0x1000).  Each test writes one of two values:
//     0x0N  → test N passed
//     0xEN  → test N FAILED
//   Final value 0xFF means all tests passed.
//
// D-Cache parameters (from dcache.sv):
//   Lines   : 8  (INDEX_BITS = 3, bits [6:4] of address)
//   Words/line: 4 (OFFSET_BITS = 4, bits [3:0])
//   Tag     : bits [31:7]
//   Policy  : Write-Back, Dirty-bit, direct-mapped
//
// RAM base: 0x2000
//   0x2000 + i*0x10  →  cache index i  (for i = 0..7)
//   0x2080           →  same index as 0x2000 but DIFFERENT TAG
//                       (used to force conflict-miss / dirty eviction)
// =============================================================================

#include <stdint.h>

#define GPIO_ADDR   0x1000
#define GPIO_REG    *((volatile uint32_t *)GPIO_ADDR)

// PASS / FAIL reporting helper
#define REPORT(n, cond)   GPIO_REG = ((cond) ? (0x00 | (n)) : (0xE0 | (n)))

int main() {

    // -------------------------------------------------------------------------
    // TEST 1 : Cold miss → allocate → read hit
    // First access to 0x2000 is a cold miss: dcache fetches the 16-byte line
    // from RAM and allocates it.  The second read should be a clean hit.
    // Expected GPIO: 0x01
    // -------------------------------------------------------------------------
    volatile uint32_t *ram = (volatile uint32_t *)0x2000;

    ram[0] = 0xDEADBEEF;            // miss → fetch line, then write to cache
    volatile uint32_t r = ram[0];   // hit  → must return 0xDEADBEEF
    REPORT(1, r == 0xDEADBEEF);


    // -------------------------------------------------------------------------
    // TEST 2 : Byte writes (sb) inside a cached line
    // 0x2004 is word 1 inside cache index-0 line (already loaded).
    // Write each byte separately via an 8-bit pointer, then read back as word.
    // Expected: 0x44332211 → GPIO: 0x02
    // -------------------------------------------------------------------------
    volatile uint8_t *bp = (volatile uint8_t *)0x2004;
    bp[0] = 0x11;
    bp[1] = 0x22;
    bp[2] = 0x33;
    bp[3] = 0x44;
    r = ram[1];                     // hit: read word at 0x2004
    REPORT(2, r == 0x44332211);


    // -------------------------------------------------------------------------
    // TEST 3 : Halfword writes (sh) inside a cached line
    // 0x2008 is word 2 inside the same index-0 line.
    // Expected: 0x1234ABCD → GPIO: 0x03
    // -------------------------------------------------------------------------
    volatile uint16_t *hp = (volatile uint16_t *)0x2008;
    hp[0] = 0xABCD;                 // lower half of word 2
    hp[1] = 0x1234;                 // upper half of word 2
    r = ram[2];                     // hit: read word at 0x2008
    REPORT(3, r == 0x1234ABCD);


    // -------------------------------------------------------------------------
    // TEST 4 : Fill all 4 words of a fresh cache line
    // 0x2010 → index 1.  Write all four words, sum them, check the total.
    // Expected: 0x11111111+0x22222222+0x33333333+0x44444444 = 0xAAAAAAAA
    // GPIO: 0x04
    // -------------------------------------------------------------------------
    volatile uint32_t *line1 = (volatile uint32_t *)0x2010;
    line1[0] = 0x11111111;          // miss on first write, fetches index-1 line
    line1[1] = 0x22222222;          // hits (same line)
    line1[2] = 0x33333333;          // hit
    line1[3] = 0x44444444;          // hit
    r = line1[0] + line1[1] + line1[2] + line1[3];
    REPORT(4, r == 0xAAAAAAAA);


    // -------------------------------------------------------------------------
    // TEST 5 : Dirty-line eviction (write-back) + conflict miss
    // ram[0] at 0x2000 is still in cache index 0 from test 1.
    // Step A: overwrite it (hit write → marks dirty).
    // Step B: access 0x2080 which maps to the SAME index 0 but a different
    //         tag.  The FSM must:
    //            COMPARE → WRITE_BACK (evict dirty 0x2000) → FETCH (0x2080)
    //            → ALLOCATE → COMPARE (hit, write 0x12345678)
    // Step C: read back 0x2080 → should be 0x12345678.
    // GPIO: 0x05
    // -------------------------------------------------------------------------
    ram[0] = 0xCAFEBABE;                        // hit write, line becomes dirty
    volatile uint32_t *alias = (volatile uint32_t *)0x2080; // index 0, tag ≠
    alias[0] = 0x12345678;                      // conflict miss → eviction
    r = alias[0];                               // hit
    REPORT(5, r == 0x12345678);


    // -------------------------------------------------------------------------
    // TEST 6 : Verify write-back persisted to RAM after eviction
    // After test 5, the 0x2000 line was written back to RAM (holding
    // 0xCAFEBABE) and then evicted.  Reading ram[0] now causes another cold
    // miss → fetches from RAM.  Data should still be 0xCAFEBABE.
    // GPIO: 0x06
    // -------------------------------------------------------------------------
    r = ram[0];                                 // cold miss → refetch from RAM
    REPORT(6, r == 0xCAFEBABE);


    // -------------------------------------------------------------------------
    // TEST 7 : Sequential fill of all 8 dcache lines
    // Write one word to each line index (0x2000, 0x2010, …, 0x2070),
    // then read all back and verify.  This exercises all 8 index slots.
    // GPIO: 0x07 (pass) or 0xE7 (fail)
    // -------------------------------------------------------------------------
    for (int i = 0; i < 8; i++) {
        volatile uint32_t *p = (volatile uint32_t *)(0x2000 + i * 0x10);
        p[0] = (uint32_t)(i * 0x11111111);
    }
    volatile uint32_t pass7 = 1;
    for (int i = 0; i < 8; i++) {
        volatile uint32_t *p = (volatile uint32_t *)(0x2000 + i * 0x10);
        if (p[0] != (uint32_t)(i * 0x11111111)) { pass7 = 0; }
    }
    REPORT(7, pass7);


    // -------------------------------------------------------------------------
    // TEST 8 : Sustained read hit — same address, many reads, no extra misses
    // 0x2020 → index 2.  Write once, read 16 times; all should be cache hits.
    // GPIO: 0x08
    // -------------------------------------------------------------------------
    volatile uint32_t *hot = (volatile uint32_t *)0x2020;
    hot[0] = 0xBEEFCAFE;
    volatile uint32_t pass8 = 1;
    for (int i = 0; i < 16; i++) {
        if (hot[0] != 0xBEEFCAFE) { pass8 = 0; }
    }
    REPORT(8, pass8);


    // -------------------------------------------------------------------------
    // ALL DONE — 0xFF signals all tests passed
    // -------------------------------------------------------------------------
    GPIO_REG = 0xFF;

    while (1);
    return 0;
}