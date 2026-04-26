`ifndef INSTR_MEM_INIT_FILE
`define INSTR_MEM_INIT_FILE "instr_mem.mem"
`endif

module Instruction_Memory(
    input         clka,
    input  [9:0]  addra,
    output [31:0] douta
);
    reg [31:0] mem [0:1023];
    reg [31:0] douta_r;
    integer i;

    assign douta = douta_r;

    initial begin
        for (i = 0; i < 1024; i = i + 1) begin
            mem[i] = 32'd0;
        end
        $readmemh(`INSTR_MEM_INIT_FILE, mem);
    end

    always @(posedge clka) begin
        douta_r <= mem[addra];
    end
endmodule
