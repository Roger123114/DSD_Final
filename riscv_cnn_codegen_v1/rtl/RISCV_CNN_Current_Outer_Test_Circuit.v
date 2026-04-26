`timescale 1ns / 1ps
// ============================================================================
// RISCV_CNN_Current_Outer_Test_Circuit.v
// ----------------------------------------------------------------------------
// Simulation-only outer test circuit tailored to the current uploaded RISCV_CNN.
//
// Current top-level interface expected:
//
// module RISCV_CNN(
//     input         clk,
//     input         rstn,
//     input         test_mode,
//     input         test_we,
//     input  [9:0]  test_addr,
//     input  [31:0] test_wdata,
//     output [31:0] test_rdata,
//     output [9:0]  cpu_dmem_addr_debug,
//     output        cpu_dmem_we_debug,
//     output [9:0]  cnn_addr_debug,
//     output        cnn_we_debug
// );
//
// Test concept:
//   1. test_mode=1: outer test circuit owns data-memory Port A.
//   2. rstn=0: keep CPU/CNN reset during memory initialization.
//   3. Write one RAM_case*.mem image into shared memory.
//   4. Force public start protocol:
//        mem[12][0]    = 1
//        mem[13]       = 0
//   5. test_mode=0 and rstn=1: release CPU/CNN.
//   6. During execution, do not drive Port A.
//   7. Wait until public finish mem[13][0] becomes 1.
//   8. test_mode=1: read back memory through test port and compare output.
//   9. Repeat for multiple input sizes.
//
// Notes:
//   - Default output size formula matches the current uploaded CNN, which behaves
//     as one valid 3x3 convolution stage: output dimension = N - 2.
//   - To enforce the project two-stage CNN topology, set SPEC_TWO_STAGE = 1.
//     Then output dimension = N - 4. Your CNN/golden files must match that.
//   - For behavioral Data_mem, this TB can passively monitor mem[13][0] through
//     hierarchy. For black-box Vivado IP, define NO_HIER_FINISH_MONITOR and the
//     TB will wait a fixed number of cycles before checking.
// ============================================================================

`ifndef DUT_MEM_PATH
`define DUT_MEM_PATH dut.u_data_mem.mem
`endif

module RISCV_CNN_Current_Outer_Test_Circuit;

parameter integer NUM_CASES = 5;
parameter integer TIMEOUT_CYCLES = 200000;
parameter integer RUN_WAIT_CYCLES_NO_HIER = 20000;
parameter integer SPEC_TWO_STAGE = 0;  // 0=current uploaded CNN; 1=strict two-stage spec

reg clk;
reg rstn;
reg test_mode;
reg test_we;
reg [9:0] test_addr;
reg [31:0] test_wdata;
wire [31:0] test_rdata;
wire [9:0] cpu_dmem_addr_debug;
wire cpu_dmem_we_debug;
wire [9:0] cnn_addr_debug;
wire cnn_we_debug;

integer i;
integer case_id;
integer cycle_count;
integer error_count;
integer case_error_count;
integer feature_size;
integer expected_feature_size;
integer output_dim;
integer output_words;
integer output_start;
integer expected_output_start;
integer mismatch_count;
integer reserved_error_count;

reg [31:0] ram_image [0:1023];
reg [31:0] golden_mem [0:1023];
reg [31:0] reserved_snapshot [0:63];
reg [31:0] read_data_tmp;
reg [8*256-1:0] ram_file;
reg [8*256-1:0] golden_file;

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
    forever #5 clk = ~clk;
end

initial begin
    rstn = 1'b0;
    test_mode = 1'b1;
    test_we = 1'b0;
    test_addr = 10'd0;
    test_wdata = 32'd0;
    error_count = 0;

    $display("[TB] ============================================================");
    $display("[TB] RISCV_CNN current-code outer multi-size test");
    $display("[TB] SPEC_TWO_STAGE = %0d", SPEC_TWO_STAGE);
    $display("[TB] ============================================================");

    run_case(0);
    run_case(1);
    run_case(2);
    run_case(3);
    run_case(4);

    if (error_count == 0) begin
        $display("[TB] PASS: all current outer multi-size tests passed.");
    end
    else begin
        $display("[TB] FAIL: total errors = %0d", error_count);
    end

    $finish;
end

task select_case_files;
input integer cid;
begin
    case (cid)
        0: begin
            ram_file = "generated/RAM_case0.mem";
            golden_file = "generated/golden_case0.mem";
            expected_feature_size = 10;
        end
        1: begin
            ram_file = "generated/RAM_case1.mem";
            golden_file = "generated/golden_case1.mem";
            expected_feature_size = 16;
        end
        2: begin
            ram_file = "generated/RAM_case2.mem";
            golden_file = "generated/golden_case2.mem";
            expected_feature_size = 20;
        end
        3: begin
            ram_file = "generated/RAM_case3.mem";
            golden_file = "generated/golden_case3.mem";
            expected_feature_size = 28;
        end
        4: begin
            ram_file = "generated/RAM_case4.mem";
            golden_file = "generated/golden_case4.mem";
            expected_feature_size = 32;
        end
        default: begin
            ram_file = "generated/RAM_case0.mem";
            golden_file = "generated/golden_case0.mem";
            expected_feature_size = 10;
        end
    endcase
end
endtask

task calc_output_words;
input integer fs;
begin
    if (SPEC_TWO_STAGE != 0) begin
        output_dim = fs - 4;
    end
    else begin
        output_dim = fs - 2;
    end

    if (output_dim <= 0) begin
        output_words = 0;
    end
    else begin
        output_words = ((output_dim * output_dim) + 3) / 4;
    end
end
endtask

task test_write_word;
input [9:0] addr;
input [31:0] data;
begin
    test_mode = 1'b1;
    test_addr = addr;
    test_wdata = data;
    test_we = 1'b1;
    @(posedge clk);
    #1;
    test_we = 1'b0;
    test_wdata = 32'd0;
end
endtask

task test_read_word;
input [9:0] addr;
output [31:0] data;
begin
    test_mode = 1'b1;
    test_we = 1'b0;
    test_addr = addr;
    @(posedge clk);
    #1;
    data = test_rdata;
end
endtask

task load_case_to_memory;
begin
    for (i = 0; i < 1024; i = i + 1) begin
        ram_image[i] = 32'd0;
        golden_mem[i] = 32'd0;
    end

    $readmemh(ram_file, ram_image);
    $readmemh(golden_file, golden_mem);

    rstn = 1'b0;
    test_mode = 1'b1;
    test_we = 1'b0;
    repeat (3) @(posedge clk);

    for (i = 0; i < 1024; i = i + 1) begin
        test_write_word(i[9:0], ram_image[i]);
    end

    // Enforce public spec-side start/status fields.
    ram_image[12][0] = 1'b1;
    ram_image[13] = 32'd0;
    test_write_word(10'd12, ram_image[12]);
    test_write_word(10'd13, 32'd0);
end
endtask

task snapshot_reserved_region;
begin
    for (i = 0; i < 64; i = i + 1) begin
        test_read_word(10'd960 + i[9:0], reserved_snapshot[i]);
    end
end
endtask

task check_reserved_region;
begin
    reserved_error_count = 0;
    for (i = 0; i < 64; i = i + 1) begin
        test_read_word(10'd960 + i[9:0], read_data_tmp);
        if (read_data_tmp !== reserved_snapshot[i]) begin
            $display("[TB][ERROR] reserved mem[%0d] overwritten: expected=%h got=%h",
                     960 + i, reserved_snapshot[i], read_data_tmp);
            reserved_error_count = reserved_error_count + 1;
        end
    end

    if (reserved_error_count != 0) begin
        error_count = error_count + reserved_error_count;
        case_error_count = case_error_count + reserved_error_count;
    end
end
endtask

task release_dut_and_wait_finish;
begin
    // Release CPU/CNN. test_mode=0 gives Port A to CPU.
    test_mode = 1'b0;
    test_we = 1'b0;
    rstn = 1'b1;
    repeat (5) @(posedge clk);

`ifndef NO_HIER_FINISH_MONITOR
    cycle_count = 0;

    while ((`DUT_MEM_PATH[12][0] !== 1'b0) && (cycle_count < TIMEOUT_CYCLES)) begin
        @(posedge clk);
        cycle_count = cycle_count + 1;
    end

    if (cycle_count >= TIMEOUT_CYCLES) begin
        $display("[TB][ERROR] timeout waiting CPU to clear mem[12][0].");
        error_count = error_count + 1;
        case_error_count = case_error_count + 1;
    end
    else begin
        $display("[TB] CPU cleared mem[12][0] after %0d cycles.", cycle_count);
    end

    cycle_count = 0;
    while ((`DUT_MEM_PATH[13][0] !== 1'b1) && (cycle_count < TIMEOUT_CYCLES)) begin
        @(posedge clk);
        cycle_count = cycle_count + 1;
    end

    if (cycle_count >= TIMEOUT_CYCLES) begin
        $display("[TB][ERROR] timeout waiting mem[13][0] public finish.");
        error_count = error_count + 1;
        case_error_count = case_error_count + 1;
    end
    else begin
        $display("[TB] Public finish mem[13][0] asserted after %0d cycles.", cycle_count);
    end
`else
    // For black-box IP memories without hierarchical access, wait a conservative
    // fixed time, then seize Port A and check mem[13][0].
    repeat (RUN_WAIT_CYCLES_NO_HIER) @(posedge clk);
`endif

    // Seize Port A for final readback. In current top this resets CPU only.
    test_mode = 1'b1;
    test_we = 1'b0;
    repeat (3) @(posedge clk);
end
endtask

task check_public_protocol;
begin
    test_read_word(10'd12, read_data_tmp);
    feature_size = read_data_tmp[6:1];

    if (feature_size != expected_feature_size) begin
        $display("[TB][ERROR] feature size mismatch: expected=%0d got=%0d mem12=%h",
                 expected_feature_size, feature_size, read_data_tmp);
        error_count = error_count + 1;
        case_error_count = case_error_count + 1;
    end

    if (read_data_tmp[0] !== 1'b0) begin
        $display("[TB][ERROR] mem[12][0] start bit was not cleared. mem12=%h", read_data_tmp);
        error_count = error_count + 1;
        case_error_count = case_error_count + 1;
    end

    test_read_word(10'd13, read_data_tmp);
    output_start = read_data_tmp[10:1];

    if (read_data_tmp[0] !== 1'b1) begin
        $display("[TB][ERROR] mem[13][0] finish bit is not high. mem13=%h", read_data_tmp);
        error_count = error_count + 1;
        case_error_count = case_error_count + 1;
    end

    if (output_start < 16) begin
        $display("[TB][ERROR] output_start too low: %0d", output_start);
        error_count = error_count + 1;
        case_error_count = case_error_count + 1;
    end

    calc_output_words(feature_size);

    if ((output_start + output_words - 1) >= 960) begin
        $display("[TB][ERROR] output region [%0d:%0d] overlaps reserved region.",
                 output_start, output_start + output_words - 1);
        error_count = error_count + 1;
        case_error_count = case_error_count + 1;
    end

    $display("[TB] mem12=%h mem13=%h feature_size=%0d output_start=%0d output_words=%0d",
             ram_image[12], read_data_tmp, feature_size, output_start, output_words);
end
endtask

task check_output_data;
begin
    mismatch_count = 0;

    for (i = 0; i < output_words; i = i + 1) begin
        test_read_word(output_start[9:0] + i[9:0], read_data_tmp);
        if (read_data_tmp !== golden_mem[i]) begin
            $display("[TB][ERROR] output mismatch case=%0d word=%0d mem[%0d]: expected=%h got=%h",
                     case_id, i, output_start + i, golden_mem[i], read_data_tmp);
            mismatch_count = mismatch_count + 1;
        end
    end

    if (mismatch_count != 0) begin
        error_count = error_count + mismatch_count;
        case_error_count = case_error_count + mismatch_count;
    end
    else begin
        $display("[TB] output matched %0d words.", output_words);
    end
end
endtask

task run_case;
input integer cid;
begin
    case_id = cid;
    case_error_count = 0;
    select_case_files(cid);

    $display("[TB] ------------------------------------------------------------");
    $display("[TB] CASE %0d start", cid);
    $display("[TB] RAM    : %0s", ram_file);
    $display("[TB] GOLDEN : %0s", golden_file);
    $display("[TB] expected feature size = %0d", expected_feature_size);

    load_case_to_memory();
    snapshot_reserved_region();
    release_dut_and_wait_finish();
    check_public_protocol();
    check_output_data();
    check_reserved_region();

    if (case_error_count == 0) begin
        $display("[TB] CASE %0d PASS", cid);
    end
    else begin
        $display("[TB] CASE %0d FAIL: errors=%0d", cid, case_error_count);
    end

    rstn = 1'b0;
    test_mode = 1'b1;
    test_we = 1'b0;
    repeat (5) @(posedge clk);
end
endtask

initial begin
    $dumpfile("riscv_cnn_current_outer_test.vcd");
    $dumpvars(0, RISCV_CNN_Current_Outer_Test_Circuit);
end

endmodule
