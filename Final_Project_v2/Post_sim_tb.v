`timescale 1ns / 1ps

module RISCV_CNN_tb;

    // =========================
    // Testbench signals
    // =========================
    reg         FPGA_clk;
    reg         rstn;
    reg  [3:0]  tc;
    reg         mode;
    reg         st;

    wire [6:0]  seven_seg;
    wire [3:0]  anode;
    wire        all_done;

    integer i;
    
    // =========================
    // DUT
    // =========================
    RISCV_CNN dut (
        .FPGA_clk (FPGA_clk),
        .rstn     (rstn),
        .tc       (tc),
        .mode     (mode),
        .st       (st),
        .seven_seg(seven_seg),
        .anode    (anode),
        .all_done (all_done)
    );
    
    // =========================
    // 100 MHz clock
    // Period = 10 ns
    // =========================
    initial begin
        FPGA_clk = 1'b0;
        forever #5 FPGA_clk = ~FPGA_clk;
    end

    // =========================
    // Test stimulus
    // =========================
    initial begin
        rstn = 1'b1;
        #20;
        rstn = 1'b0;     // assert reset
        #50;
        rstn = 1'b1;     // release reset
        #500// Initial value
        mode = 1'b0;
        tc   = 4'h0;
        st   = 1'b0; 

        // -------------------------
        // Active-low reset
        // reset negedge
        // -------------------------



        // Wait a few cycles after reset
        repeat (5) @(posedge FPGA_clk);

        // -------------------------
        // mode = 0
        // Directly set tc from 0 to 15
        // Trigger st high for one clock cycle
        // Then switch mode to 1
        // -------------------------
        mode = 1'b0;
        tc   = 4'hF;
        st   = 1'b0;

        // Hold st high long enough to pass debounce
        @(posedge FPGA_clk);
        st = 1'b1;
        
        repeat (2000020) @(posedge FPGA_clk);
        
        st = 1'b0;
        #10 mode = 1'b1;

        // -------------------------
        // After one-cycle st trigger,
        // set mode = 1 forever
        // -------------------------
        @(posedge FPGA_clk);
//        mode = 1'b1;
        st   = 1'b0;

        // // Keep simulation running
        // repeat (200) @(posedge FPGA_clk);

        // $finish;
    end

endmodule