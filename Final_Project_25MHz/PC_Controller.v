module PC_Controller(
    input             CLK,
    input             RSTN,
    input             pc_write,
    input             branch_taken,
    input             jalr_taken,
    input      [31:0] branch_pc,
    input      [31:0] branch_imm,
    input      [31:0] jalr_target,
    output reg [31:0] PC
);
    reg [31:0] pc_next;

    always @* begin
        if (jalr_taken) begin
            pc_next = jalr_target;
        end
        else if (branch_taken) begin
            pc_next = branch_pc + branch_imm;
        end
        else begin
            pc_next = PC + 32'd4;
        end
    end

    always @(posedge CLK or negedge RSTN) begin
        if (!RSTN) begin
            PC <= 32'd0;
        end
        else if (pc_write) begin
            PC <= pc_next;
        end
    end
endmodule