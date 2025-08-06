// ─────────────────────────────────────────────────────────────────────────────
// dram_counter.hpp – DRAM read/write CAS-COUNT helper
//
// Measures DRAM traffic via uncore_iMC PMU events on Intel CPUs.
// Exposes:
//
//   bool   init();        // probe PMU & open counters
//   void   start();       // reset + enable
//   void   stop();        // read + disable
//   void   print_results();  // human-readable + dumps dram_counts.out
//
// Writes dram_counts.out with
//   DRAM_READ_BYTES
//   DRAM_WRITE_BYTES
//   DRAM_TOTAL_BYTES
// ─────────────────────────────────────────────────────────────────────────────
#pragma once

#include <linux/perf_event.h>
#include <sys/ioctl.h>
#include <sys/syscall.h>
#include <unistd.h>

#include <cstdio>
#include <cstring>
#include <dirent.h>
#include <fstream>
#include <iostream>
#include <string>
#include <vector>

class DRAMCounter {
    struct Counter {
        int         fd   = -1;
        uint64_t    val  = 0;
        double      scale = 1.0;
        std::string unit;
    };

    std::vector<Counter> reads, writes;
    bool initialised = false, measuring = false;

    /*──────────────────────────── low-level helpers ─────────────────────────*/
    static long perf_event_open(struct perf_event_attr* pe,
                                pid_t pid, int cpu,
                                int group_fd, unsigned flags) {
        return syscall(__NR_perf_event_open, pe, pid, cpu, group_fd, flags);
    }

    static double read_double(const std::string& path, double def = 1.0) {
        FILE* f = fopen(path.c_str(), "r");
        if (!f) return def;
        double v = def;
        if (fscanf(f, "%lf", &v) != 1) v = def;
        fclose(f);
        return v;
    }

    static std::string read_string(const std::string& path) {
        FILE* f = fopen(path.c_str(), "r");
        if (!f) return "";
        char buf[64] = {};
        if (fscanf(f, "%63s", buf) != 1) buf[0] = '\0';
        fclose(f);
        return std::string(buf);
    }

    static std::vector<std::string> list_imc_devices() {
        std::vector<std::string> out;
        if (DIR* d = opendir("/sys/bus/event_source/devices/")) {
            while (auto* e = readdir(d)) {
                std::string n = e->d_name;
                if (n.rfind("uncore_imc", 0) == 0) out.push_back(n);
            }
            closedir(d);
        }
        return out;
    }

    /*──── parse strings like \"event=0x04,umask=0x03,cmask=0x1\" ───────────*/
    static uint64_t parse_config(const std::string& path, bool is_write) {
        FILE* f = fopen(path.c_str(), "r");
        if (!f) return is_write ? 0x0c04 : 0x0304;  // fallback defaults

        char buf[256] = {};
        if (!fgets(buf, sizeof(buf), f)) {
            fclose(f);
            return is_write ? 0x0c04 : 0x0304;
        }
        fclose(f);

        uint64_t cfg = 0;
        unsigned v   = 0;
        for (char* tok = strtok(buf, ","); tok; tok = strtok(nullptr, ",")) {
            if (sscanf(tok, "event=%x", &v)  == 1) cfg |= v;
            else if (sscanf(tok, "umask=%x", &v) == 1) cfg |= v << 8;
            else if (sscanf(tok, "edge=%x",  &v) == 1) cfg |= v << 18;
            else if (sscanf(tok, "inv=%x",   &v) == 1) cfg |= v << 23;
            else if (sscanf(tok, "cmask=%x", &v) == 1) cfg |= v << 24;
        }
        return cfg ? cfg : (is_write ? 0x0c04 : 0x0304);
    }

    Counter open_counter(const std::string& dev, bool is_write) {
        Counter c;

        /* pmu type --------------------------------------------------------- */
        int pmu_type = static_cast<int>(
            read_double("/sys/bus/event_source/devices/" + dev + "/type", -1));
        if (pmu_type < 0) return c;

        const std::string evt = is_write ? "cas_count_write" : "cas_count_read";
        const std::string base =
            "/sys/bus/event_source/devices/" + dev + "/events/";
        uint64_t cfg = parse_config(base + evt, is_write);

        struct perf_event_attr pe{};
        pe.type           = pmu_type;
        pe.size           = sizeof(pe);
        pe.config         = cfg;
        pe.disabled       = 1;
        pe.exclude_kernel = 0;
        pe.exclude_hv     = 0;

        for (int cpu = 0; cpu < 128; ++cpu) {
            int fd = perf_event_open(&pe, -1, cpu, -1, 0);
            if (fd >= 0) {
                c.fd    = fd;
                c.scale = read_double(base + evt + ".scale", 1.0);
                c.unit  = read_string(base + evt + ".unit");
                return c;
            }
        }
        return c;  // failed on all CPUs
    }

public:
    /*──────────────────────── public API ───────────────────────────────────*/
    bool init() {
        if (initialised) return true;
        auto devs = list_imc_devices();
        if (devs.empty()) {
            std::cerr << "No uncore_imc devices\n";
            return false;
        }

        for (const auto& d : devs) {
            if (auto r = open_counter(d, false); r.fd >= 0) reads.push_back(r);
            if (auto w = open_counter(d, true);  w.fd >= 0) writes.push_back(w);
        }
        initialised = !(reads.empty() && writes.empty());
        return initialised;
    }

    void start() {
        if (!initialised) return;
        auto en = [](Counter& c) {
            ioctl(c.fd, PERF_EVENT_IOC_RESET,  0);
            ioctl(c.fd, PERF_EVENT_IOC_ENABLE, 0);
        };
        for (auto& c : reads)  en(c);
        for (auto& c : writes) en(c);
        measuring = true;
    }

    void stop() {
        if (!measuring) return;
        auto grab = [](Counter& c) {
            uint64_t v = 0;
            if (read(c.fd, &v, sizeof(v)) == sizeof(v)) c.val = v;
            ioctl(c.fd, PERF_EVENT_IOC_DISABLE, 0);
        };
        for (auto& c : reads)  grab(c);
        for (auto& c : writes) grab(c);
        measuring = false;
    }

    void print_results() {
        auto to_bytes = [](double v, const std::string& unit) {
            if (unit.find("MiB") != std::string::npos) return v * 1048576;
            if (unit.find("KiB") != std::string::npos) return v * 1024;
            return v * 64;  // assume cache-lines
        };

        double rB = 0, wB = 0;
        for (const auto& c : reads)  rB += to_bytes(c.val * c.scale, c.unit);
        for (const auto& c : writes) wB += to_bytes(c.val * c.scale, c.unit);

        auto human = [](double B) {
            char buf[32];
            if (B > (1ll << 30))      sprintf(buf, "%.2f GB", B / (1ll << 30));
            else if (B > (1ll << 20)) sprintf(buf, "%.2f MB", B / (1ll << 20));
            else                      sprintf(buf, "%.0f bytes", B);
            return std::string(buf);
        };

        std::cout << "\n=== DRAM Traffic (Region) ===\n"
                  << "Read : "  << human(rB) << '\n'
                  << "Write: " << human(wB) << '\n'
                  << "Total: " << human(rB + wB) << '\n';

        std::system("mkdir -p logs");
        std::ofstream out("logs/dram_counts.out");
        out << "DRAM_READ_BYTES="  << static_cast<uint64_t>(rB)      << '\n'
            << "DRAM_WRITE_BYTES=" << static_cast<uint64_t>(wB)      << '\n'
            << "DRAM_TOTAL_BYTES=" << static_cast<uint64_t>(rB+wB)   << '\n';
    }

    ~DRAMCounter() {
        for (auto& c : reads)  if (c.fd >= 0) close(c.fd);
        for (auto& c : writes) if (c.fd >= 0) close(c.fd);
    }
};