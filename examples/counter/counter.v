`include "consts.vh"

// Two-clock counter used by the tutorials and the integration tests.
//  - count:      adds `step` on every rising edge of clk
//  - slow_count: adds 1 on every rising edge of clk_slow
//  - wide_out:   ~wide_in (100 bits), upper: wide_in[99:36] (64 bits)
//  - init_val:   the INIT_VAL macro (from include/consts.vh or a define)
module counter #(parameter WIDTH = 8) (
    input  wire             clk,
    input  wire             clk_slow,
    input  wire             rst,
    input  wire [WIDTH-1:0] step,
    input  wire [99:0]      wide_in,
    output wire [99:0]      wide_out,
    output wire [63:0]      upper,
    output wire [7:0]       init_val,
    output reg  [WIDTH-1:0] count,
    output reg  [15:0]      slow_count
);
    inverter #(.W(100)) inv (.a(wide_in), .y(wide_out));

    assign upper    = wide_in[99:36];
    assign init_val = `INIT_VAL;

    always @(posedge clk)
        if (rst) count <= {WIDTH{1'b0}};
        else     count <= count + step;

    always @(posedge clk_slow)
        if (rst) slow_count <= 16'd0;
        else     slow_count <= slow_count + 16'd1;
endmodule
