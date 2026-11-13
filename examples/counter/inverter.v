// Bitwise inverter, kept in its own file to show multi-file builds.
module inverter #(parameter W = 100) (
    input  wire [W-1:0] a,
    output wire [W-1:0] y
);
    assign y = ~a;
endmodule
