module filter (
    input wire clk,
    input wire [7:0] in_data,
    output reg [7:0] out_data
);

    reg [7:0] shift_reg [0:3];
    wire [9:0] sum; // 10 bits to prevent overflow during addition

    assign sum = shift_reg[0] + shift_reg[1] + shift_reg[2] + shift_reg[3];

    initial begin
        shift_reg[0] = 0; shift_reg[1] = 0; 
        shift_reg[2] = 0; shift_reg[3] = 0;
        out_data = 0;
    end

    always @(posedge clk) begin
        // Shift data down the pipeline
        shift_reg[3] <= shift_reg[2];
        shift_reg[2] <= shift_reg[1];
        shift_reg[1] <= shift_reg[0];
        shift_reg[0] <= in_data;
        
        // Output the average (divide by 4 via bitshift)
        out_data <= sum[9:2];
    end

endmodule