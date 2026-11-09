// Trimmed Verilator 5 model header used by the unit tests
#ifndef VERILATED_VPORTS_H_
#define VERILATED_VPORTS_H_

#include "verilated.h"

class Vports VL_NOT_FINAL : public VerilatedModel {
  public:
    // PORTS
    // The application code writes and reads these signals to
    // propagate new values into/out from the Verilated model.
    VL_IN8(&clk,0,0);
    VL_IN8(&in_data,7,0);
    VL_IN16(&word,15,0);
    VL_INOUT8(&bus,3,0);
    VL_OUT64(&wide,40,0);
    VL_OUT8(out_data,7,0);
    VL_OUTW(&huge,99,0,4);

    explicit Vports(const char* name = "TOP");
};

#endif
