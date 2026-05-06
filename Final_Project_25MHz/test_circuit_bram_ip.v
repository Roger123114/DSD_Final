module test_circuit #(
    parameter MEM_DW = 32,
    parameter MEM_AW = 10
)(
    //global
    input  clk,
    input  rstn,
    output reg sys_rstn,
    //data mem
    output [MEM_AW-1:0] mem_addr,
    output [MEM_DW-1:0] mem_wdata,
    input  [MEM_DW-1:0] mem_rdata,
    output              mem_we,
    //cpu
    input  [MEM_AW-1:0] cpu_addr,
    input  [MEM_DW-1:0] cpu_wdata,
    output [MEM_DW-1:0] cpu_rdata,
    input               cpu_we,
    input               system_done,
    //user control
    input  start_bt,
    input  result_bt,
    input  score_sw,   // 0: show CPU/CNN pass counts, 1: show weighted score out of 100
    // Display output
    output reg [7-1:0] seven_seg,
    output reg [3:0] anode
);

localparam TEST_NUM = 10;
localparam INIT_WORDS = 1024;
localparam MEM_WORDS = 1024;
localparam RESERVED_START = 960;
localparam RESERVED_END = 1023;
localparam GOLDEN_MAX_WORDS = 196;
localparam CPU_SUBTEST_NUM = 5;
localparam [11:0] CPU_GOLDEN_BASE = TEST_NUM * GOLDEN_MAX_WORDS;
localparam CLK_PERIOD_NS = 10;
localparam [31:0] RUN_TIMEOUT_CYCLES = 32'd100000000;
localparam [19:0] DEBOUNCE_MAX = 20'd999999;

// S_IDLE: wait for start button while holding CPU/CNN reset.
// S_CLEAR_MEM: write zero to data_mem[0:1023].
// S_LOAD_INIT_REQ: issue synchronous ROM read for selected init word.
// S_LOAD_INIT_WRITE: write selected init ROM word to data_mem[0:1023].
// S_WRITE_START_REQ: issue synchronous ROM read for init word at address 11.
// S_WRITE_START_WRITE: force data_mem[11][0] to 1.
// S_RELEASE_SYS_RESET: release CPU/CNN reset for one cycle before RUN.
// S_RUN: CPU owns Port A; test circuit monitors finish write.
// S_CHECK_PREP: take back Port A and reset CPU/CNN.
// S_READ_ADDR13_REQ: issue synchronous read of data_mem[13].
// S_READ_ADDR13_CMP: read finish bit and actual output start field from data_mem[13].
// S_READ_RESERVED_REQ: issue synchronous read of CPU test region Data Memory[960:1023]
//                      and CPU golden block golden[196*10 + 0 : 196*10 + 63].
// S_READ_RESERVED_CMP: compare CPU test region with CPU golden block and update
//                      five CPU subtest fail flags independently.
// S_READ_OFMAP_REQ: issue synchronous read of output feature map word and golden ROM word.
// S_READ_OFMAP_CMP: compare output feature map word with golden ROM.
// S_UPDATE_SCORE: update pass/fail and total cycle counters.
// S_NEXT_TEST: advance to next testcase or finish.
// S_DONE: show final result and wait in inactive state.
localparam [4:0] S_IDLE               = 5'd0;
localparam [4:0] S_CLEAR_MEM          = 5'd1;
localparam [4:0] S_LOAD_INIT_REQ      = 5'd2;
localparam [4:0] S_LOAD_INIT_WRITE    = 5'd3;
localparam [4:0] S_WRITE_START_REQ    = 5'd4;
localparam [4:0] S_WRITE_START_WRITE  = 5'd5;
localparam [4:0] S_RELEASE_SYS_RESET  = 5'd6;
localparam [4:0] S_RUN                = 5'd7;
localparam [4:0] S_CHECK_PREP         = 5'd8;
localparam [4:0] S_READ_ADDR13_REQ    = 5'd9;
localparam [4:0] S_READ_ADDR13_CMP    = 5'd10;
localparam [4:0] S_READ_RESERVED_REQ  = 5'd11;
localparam [4:0] S_READ_RESERVED_CMP  = 5'd12;
localparam [4:0] S_READ_OFMAP_REQ     = 5'd13;
localparam [4:0] S_READ_OFMAP_CMP     = 5'd14;
localparam [4:0] S_UPDATE_SCORE       = 5'd15;
localparam [4:0] S_NEXT_TEST          = 5'd16;
localparam [4:0] S_DONE               = 5'd17;

reg [4:0] state, nstate;

reg test_mode;
reg [MEM_AW-1:0] tc_addr;
reg [MEM_DW-1:0] tc_wdata;
reg tc_we;

reg [MEM_AW-1:0] addr_counter;
reg [7:0] ofmap_idx;
reg [3:0] test_id;
reg testcase_fail;  // CNN testcase fail flag only.
reg cpu_addi_sw_fail, cpu_lw_fail, cpu_add_sub_fail, cpu_beq_fail, cpu_blt_fail;
wire [3:0] cpu_pass_score, cpu_fail_score;
wire [3:0] cnn_pass_inc, cnn_fail_inc;
reg [3:0] cnn_pass_count;
reg [3:0] pass_count, fail_count;
wire [7:0] weighted_score_decimal; // integer score, 0~100
reg [15:0] count_display_bcd;
reg [15:0] score_display_bcd;
reg [31:0] cycle_counter, testcase_cycle_count, total_cycle_count;
reg [31:0] captured_addr13;
reg [MEM_AW-1:0] captured_ofmap_start;

wire [MEM_DW-1:0] init_word, golden_word;
reg [MEM_AW-1:0] init_lookup_addr, ofmap_addr_offset;
reg [5:0] feature_size;
reg [7:0] ofmap_word_count;
reg [MEM_AW-1:0] addr13_ofmap_start;
reg [10:0] addr13_ofmap_end_exclusive;
reg [11:0] final_ofmap_size_ext, ofmap_elem_count_ext;
wire finish_event, run_timeout_event;

wire [13:0] init_rom_addr;
wire [13:0] init_rom_base;
wire [13:0] init_test_id_ext;
wire [13:0] init_lookup_addr_ext;
wire [11:0] golden_rom_addr;
wire [11:0] golden_rom_base;
wire [11:0] golden_test_id_ext;
wire [11:0] golden_idx_ext;
wire [11:0] cpu_golden_idx_ext;

reg start_sync0, start_sync1, start_stable, start_stable_d;
reg result_sync0, result_sync1, result_stable, result_stable_d;
reg score_sw_sync0, score_sw_sync1;
reg [19:0] start_db_cnt, result_db_cnt;
wire start_bt_pulse, result_bt_pulse;

reg [15:0] scan_counter;
wire [1:0] scan_sel;
reg [1:0] display_mode;
reg [15:0] display_value;
reg [3:0] display_nibble;

assign mem_addr = test_mode ? tc_addr : cpu_addr;
assign mem_wdata = test_mode ? tc_wdata : cpu_wdata;
assign mem_we = test_mode ? tc_we : cpu_we;
assign cpu_rdata = test_mode ? {MEM_DW{1'b0}} : mem_rdata;

assign finish_event = system_done || (cpu_we && (cpu_addr == 10'd13) && cpu_wdata[0]);
assign run_timeout_event = (cycle_counter == RUN_TIMEOUT_CYCLES);
assign start_bt_pulse = start_stable && !start_stable_d;
assign result_bt_pulse = result_stable && !result_stable_d;
assign scan_sel = scan_counter[15:14];

assign init_test_id_ext = {10'd0, test_id};
assign init_lookup_addr_ext = {4'd0, init_lookup_addr};
assign init_rom_base = (init_test_id_ext << 10);
assign init_rom_addr = init_rom_base + init_lookup_addr_ext;

assign golden_test_id_ext = {8'd0, test_id};
assign golden_idx_ext = {4'd0, ofmap_idx};
assign cpu_golden_idx_ext = {6'd0, addr_counter[5:0]};
assign golden_rom_base = (golden_test_id_ext << 7) + (golden_test_id_ext << 6) + (golden_test_id_ext << 2);
assign golden_rom_addr = ((state == S_READ_RESERVED_REQ) || (state == S_READ_RESERVED_CMP)) ?
                         (CPU_GOLDEN_BASE + cpu_golden_idx_ext) :
                         (golden_rom_base + golden_idx_ext);

assign cpu_pass_score = (cpu_addi_sw_fail ? 4'd0 : 4'd1) +
                        (cpu_lw_fail      ? 4'd0 : 4'd1) +
                        (cpu_add_sub_fail ? 4'd0 : 4'd1) +
                        (cpu_beq_fail     ? 4'd0 : 4'd1) +
                        (cpu_blt_fail     ? 4'd0 : 4'd1);
assign cpu_fail_score = (cpu_addi_sw_fail ? 4'd1 : 4'd0) +
                        (cpu_lw_fail      ? 4'd1 : 4'd0) +
                        (cpu_add_sub_fail ? 4'd1 : 4'd0) +
                        (cpu_beq_fail     ? 4'd1 : 4'd0) +
                        (cpu_blt_fail     ? 4'd1 : 4'd0);
assign cnn_pass_inc = testcase_fail ? 4'd0 : 4'd1;
assign cnn_fail_inc = testcase_fail ? 4'd1 : 4'd0;

// Weighted grading: original 20% rubric scaled to 100 points.
// CNN 10% -> 50 points: each of 10 CNN testcases = 5 points.
// CPU 10% -> 50 points: five CPU subtests, each 2% -> 10 points.
//   addi/sw = 10, lw = 10, add/sub = 10, beq = 10, blt = 10.
// No divider is used here. The constants 5 and 10 are implemented by shifts/adds.
assign weighted_score_decimal = ({4'd0, cnn_pass_count} << 2) + {4'd0, cnn_pass_count} +
                                ({4'd0, cpu_pass_score} << 3) + ({4'd0, cpu_pass_score} << 1);

always @(*) begin
    case (state)
        S_IDLE: nstate = start_bt_pulse ? S_CLEAR_MEM : S_IDLE;
        S_CLEAR_MEM: nstate = (addr_counter == 10'd1023) ? S_LOAD_INIT_REQ : S_CLEAR_MEM;
        S_LOAD_INIT_REQ: nstate = S_LOAD_INIT_WRITE;
        S_LOAD_INIT_WRITE: nstate = (addr_counter == 10'd1023) ? S_WRITE_START_REQ : S_LOAD_INIT_REQ;
        S_WRITE_START_REQ: nstate = S_WRITE_START_WRITE;
        S_WRITE_START_WRITE: nstate = S_RELEASE_SYS_RESET;
        S_RELEASE_SYS_RESET: nstate = S_RUN;
        S_RUN: nstate = (finish_event || run_timeout_event) ? S_CHECK_PREP : S_RUN;
        S_CHECK_PREP: nstate = S_READ_ADDR13_REQ;
        S_READ_ADDR13_REQ: nstate = S_READ_ADDR13_CMP;
        S_READ_ADDR13_CMP: nstate = S_READ_RESERVED_REQ;
        S_READ_RESERVED_REQ: nstate = S_READ_RESERVED_CMP;
        S_READ_RESERVED_CMP: nstate = (addr_counter == 10'd1023) ? S_READ_OFMAP_REQ : S_READ_RESERVED_REQ;
        S_READ_OFMAP_REQ: nstate = S_READ_OFMAP_CMP;
        S_READ_OFMAP_CMP: nstate = (ofmap_idx == (ofmap_word_count - 8'd1)) ? S_UPDATE_SCORE : S_READ_OFMAP_REQ;
        S_UPDATE_SCORE: nstate = S_NEXT_TEST;
        S_NEXT_TEST: nstate = (test_id == 4'd9) ? S_DONE : S_CLEAR_MEM;
        S_DONE: nstate = S_DONE;
        default: nstate = S_IDLE;
    endcase
end

always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        state <= S_IDLE;
        sys_rstn <= 1'b0;
        test_mode <= 1'b1;
        addr_counter <= 10'd0;
        ofmap_idx <= 8'd0;
        test_id <= 4'd0;
        testcase_fail <= 1'b0;
        cpu_addi_sw_fail <= 1'b0;
        cpu_lw_fail <= 1'b0;
        cpu_add_sub_fail <= 1'b0;
        cpu_beq_fail <= 1'b0;
        cpu_blt_fail <= 1'b0;
        cnn_pass_count <= 4'd0;
        pass_count <= 4'd0;
        fail_count <= 4'd0;
        cycle_counter <= 32'd0;
        testcase_cycle_count <= 32'd0;
        total_cycle_count <= 32'd0;
        captured_addr13 <= 32'd0;
        captured_ofmap_start <= 10'd0;
    end
    else begin
        state <= nstate;
        case (state)
            S_IDLE: begin
                sys_rstn <= 1'b0;
                test_mode <= 1'b1;
                if (start_bt_pulse) begin
                    addr_counter <= 10'd0;
                    ofmap_idx <= 8'd0;
                    test_id <= 4'd0;
                    testcase_fail <= 1'b0;
                    cpu_addi_sw_fail <= 1'b0;
                    cpu_lw_fail <= 1'b0;
                    cpu_add_sub_fail <= 1'b0;
                    cpu_beq_fail <= 1'b0;
                    cpu_blt_fail <= 1'b0;
                    cnn_pass_count <= 4'd0;
                    pass_count <= 4'd0;
                    fail_count <= 4'd0;
                    cycle_counter <= 32'd0;
                    testcase_cycle_count <= 32'd0;
                    total_cycle_count <= 32'd0;
                    captured_addr13 <= 32'd0;
                    captured_ofmap_start <= 10'd0;
                end
            end
            S_CLEAR_MEM: begin
                sys_rstn <= 1'b0;
                test_mode <= 1'b1;
                if (addr_counter == 10'd1023) begin
                    addr_counter <= 10'd0;
                end
                else begin
                    addr_counter <= addr_counter + 10'd1;
                end
            end
            S_LOAD_INIT_REQ: begin
                sys_rstn <= 1'b0;
                test_mode <= 1'b1;
            end
            S_LOAD_INIT_WRITE: begin
                sys_rstn <= 1'b0;
                test_mode <= 1'b1;
                if (addr_counter == 10'd1023) begin
                    addr_counter <= 10'd0;
                end
                else begin
                    addr_counter <= addr_counter + 10'd1;
                end
            end
            S_WRITE_START_REQ: begin
                sys_rstn <= 1'b0;
                test_mode <= 1'b1;
            end
            S_WRITE_START_WRITE: begin
                sys_rstn <= 1'b0;
                test_mode <= 1'b1;
                addr_counter <= 10'd0;
                ofmap_idx <= 8'd0;
                testcase_fail <= 1'b0;
                cycle_counter <= 32'd0;
                testcase_cycle_count <= 32'd0;
                captured_addr13 <= 32'd0;
                captured_ofmap_start <= 10'd0;
            end
            S_RELEASE_SYS_RESET: begin
                sys_rstn <= 1'b1;
                test_mode <= 1'b0;
            end
            S_RUN: begin
                sys_rstn <= 1'b1;
                test_mode <= 1'b0;
                if (finish_event) begin
                    testcase_cycle_count <= cycle_counter + 32'd1;
                    if (cpu_we && (cpu_addr == 10'd13) && cpu_wdata[0]) begin
                        captured_addr13 <= cpu_wdata;
                        captured_ofmap_start <= cpu_wdata[10:1];
                    end
                end
                else begin
                    if (run_timeout_event) begin
                        testcase_cycle_count <= cycle_counter;
                        captured_addr13 <= 32'd0;
                        captured_ofmap_start <= 10'd0;
                        testcase_fail <= 1'b1;
                    end
                    else begin
                        cycle_counter <= cycle_counter + 32'd1;
                    end
                end
            end
            S_CHECK_PREP: begin
                sys_rstn <= 1'b0;
                test_mode <= 1'b1;
                addr_counter <= 10'd960;
                ofmap_idx <= 8'd0;
            end
            S_READ_ADDR13_REQ: begin
                sys_rstn <= 1'b0;
                test_mode <= 1'b1;
            end
            S_READ_ADDR13_CMP: begin
                sys_rstn <= 1'b0;
                test_mode <= 1'b1;
                captured_addr13 <= mem_rdata;
                captured_ofmap_start <= addr13_ofmap_start;
                if ((mem_rdata[0] != 1'b1) || (addr13_ofmap_end_exclusive > 11'd960)) begin
                    testcase_fail <= 1'b1;
                end
            end
            S_READ_RESERVED_REQ: begin
                sys_rstn <= 1'b0;
                test_mode <= 1'b1;
            end
            S_READ_RESERVED_CMP: begin
                sys_rstn <= 1'b0;
                test_mode <= 1'b1;
                if (mem_rdata != golden_word) begin
                    case (addr_counter)
                        10'd965: cpu_addi_sw_fail <= 1'b1;
                        10'd966: cpu_lw_fail <= 1'b1;
                        10'd967, 10'd968: cpu_add_sub_fail <= 1'b1;
                        10'd969, 10'd970: cpu_beq_fail <= 1'b1;
                        10'd971, 10'd972: cpu_blt_fail <= 1'b1;
                        default: begin
                            // Inputs [960:964] and unused outputs [973:1023]
                            // should remain equal to the CPU golden block. Since
                            // there is no separate score item for illegal writes,
                            // any mismatch here invalidates all CPU subtests.
                            cpu_addi_sw_fail <= 1'b1;
                            cpu_lw_fail <= 1'b1;
                            cpu_add_sub_fail <= 1'b1;
                            cpu_beq_fail <= 1'b1;
                            cpu_blt_fail <= 1'b1;
                        end
                    endcase
                end
                if (addr_counter == 10'd1023) begin
                    addr_counter <= 10'd0;
                end
                else begin
                    addr_counter <= addr_counter + 10'd1;
                end
            end
            S_READ_OFMAP_REQ: begin
                sys_rstn <= 1'b0;
                test_mode <= 1'b1;
            end
            S_READ_OFMAP_CMP: begin
                sys_rstn <= 1'b0;
                test_mode <= 1'b1;
                if (mem_rdata != golden_word) begin
                    testcase_fail <= 1'b1;
                end
                if (ofmap_idx == (ofmap_word_count - 8'd1)) begin
                    ofmap_idx <= 8'd0;
                end
                else begin
                    ofmap_idx <= ofmap_idx + 8'd1;
                end
            end
            S_UPDATE_SCORE: begin
                sys_rstn <= 1'b0;
                test_mode <= 1'b1;
                total_cycle_count <= total_cycle_count + testcase_cycle_count;
                cnn_pass_count <= cnn_pass_count + cnn_pass_inc;
                if (test_id == 4'd9) begin
                    // Final score = 10 CNN testcase scores + 5 CPU subtest scores.
                    pass_count <= pass_count + cnn_pass_inc + cpu_pass_score;
                    fail_count <= fail_count + cnn_fail_inc + cpu_fail_score;
                end
                else begin
                    pass_count <= pass_count + cnn_pass_inc;
                    fail_count <= fail_count + cnn_fail_inc;
                end
            end
            S_NEXT_TEST: begin
                sys_rstn <= 1'b0;
                test_mode <= 1'b1;
                addr_counter <= 10'd0;
                ofmap_idx <= 8'd0;
                testcase_fail <= 1'b0;
                cycle_counter <= 32'd0;
                testcase_cycle_count <= 32'd0;
                captured_addr13 <= 32'd0;
                captured_ofmap_start <= 10'd0;
                if (test_id != 4'd9) begin
                    test_id <= test_id + 4'd1;
                end
            end
            S_DONE: begin
                sys_rstn <= 1'b0;
                test_mode <= 1'b1;
            end
            default: begin
                sys_rstn <= 1'b0;
                test_mode <= 1'b1;
                addr_counter <= 10'd0;
                ofmap_idx <= 8'd0;
                test_id <= 4'd0;
                testcase_fail <= 1'b0;
                cpu_addi_sw_fail <= 1'b0;
                cpu_lw_fail <= 1'b0;
                cpu_add_sub_fail <= 1'b0;
                cpu_beq_fail <= 1'b0;
                cpu_blt_fail <= 1'b0;
                cnn_pass_count <= 4'd0;
                pass_count <= 4'd0;
                fail_count <= 4'd0;
                cycle_counter <= 32'd0;
                testcase_cycle_count <= 32'd0;
                total_cycle_count <= 32'd0;
                captured_addr13 <= 32'd0;
                captured_ofmap_start <= 10'd0;
            end
        endcase
    end
end

always @(*) begin
    tc_addr = {MEM_AW{1'b0}};
    tc_wdata = {MEM_DW{1'b0}};
    tc_we = 1'b0;
    case (state)
        S_CLEAR_MEM: begin
            tc_addr = addr_counter;
            tc_wdata = 32'h00000000;
            tc_we = 1'b1;
        end
        S_LOAD_INIT_REQ: begin
            tc_addr = addr_counter;
            tc_wdata = 32'h00000000;
            tc_we = 1'b0;
        end
        S_LOAD_INIT_WRITE: begin
            tc_addr = addr_counter;
            tc_wdata = init_word;
            tc_we = 1'b1;
        end
        S_WRITE_START_REQ: begin
            tc_addr = 10'd11;
            tc_wdata = 32'h00000000;
            tc_we = 1'b0;
        end
        S_WRITE_START_WRITE: begin
            tc_addr = 10'd11;
            tc_wdata = {31'd0, 1'b1};
            tc_we = 1'b1;
        end
        S_READ_ADDR13_REQ: begin
            tc_addr = 10'd13;
            tc_wdata = 32'h00000000;
            tc_we = 1'b0;
        end
        S_READ_ADDR13_CMP: begin
            tc_addr = 10'd13;
            tc_wdata = 32'h00000000;
            tc_we = 1'b0;
        end
        S_READ_RESERVED_REQ: begin
            tc_addr = addr_counter;
            tc_wdata = 32'h00000000;
            tc_we = 1'b0;
        end
        S_READ_RESERVED_CMP: begin
            tc_addr = addr_counter;
            tc_wdata = 32'h00000000;
            tc_we = 1'b0;
        end
        S_READ_OFMAP_REQ: begin
            tc_addr = captured_ofmap_start + ofmap_addr_offset;
            tc_wdata = 32'h00000000;
            tc_we = 1'b0;
        end
        S_READ_OFMAP_CMP: begin
            tc_addr = captured_ofmap_start + ofmap_addr_offset;
            tc_wdata = 32'h00000000;
            tc_we = 1'b0;
        end
        default: begin
            tc_addr = {MEM_AW{1'b0}};
            tc_wdata = {MEM_DW{1'b0}};
            tc_we = 1'b0;
        end
    endcase
end

always @(*) begin
    feature_size = 6'd10;
    case (test_id)
        4'd0: feature_size = 6'd10;
        4'd1: feature_size = 6'd12;
        4'd2: feature_size = 6'd14;
        4'd3: feature_size = 6'd16;
        4'd4: feature_size = 6'd18;
        4'd5: feature_size = 6'd20;
        4'd6: feature_size = 6'd22;
        4'd7: feature_size = 6'd24;
        4'd8: feature_size = 6'd26;
        4'd9: feature_size = 6'd32;
        default: feature_size = 6'd10;
    endcase
end

always @(*) begin
    init_lookup_addr = ((state == S_WRITE_START_REQ) || (state == S_WRITE_START_WRITE)) ? 10'd11 : addr_counter;
    ofmap_addr_offset = {{(MEM_AW-8){1'b0}}, ofmap_idx};
end

always @(*) begin
    final_ofmap_size_ext = {6'd0, feature_size} - 12'd4;
    ofmap_elem_count_ext = final_ofmap_size_ext * final_ofmap_size_ext;
    ofmap_word_count = (ofmap_elem_count_ext[9:0] + 10'd3) >> 2;
end

always @(*) begin
    addr13_ofmap_start = mem_rdata[10:1];
    addr13_ofmap_end_exclusive = {1'b0, mem_rdata[10:1]} + {3'd0, ofmap_word_count};
end

always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        start_sync0 <= 1'b0;
        start_sync1 <= 1'b0;
        start_stable <= 1'b0;
        start_stable_d <= 1'b0;
        start_db_cnt <= 20'd0;
    end
    else begin
        start_sync0 <= start_bt;
        start_sync1 <= start_sync0;
        start_stable_d <= start_stable;
        if (start_sync1 == start_stable) begin
            start_db_cnt <= 20'd0;
        end
        else begin
            if (start_db_cnt == DEBOUNCE_MAX) begin
                start_stable <= start_sync1;
                start_db_cnt <= 20'd0;
            end
            else begin
                start_db_cnt <= start_db_cnt + 20'd1;
            end
        end
    end
end

always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        result_sync0 <= 1'b0;
        result_sync1 <= 1'b0;
        result_stable <= 1'b0;
        result_stable_d <= 1'b0;
        result_db_cnt <= 20'd0;
    end
    else begin
        result_sync0 <= result_bt;
        result_sync1 <= result_sync0;
        result_stable_d <= result_stable;
        if (result_sync1 == result_stable) begin
            result_db_cnt <= 20'd0;
        end
        else begin
            if (result_db_cnt == DEBOUNCE_MAX) begin
                result_stable <= result_sync1;
                result_db_cnt <= 20'd0;
            end
            else begin
                result_db_cnt <= result_db_cnt + 20'd1;
            end
        end
    end
end

always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        score_sw_sync0 <= 1'b0;
        score_sw_sync1 <= 1'b0;
    end
    else begin
        score_sw_sync0 <= score_sw;
        score_sw_sync1 <= score_sw_sync0;
    end
end

always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        scan_counter <= 16'd0;
        display_mode <= 2'd0;
    end
    else begin
        scan_counter <= scan_counter + 16'd1;
        if (result_bt_pulse) begin
            display_mode <= display_mode + 2'd1;
        end
    end
end

always @(*) begin
    // Count mode format: [CPU tens][CPU ones][CNN tens][CNN ones].
    // CPU is 0~5, CNN is 0~10, so no binary-to-decimal divider is needed.
    // Example: CPU=5, CNN=10 -> 0510.
    count_display_bcd[15:12] = 4'd0;
    count_display_bcd[11:8]  = cpu_pass_score;
    count_display_bcd[7:4]   = (cnn_pass_count == 4'd10) ? 4'd1 : 4'd0;
    count_display_bcd[3:0]   = (cnn_pass_count == 4'd10) ? 4'd0 : cnn_pass_count;

    // Score mode format: 0000~0100, decimal score out of 100.
    // The score is always a multiple of 5, so use a small case table instead of / and %.
    case (weighted_score_decimal)
        8'd0:   score_display_bcd = 16'h0000;
        8'd5:   score_display_bcd = 16'h0005;
        8'd10:  score_display_bcd = 16'h0010;
        8'd15:  score_display_bcd = 16'h0015;
        8'd20:  score_display_bcd = 16'h0020;
        8'd25:  score_display_bcd = 16'h0025;
        8'd30:  score_display_bcd = 16'h0030;
        8'd35:  score_display_bcd = 16'h0035;
        8'd40:  score_display_bcd = 16'h0040;
        8'd45:  score_display_bcd = 16'h0045;
        8'd50:  score_display_bcd = 16'h0050;
        8'd55:  score_display_bcd = 16'h0055;
        8'd60:  score_display_bcd = 16'h0060;
        8'd65:  score_display_bcd = 16'h0065;
        8'd70:  score_display_bcd = 16'h0070;
        8'd75:  score_display_bcd = 16'h0075;
        8'd80:  score_display_bcd = 16'h0080;
        8'd85:  score_display_bcd = 16'h0085;
        8'd90:  score_display_bcd = 16'h0090;
        8'd95:  score_display_bcd = 16'h0095;
        8'd100: score_display_bcd = 16'h0100;
        default: score_display_bcd = 16'h0000;
    endcase

    display_value = 16'h0000;
    case (display_mode)
        // In normal result mode, use score_sw to choose count display or score display.
        2'd0: display_value = score_sw_sync1 ? score_display_bcd : count_display_bcd;
        2'd1: display_value = total_cycle_count[15:0];
        2'd2: display_value = total_cycle_count[31:16];
        2'd3: display_value = {4'h0, test_id, 3'd0, state};
        default: display_value = 16'h0000;
    endcase
end

always @(*) begin
    display_nibble = 4'h0;
    anode = 4'b0000;
    case (scan_sel)
        2'd0: begin
            display_nibble = display_value[3:0];
            anode = 4'b0001;
        end
        2'd1: begin
            display_nibble = display_value[7:4];
            anode = 4'b0010;
        end
        2'd2: begin
            display_nibble = display_value[11:8];
            anode = 4'b0100;
        end
        2'd3: begin
            display_nibble = display_value[15:12];
            anode = 4'b1000;
        end
        default: begin
            display_nibble = 4'h0;
            anode = 4'b0000;
        end
    endcase
end

always @(*) begin
    seven_seg = 7'b0000000;
    case (display_nibble)
        4'h0: seven_seg = 7'b1111110;
        4'h1: seven_seg = 7'b0110000;
        4'h2: seven_seg = 7'b1101101;
        4'h3: seven_seg = 7'b1111001;
        4'h4: seven_seg = 7'b0110011;
        4'h5: seven_seg = 7'b1011011;
        4'h6: seven_seg = 7'b1011111;
        4'h7: seven_seg = 7'b1110000;
        4'h8: seven_seg = 7'b1111111;
        4'h9: seven_seg = 7'b1111011;
        4'ha: seven_seg = 7'b1110111;
        4'hb: seven_seg = 7'b0011111;
        4'hc: seven_seg = 7'b1001110;
        4'hd: seven_seg = 7'b0111101;
        4'he: seven_seg = 7'b1001111;
        4'hf: seven_seg = 7'b1000111;
        default: seven_seg = 7'b0000000;
    endcase
end

init_rom init_rom_inst (
    .clka(clk),
    .ena(1'b1),
    .addra(init_rom_addr),
    .douta(init_word)
);

golden_rom golden_rom_inst (
    .clka(clk),
    .ena(1'b1),
    .addra(golden_rom_addr),
    .douta(golden_word)
);

endmodule
