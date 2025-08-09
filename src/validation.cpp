// validation.cpp – Test pintool + DRAM counters
#include "dram_counter.hpp"
#include <cstdint>
#include <cstdlib>

extern "C" {
    void __attribute__((noinline)) PIN_MARKER_START() { asm volatile(""); }
    void __attribute__((noinline)) PIN_MARKER_END()   { asm volatile(""); }
}

int main() {
    // 4000 integer ops
    PIN_MARKER_START();
    uint64_t a = 1, b = 2, c = 3, d = 5;
    for (int i = 0; i < 1000; ++i) {
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
    PIN_MARKER_END();
    
    // 2 GiB DRAM traffic
    DRAMCounter dram;
    if (dram.init()) {
        constexpr size_t N = 1ULL << 30; // 1 GiB
        auto* buf = static_cast<uint8_t*>(std::aligned_alloc(64, N));
        
        dram.start();
        for (size_t i = 0; i < N; i += 64)
            *(volatile uint64_t*)(buf + i) = 0;
        
        uint64_t sum = 0;
        for (size_t i = 0; i < N; i += 64)
            sum += *(volatile uint64_t*)(buf + i);
        dram.stop();
        
        dram.print_results();
        std::free(buf);
    }
    
    return 0;
}