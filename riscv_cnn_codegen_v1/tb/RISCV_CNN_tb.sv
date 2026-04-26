`timescale 1ns/1ps

`ifndef GOLDEN_MEM_FILE
`define GOLDEN_MEM_FILE "golden_case0.mem"
`endif

`ifndef OUT_WORDS
`define OUT_WORDS 16
`endif

module RISCV_CNN_tb;
    localparam integer CLK_PERIOD_NS = 10;
    localparam integer RESET_CYCLES = 5;
    localparam integer MAX_CYCLES = 300000;
    localparam integer OUT_START_WORD = 384;

    logic clk, rstn;
    logic test_mode, test_we;
    logic [9:0] test_addr;
    logic [31:0] test_wdata, test_rdata;
    logic [9:0] cpu_dmem_addr_debug, cnn_addr_debug;
    logic cpu_dmem_we_debug, cnn_we_debug;

    reg [31:0] golden [0:`OUT_WORDS-1];
    integer cycle;
    integer err_count;
    integer i;

    RISCV_CNN dut(
        .clk(clk),
        .rstn(rstn),
        .test_mode(test_mode),
        .test_we(test_we),
        .test_addr(test_addr),
        .test_wdata(test_wdata),
        .test_rdata(test_rdata),
        .cpu_dmem_addr_debug(cpu_dmem_addr_debug),
        .cpu_dmem_we_debug(cpu_dmem_we_debug),
        .cnn_addr_debug(cnn_addr_debug),
        .cnn_we_debug(cnn_we_debug)
    );

    initial begin
        clk = 1'b0;
    end

    always #(CLK_PERIOD_NS / 2) begin
        clk = ~clk;
    end

    initial begin
        $readmemh(`GOLDEN_MEM_FILE, golden);
    end

    initial begin
        rstn = 1'b0;
        test_mode = 1'b1;
        test_we = 1'b0;
        test_addr = 10'd0;
        test_wdata = 32'd0;
        err_count = 0;
        for (i = 0; i < RESET_CYCLES; i = i + 1) begin
            @(negedge clk);
        end
        rstn = 1'b1;
        @(negedge clk);
        test_mode = 1'b0;
    end

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            cycle <= 0;
        end
        else begin
            cycle <= cycle + 1;
            if (cycle >= MAX_CYCLES) begin
                $fatal(1, "[TB] TIMEOUT at cycle %0d", cycle);
            end
            if (dut.u_data_mem.mem[13][0] == 1'b1) begin
                $display("[TB] Done detected at cycle %0d", cycle);
                for (i = 0; i < `OUT_WORDS; i = i + 1) begin
                    if (dut.u_data_mem.mem[OUT_START_WORD + i] !== golden[i]) begin
                        $display("[TB][ERR] addr=%0d got=%08h exp=%08h", OUT_START_WORD + i,
                                 dut.u_data_mem.mem[OUT_START_WORD + i], golden[i]);
                        err_count = err_count + 1;
                    end
                end
                if (err_count == 0) begin
                    $display("[TB] PASS: all %0d output words matched", `OUT_WORDS);
                end
                else begin
                    $fatal(1, "[TB] FAIL: err_count=%0d", err_count);
                end
                $finish;
            end
        end
    end
endmodule
