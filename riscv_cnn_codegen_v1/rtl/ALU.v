module ALU(
    input  signed [31:0] data_a,
    input  signed [31:0] data_b,
    input  [1:0]         alu_op,
    output reg [31:0]    result,
    output               eq,
    output               lt
);
    localparam [1:0] ALU_ADD = 2'b00,
                     ALU_SUB = 2'b01,
                     ALU_SLT = 2'b10;

    assign eq = (data_a == data_b);
    assign lt = ($signed(data_a) < $signed(data_b));

    always @* begin
        case (alu_op)
            ALU_ADD: result = data_a + data_b;
            ALU_SUB: result = data_a - data_b;
            ALU_SLT: result = lt ? 32'd1 : 32'd0;
            default: result = 32'd0;
        endcase
    end
endmodule
