module Simple_CPU(
    input         CLK,
    input         RSTN,
    output        dmem_en,
    output        dmem_we,
    output [9:0]  dmem_addr,
    output [31:0] dmem_wdata,
    input  [31:0] dmem_rdata
);
    wire [31:0] pc;
    wire [31:0] instruction_mem;
    reg  [31:0] instruction_reg;
    wire [31:0] imm;
    wire [31:0] branch_pc, branch_imm, jalr_target;
    wire [10:0] ctrl_sig_dec, ctrl_sig;
    wire [4:0] rs1_addr, rs2_addr, rd;
    wire branch_taken, jalr_taken, operation_done;
    reg [1:0] cpu_state, cpu_nstate;

    localparam [1:0] CPU_FETCH_ADDR = 2'd0,  // present PC to instruction ROM
                     CPU_FETCH_WAIT = 2'd1,  // wait one cycle for ROM data
                     CPU_ISSUE      = 2'd2,  // issue decoded control signals
                     CPU_WAIT_DONE  = 2'd3;  // wait for processor completion

    assign ctrl_sig = (cpu_state == CPU_ISSUE) ? ctrl_sig_dec : 11'd0;

    always @* begin
        case (cpu_state)
            CPU_FETCH_ADDR: begin
                cpu_nstate = CPU_FETCH_WAIT;
            end
            CPU_FETCH_WAIT: begin
                cpu_nstate = CPU_ISSUE;
            end
            CPU_ISSUE: begin
                cpu_nstate = CPU_WAIT_DONE;
            end
            CPU_WAIT_DONE: begin
                cpu_nstate = operation_done ? CPU_FETCH_ADDR : CPU_WAIT_DONE;
            end
            default: begin
                cpu_nstate = CPU_FETCH_ADDR;
            end
        endcase
    end

    always @(posedge CLK or negedge RSTN) begin
        if (!RSTN) begin
            cpu_state <= CPU_FETCH_ADDR;
            instruction_reg <= 32'd0;
        end
        else begin
            cpu_state <= cpu_nstate;
            if (cpu_state == CPU_FETCH_WAIT) begin
                instruction_reg <= instruction_mem;
            end
        end
    end

    PC_Controller u_pc(
        .CLK(CLK),
        .RSTN(RSTN),
        .pc_write(operation_done),
        .branch_taken(branch_taken),
        .jalr_taken(jalr_taken),
        .branch_pc(branch_pc),
        .branch_imm(branch_imm),
        .jalr_target(jalr_target),
        .PC(pc)
    );

    Instruction_Memory u_imem(
        .clka(CLK),
        .addra(pc[11:2]),
        .douta(instruction_mem)
    );

    instr_dec u_dec(
        .instr(instruction_reg),
        .rs1_addr(rs1_addr),
        .rs2_addr(rs2_addr),
        .rd(rd),
        .ctrl_sig(ctrl_sig_dec),
        .imm(imm)
    );

    Simple_Processor u_proc(
        .CLK(CLK),
        .RSTN(RSTN),
        .pc(pc),
        .ctrl_sig(ctrl_sig),
        .rs1(rs1_addr),
        .rs2(rs2_addr),
        .rd(rd),
        .imm(imm),
        .dmem_en(dmem_en),
        .dmem_we(dmem_we),
        .dmem_addr(dmem_addr),
        .dmem_wdata(dmem_wdata),
        .dmem_rdata(dmem_rdata),
        .branch_taken(branch_taken),
        .branch_pc(branch_pc),
        .branch_imm(branch_imm),
        .jalr_taken(jalr_taken),
        .jalr_target(jalr_target),
        .Operation_done(operation_done)
    );
endmodule
