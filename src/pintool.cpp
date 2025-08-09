// pintool.cpp – Meaningful 64-bit integer-op counter (Pin 3.31)
// Counts ADD/SUB/MUL/DIV between PIN_MARKER_START and PIN_MARKER_END.
#include "pin.H"
#include <cstdlib>
#include <iostream>
#include <string>
#include <vector>

KNOB<BOOL> KnobQuiet(KNOB_MODE_WRITEONCE, "pintool", "quiet", "0", 
                     "suppress console output");

static PIN_LOCK      g_lock;
static TLS_KEY       g_tlsKey;
static bool          g_quiet = false;

struct alignas(64) ThreadCounters {
    UINT64 add = 0, sub = 0, mul = 0, div = 0, total = 0;
    bool   counting = false;
};

static std::vector<ThreadCounters*> g_threads;

static bool Is64BitGPR(REG r) { 
    return REG_is_gr64(r) && r != REG_RSP && r != REG_RBP; 
}

static bool HasImmediate(INS ins) {
    for (UINT32 i = 0; i < INS_OperandCount(ins); ++i)
        if (INS_OperandIsImmediate(ins, i)) return true;
    return false;
}

static bool TouchesStack(INS ins) {
    for (UINT32 i = 0; i < INS_MaxNumRRegs(ins); ++i) {
        REG r = INS_RegR(ins, i);
        if (r == REG_RSP || r == REG_RBP) return true;
    }
    for (UINT32 i = 0; i < INS_MaxNumWRegs(ins); ++i) {
        REG r = INS_RegW(ins, i);
        if (r == REG_RSP || r == REG_RBP) return true;
    }
    return INS_IsStackRead(ins) || INS_IsStackWrite(ins);
}

static bool IsMeaningfulIntOp(INS ins) {
    if (HasImmediate(ins) || TouchesStack(ins)) return false;
    for (UINT32 i = 0; i < INS_MaxNumRRegs(ins); ++i)
        if (Is64BitGPR(INS_RegR(ins, i))) return true;
    for (UINT32 i = 0; i < INS_MaxNumWRegs(ins); ++i)
        if (Is64BitGPR(INS_RegW(ins, i))) return true;
    return false;
}

static ThreadCounters* State(THREADID tid) {
    return static_cast<ThreadCounters*>(PIN_GetThreadData(g_tlsKey, tid));
}

VOID StartCounting(THREADID tid) { 
    State(tid)->counting = true; 
}

VOID StopCounting(THREADID tid) { 
    State(tid)->counting = false; 
}

VOID PIN_FAST_ANALYSIS_CALL CountOp(THREADID tid, UINT32 opc) {
    ThreadCounters* tc = State(tid);
    if (!tc->counting) return;

    tc->total++;
    switch (opc) {
        case XED_ICLASS_ADD:  
        case XED_ICLASS_ADC:  
            tc->add++; 
            break;
        case XED_ICLASS_SUB:  
        case XED_ICLASS_SBB:  
            tc->sub++; 
            break;
        case XED_ICLASS_IMUL: 
        case XED_ICLASS_MUL:
        case XED_ICLASS_MULX: 
            tc->mul++; 
            break;
        case XED_ICLASS_IDIV: 
        case XED_ICLASS_DIV:  
            tc->div++; 
            break;
        default: 
            break;
    }
}

VOID InstrumentRoutine(RTN rtn, VOID*) {
    const std::string& name = RTN_Name(rtn);
    if (name == "PIN_MARKER_START") {
        RTN_Open(rtn);
        RTN_InsertCall(rtn, IPOINT_BEFORE, (AFUNPTR)StartCounting,
                       IARG_THREAD_ID, IARG_END);
        RTN_Close(rtn);
    } else if (name == "PIN_MARKER_END") {
        RTN_Open(rtn);
        RTN_InsertCall(rtn, IPOINT_BEFORE, (AFUNPTR)StopCounting,
                       IARG_THREAD_ID, IARG_END);
        RTN_Close(rtn);
    }
}

VOID InstrumentInstruction(INS ins, VOID*) {
    const xed_iclass_enum_t opc = static_cast<xed_iclass_enum_t>(INS_Opcode(ins));
    bool arith = false;
    
    switch (opc) {
        case XED_ICLASS_ADD:  
        case XED_ICLASS_ADC:
        case XED_ICLASS_SUB:  
        case XED_ICLASS_SBB:
        case XED_ICLASS_IMUL: 
        case XED_ICLASS_MUL:
        case XED_ICLASS_MULX: 
        case XED_ICLASS_IDIV:
        case XED_ICLASS_DIV:  
            arith = true; 
            break;
        default: 
            break;
    }
    
    if (arith && IsMeaningfulIntOp(ins)) {
        INS_InsertCall(ins, IPOINT_BEFORE, (AFUNPTR)CountOp,
                       IARG_FAST_ANALYSIS_CALL, IARG_THREAD_ID,
                       IARG_UINT32, opc, IARG_END);
    }
}

VOID ThreadStart(THREADID tid, CONTEXT*, INT32, VOID*) {
    auto* tc = new ThreadCounters();
    PIN_SetThreadData(g_tlsKey, tc, tid);

    PIN_GetLock(&g_lock, tid + 1);
    g_threads.push_back(tc);
    PIN_ReleaseLock(&g_lock);
}

VOID ThreadFini(THREADID, const CONTEXT*, INT32, VOID*) {}

VOID Fini(INT32, VOID*) {
    UINT64 add = 0, sub = 0, mul = 0, div = 0;
    for (ThreadCounters* tc : g_threads) {
        add += tc->add;
        sub += tc->sub;
        mul += tc->mul;
        div += tc->div;
        delete tc;
    }
    const UINT64 total = add + sub + mul + div;

    // JSON output to stdout for easy parsing
    std::cout << "{\"add\":" << add
              << ",\"sub\":" << sub
              << ",\"mul\":" << mul
              << ",\"div\":" << div
              << ",\"total\":" << total
              << "}" << std::endl;
}

int main(int argc, char* argv[]) {
    PIN_InitSymbols();
    if (PIN_Init(argc, argv)) {
        std::cerr << "Usage: pin -t <tool> -- <application>\n";
        return 1;
    }

    g_quiet = KnobQuiet.Value();
    PIN_InitLock(&g_lock);
    g_tlsKey = PIN_CreateThreadDataKey(nullptr);

    PIN_AddThreadStartFunction(ThreadStart, nullptr);
    PIN_AddThreadFiniFunction(ThreadFini, nullptr);
    RTN_AddInstrumentFunction(InstrumentRoutine, nullptr);
    INS_AddInstrumentFunction(InstrumentInstruction, nullptr);
    PIN_AddFiniFunction(Fini, nullptr);

    if (!g_quiet)
        std::cerr << "[PIN] Analysis started...\n";
    PIN_StartProgram();
    return 0;
}