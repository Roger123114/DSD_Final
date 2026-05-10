`timescale 1ns/1ps

module tb_riscv_cnn;
    reg clk;
    reg rstn;
    reg [3:0] tc;
    reg mode;
    reg st;
    wire [6:0] seven_seg;
    wire [3:0] anode;

    RISCV_CNN dut (
        .FPGA_clk(clk),
        .rstn(rstn),
        .tc(tc),
        .mode(mode),
        .st(st),
        .seven_seg(seven_seg),
        .anode(anode)
    );

    initial begin
        clk = 1'b0;
        forever #10 clk = ~clk;
    end

    initial begin
        rstn = 1'b0;
        tc = 4'd0;
        mode = 1'b0;
        st = 1'b0;

        repeat (10) @(posedge clk);
        rstn = 1'b1;

        repeat (10) @(posedge clk);
        force dut.u_test_circuit.start_stable = 1'b1;
        force dut.u_test_circuit.start_stable_d = 1'b0;
        @(posedge clk);
        release dut.u_test_circuit.start_stable;
        release dut.u_test_circuit.start_stable_d;

        wait (dut.u_test_circuit.state == 5'd17);
        repeat (10) @(posedge clk);
        $display("DONE pass_count=%0d fail_count=%0d cnn_pass_count=%0d cpu_pass_score=%0d total_cycles=%0d",
                 dut.u_test_circuit.pass_count,
                 dut.u_test_circuit.fail_count,
                 dut.u_test_circuit.cnn_pass_count,
                 dut.u_test_circuit.cpu_pass_score,
                 dut.u_test_circuit.total_cycle_count);
        if (dut.u_test_circuit.fail_count == 4'd0) begin
            $display("PASS");
        end
        else begin
            $display("FAIL");
        end
        $finish;
    end

    initial begin
        repeat (2000000) @(posedge clk);
        $display("TIMEOUT state=%0d test_id=%0d cycle_counter=%0d",
                 dut.u_test_circuit.state,
                 dut.u_test_circuit.test_id,
                 dut.u_test_circuit.cycle_counter);
        $finish;
    end

    always @(posedge clk) begin
        if (dut.u_test_circuit.state == 5'd15) begin
            $display("TEST %0d cnn_fail=%0d cpu_score=%0d captured_addr13=%08h",
                     dut.u_test_circuit.test_id,
                     dut.u_test_circuit.testcase_fail,
                     dut.u_test_circuit.cpu_pass_score,
                     dut.u_test_circuit.captured_addr13);
        end
    end
endmodule
