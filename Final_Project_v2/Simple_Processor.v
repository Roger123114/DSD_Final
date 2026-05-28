module Simple_Processor(
    input               CLK,
    input               RSTN,
    input      [31:0]   pc,
    input      [10:0]   ctrl_sig,
    input      [4:0]    rs1,
    input      [4:0]    rs2,
    input      [4:0]    rd,
    input      [31:0]   imm,
    output              dmem_en,
    output              dmem_we,
    output     [9:0]    dmem_addr,
    output     [31:0]   dmem_wdata,
    input      [31:0]   dmem_rdata,
    output reg          branch_taken,
    output     [31:0]   branch_pc,
    output     [31:0]   branch_imm,
    output reg          jalr_taken,
    output reg [31:0]   jalr_target,
    output reg          Operation_done
);
    localparam [2:0] STATE_IDLE     = 3'd0,
                     STATE_EXEC     = 3'd1,
                     STATE_MEM_REQ  = 3'd2,
                     STATE_MEM_WAIT = 3'd3,
                     STATE_WB       = 3'd4,
                     STATE_DONE     = 3'd5;

    localparam [1:0] WB_ALU = 2'b00,
                     WB_MEM = 2'b01,
                     WB_PC4 = 2'b10;

    localparam [1:0] BR_NONE = 2'b00,
                     BR_BEQ  = 2'b01,
                     BR_BLT  = 2'b10;

    reg [2:0] state, nstate;
    reg [10:0] ctrl_r;
    reg [4:0] rd_r;
    reg [31:0] imm_r, src_a_r, src_b_r, alu_out_r, pc_plus4_r, mem_data_r;

    wire [31:0] rf_read_data1, rf_read_data2;
    wire [31:0] alu_in_b;
    wire [31:0] alu_result;
    wire [31:0] wb_data;
    wire        alu_eq, alu_lt;
    wire        ctrl_valid_d;
    wire        rf_we;
    wire        is_load_r;
    wire        needs_mem_r;

    assign ctrl_valid_d = ctrl_sig[10];
    assign alu_in_b = ctrl_r[8] ? imm_r : src_b_r;
    assign is_load_r = (ctrl_r[6:5] == WB_MEM);
    assign needs_mem_r = ctrl_r[7] | is_load_r;
    assign rf_we = (state == STATE_WB) && ctrl_r[9];
    assign dmem_en = (state == STATE_MEM_REQ) || (state == STATE_MEM_WAIT) || (state == STATE_IDLE);
    assign dmem_we = (state == STATE_MEM_REQ) && ctrl_r[7];
    assign dmem_addr = alu_out_r[11:2];
    assign dmem_wdata = src_b_r;
    assign branch_pc = pc_plus4_r - 32'd4;
    assign branch_imm = imm_r;
    assign wb_data = (ctrl_r[6:5] == WB_ALU) ? alu_out_r :
                     (ctrl_r[6:5] == WB_MEM) ? mem_data_r :
                     (ctrl_r[6:5] == WB_PC4) ? pc_plus4_r : 32'd0;

    Registers u_regfile(
        .clk(CLK),
        .RSTN(RSTN),
        .RegWrite(rf_we),
        .rs1(rs1),
        .rs2(rs2),
        .rd(rd_r),
        .write_data(wb_data),
        .read_data1(rf_read_data1),
        .read_data2(rf_read_data2)
    );

    ALU u_alu(
        .data_a(src_a_r),
        .data_b(alu_in_b),
        .alu_op(ctrl_r[1:0]),
        .result(alu_result),
        .eq(alu_eq),
        .lt(alu_lt)
    );

    always @* begin
        case (state)
            STATE_IDLE: begin
                nstate = ctrl_valid_d ? STATE_EXEC : STATE_IDLE;
            end
            STATE_EXEC: begin
                if (needs_mem_r) begin
                    nstate = STATE_MEM_REQ;
                end
                else if (ctrl_r[9]) begin
                    nstate = STATE_WB;
                end
                else begin
                    nstate = STATE_DONE;
                end
            end
            STATE_MEM_REQ: begin
                if (ctrl_r[7]) begin
                    nstate = STATE_DONE;
                end
                else begin
                    nstate = STATE_MEM_WAIT;
                end
            end
            STATE_MEM_WAIT: begin
                nstate = STATE_WB;
            end
            STATE_WB: begin
                nstate = STATE_DONE;
            end
            STATE_DONE: begin
                nstate = STATE_IDLE;
            end
            default: begin
                nstate = STATE_IDLE;
            end
        endcase
    end

    always @(posedge CLK or negedge RSTN) begin
        if (!RSTN) begin
            state <= STATE_IDLE;
            ctrl_r <= 11'd0;
            rd_r <= 5'd0;
            imm_r <= 32'd0;
            src_a_r <= 32'd0;
            src_b_r <= 32'd0;
            alu_out_r <= 32'd0;
            pc_plus4_r <= 32'd0;
            mem_data_r <= 32'd0;
            branch_taken <= 1'b0;
            jalr_taken <= 1'b0;
            jalr_target <= 32'd0;
            Operation_done <= 1'b0;
        end
        else begin
            state <= nstate;

            case (state)
                STATE_IDLE: begin
                    Operation_done <= 1'b0;
                    branch_taken <= 1'b0;
                    jalr_taken <= 1'b0;
                    if (ctrl_valid_d) begin
                        ctrl_r <= ctrl_sig;
                        rd_r <= rd;
                        imm_r <= imm;
                        src_a_r <= rf_read_data1;
                        src_b_r <= rf_read_data2;
                        pc_plus4_r <= pc + 32'd4;
                    end
                end
                STATE_EXEC: begin
                    Operation_done <= 1'b0;
                    alu_out_r <= alu_result;
                    jalr_target <= {alu_result[31:1], 1'b0};
                    jalr_taken <= ctrl_r[2];
                    case (ctrl_r[4:3])
                        BR_BEQ: begin
                            branch_taken <= alu_eq;
                        end
                        BR_BLT: begin
                            branch_taken <= alu_lt;
                        end
                        default: begin
                            branch_taken <= 1'b0;
                        end
                    endcase
                end
                STATE_MEM_REQ: begin
                    Operation_done <= 1'b0;
                end
                STATE_MEM_WAIT: begin
                    Operation_done <= 1'b0;
                    mem_data_r <= dmem_rdata;
                end
                STATE_WB: begin
                    Operation_done <= 1'b0;
                end
                STATE_DONE: begin
                    Operation_done <= 1'b1;
                end
                default: begin
                    Operation_done <= 1'b0;
                    branch_taken <= 1'b0;
                    jalr_taken <= 1'b0;
                    jalr_target <= 32'd0;
                end
            endcase
        end
    end
endmodule