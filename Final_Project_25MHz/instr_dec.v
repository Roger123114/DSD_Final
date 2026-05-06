module instr_dec(
    input  [31:0] instr,
    output [4:0]  rs1_addr,
    output [4:0]  rs2_addr,
    output [4:0]  rd,
    output reg [10:0] ctrl_sig,
    output reg [31:0] imm
);
    // ctrl_sig[10]   : valid
    // ctrl_sig[9]    : reg_we
    // ctrl_sig[8]    : alu_src_imm
    // ctrl_sig[7]    : mem_we
    // ctrl_sig[6:5]  : wb_sel   2'b00=ALU, 2'b01=MEM, 2'b10=PC+4, 2'b11=NONE
    // ctrl_sig[4:3]  : br_type  2'b00=NONE, 2'b01=BEQ, 2'b10=BLT
    // ctrl_sig[2]    : jalr
    // ctrl_sig[1:0]  : alu_op   2'b00=ADD, 2'b01=SUB, 2'b10=SLL, 2'b11=SRA

    localparam [6:0] OPCODE_OP     = 7'b0110011;
    localparam [6:0] OPCODE_OP_IMM = 7'b0010011;
    localparam [6:0] OPCODE_LOAD   = 7'b0000011;
    localparam [6:0] OPCODE_STORE  = 7'b0100011;
    localparam [6:0] OPCODE_BRANCH = 7'b1100011;
    localparam [6:0] OPCODE_JALR   = 7'b1100111;

    localparam [2:0] F3_ADD_SUB = 3'b000;
    localparam [2:0] F3_SLLI    = 3'b001;
    localparam [2:0] F3_SRAI    = 3'b101;
    localparam [2:0] F3_LW_SW   = 3'b010;
    localparam [2:0] F3_BEQ     = 3'b000;
    localparam [2:0] F3_BLT     = 3'b100;

    localparam [6:0] F7_ADD = 7'b0000000;
    localparam [6:0] F7_SUB = 7'b0100000;

    localparam [10:0] CTRL_ADD  = {1'b1, 1'b1, 1'b0, 1'b0, 2'b00, 2'b00, 1'b0, 2'b00};
    localparam [10:0] CTRL_SUB  = {1'b1, 1'b1, 1'b0, 1'b0, 2'b00, 2'b00, 1'b0, 2'b01};
    localparam [10:0] CTRL_SLLI = {1'b1, 1'b1, 1'b1, 1'b0, 2'b00, 2'b00, 1'b0, 2'b10};
    localparam [10:0] CTRL_SRAI = {1'b1, 1'b1, 1'b1, 1'b0, 2'b00, 2'b00, 1'b0, 2'b11};
    localparam [10:0] CTRL_ADDI = {1'b1, 1'b1, 1'b1, 1'b0, 2'b00, 2'b00, 1'b0, 2'b00};
    localparam [10:0] CTRL_LW   = {1'b1, 1'b1, 1'b1, 1'b0, 2'b01, 2'b00, 1'b0, 2'b00};
    localparam [10:0] CTRL_SW   = {1'b1, 1'b0, 1'b1, 1'b1, 2'b11, 2'b00, 1'b0, 2'b00};
    localparam [10:0] CTRL_BEQ  = {1'b1, 1'b0, 1'b0, 1'b0, 2'b11, 2'b01, 1'b0, 2'b01};
    localparam [10:0] CTRL_BLT  = {1'b1, 1'b0, 1'b0, 1'b0, 2'b11, 2'b10, 1'b0, 2'b10};
    localparam [10:0] CTRL_JALR = {1'b1, 1'b1, 1'b1, 1'b0, 2'b10, 2'b00, 1'b1, 2'b00};

    assign rs1_addr = instr[19:15];
    assign rs2_addr = instr[24:20];
    assign rd = instr[11:7];

    always @* begin
        ctrl_sig = 11'd0;
        imm = 32'd0;

        case (instr[6:0])
            OPCODE_OP: begin
                if ((instr[14:12] == F3_ADD_SUB) && (instr[31:25] == F7_ADD)) begin
                    ctrl_sig = CTRL_ADD;
                end
                else if ((instr[14:12] == F3_ADD_SUB) && (instr[31:25] == F7_SUB)) begin
                    ctrl_sig = CTRL_SUB;
                end
            end
            OPCODE_OP_IMM: begin
                if (instr[14:12] == F3_ADD_SUB) begin
                    ctrl_sig = CTRL_ADDI;
                    imm = {{20{instr[31]}}, instr[31:20]};
                end
                else if ((instr[14:12] == F3_SLLI) && (instr[31:25] == F7_ADD)) begin
                    ctrl_sig = CTRL_SLLI;
                    imm = {27'd0, instr[24:20]};
                end
                else if ((instr[14:12] == F3_SRAI) && (instr[31:25] == F7_SUB)) begin
                    ctrl_sig = CTRL_SRAI;
                    imm = {27'd0, instr[24:20]};
                end
            end
            OPCODE_LOAD: begin
                if (instr[14:12] == F3_LW_SW) begin
                    ctrl_sig = CTRL_LW;
                    imm = {{20{instr[31]}}, instr[31:20]};
                end
            end
            OPCODE_STORE: begin
                if (instr[14:12] == F3_LW_SW) begin
                    ctrl_sig = CTRL_SW;
                    imm = {{20{instr[31]}}, instr[31:25], instr[11:7]};
                end
            end
            OPCODE_BRANCH: begin
                if (instr[14:12] == F3_BEQ) begin
                    ctrl_sig = CTRL_BEQ;
                    imm = {{19{instr[31]}}, instr[31], instr[7], instr[30:25], instr[11:8], 1'b0};
                end
                else if (instr[14:12] == F3_BLT) begin
                    ctrl_sig = CTRL_BLT;
                    imm = {{19{instr[31]}}, instr[31], instr[7], instr[30:25], instr[11:8], 1'b0};
                end
            end
            OPCODE_JALR: begin
                if (instr[14:12] == F3_ADD_SUB) begin
                    ctrl_sig = CTRL_JALR;
                    imm = {{20{instr[31]}}, instr[31:20]};
                end
            end
            default: begin
                ctrl_sig = 11'd0;
                imm = 32'd0;
            end
        endcase
    end
endmodule
