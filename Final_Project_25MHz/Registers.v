module Registers(
    input         clk,
    input         RSTN,
    input         RegWrite,
    input  [4:0]  rs1,
    input  [4:0]  rs2,
    input  [4:0]  rd,
    input  [31:0] write_data,
    output [31:0] read_data1,
    output [31:0] read_data2
);
    reg [31:0] register_file [0:31];
    integer i;

    assign read_data1 = (rs1 == 5'd0) ? 32'd0 : register_file[rs1];
    assign read_data2 = (rs2 == 5'd0) ? 32'd0 : register_file[rs2];

    always @(posedge clk or negedge RSTN) begin
        if (!RSTN) begin
            for (i = 0; i < 32; i = i + 1) begin
                register_file[i] <= 32'd0;
            end
        end
        else if (RegWrite && (rd != 5'd0)) begin
            register_file[rd] <= write_data;
        end
    end
endmodule