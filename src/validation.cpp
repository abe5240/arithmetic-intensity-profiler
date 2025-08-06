// validation.cpp – End-to-end sanity test for pintool + DRAM counters
#include "dram_counter.hpp"
#include <cstdint>
#include <cstdio>
#include <cstdlib>

extern "C" {
    void __attribute__((noinline)) PIN_MARKER_START() { asm volatile(""); }
    void __attribute__((noinline)) PIN_MARKER_END()   { asm volatile(""); }
}

static DRAMCounter g_dram;

// ── arithmetic kernel (4 000 ops) ────────────────────────────────────────────
static void ArithmeticKernel() {
    constexpr int ITERS = 1'000; // 4 ops × 1 000 = 4 000

    uint64_t a = 1, b = 2, c = 3, d = 5;
    for (int i = 0; i < ITERS; ++i) {
        asm volatile(
            "addq  %[b], %[a]\n\t"
            "subq  %[d], %[c]\n\t"
            "imulq %[a], %[b]\n\t"
            "xorq  %%rdx, %%rdx\n\t"
            "movq  %[a], %%rax\n\t"
            "divq  %[c]\n\t"
            : [a] "+r"(a), [b] "+r"(b), [c] "+r"(c)
            : [d] "r"(d)
            : "rax", "rdx", "cc");
    }
}

static void MeasureArithmetic() {
    constexpr size_t N = 1ULL << 30; // 1 GiB
    auto* buf = static_cast<uint8_t*>(std::aligned_alloc(64, N));

    // Measure arithmetic kernel (but don't save to file)
    PIN_MARKER_START();
    g_dram.start();
    ArithmeticKernel();
    g_dram.stop();
    PIN_MARKER_END();

    std::puts("\n=== Arithmetic Kernel (Measured) ===");
    std::puts("Expected: 4 000 integer ops, <2 MiB DRAM\n");
    g_dram.print_results(false);  // Don't save

    // Measure bandwidth test (save this one to file)
    std::puts("\n=== DRAM Bandwidth Test ===");
    g_dram.start();

    // Write phase
    for (size_t i = 0; i < N; i += 64)
        *(volatile uint64_t*)(buf + i) = 0;

    // Read phase
    uint64_t sum = 0;
    for (size_t i = 0; i < N; i += 64)
        sum += *(volatile uint64_t*)(buf + i);

    g_dram.stop();
    g_dram.print_results(true);  // Save this measurement

    std::free(buf);
    std::printf("\nChecksum: %llu\n", (unsigned long long)sum);
}

int main() {
    std::puts("=== Arithmetic Intensity Validation Test ===\n");

    if (!g_dram.init())
        std::puts("Warning: DRAM counters not initialised – try sudo");

    MeasureArithmetic();
    std::puts("\n=== Test Complete ===");
    return 0;
}