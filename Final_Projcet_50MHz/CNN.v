module CNN(
    input clk,
    input rstn,

    input [31:0] doutb,
    output web,
    output enb,
    output [31:0] dinb,
    output [9:0] addr,
    output done
);

wire in_fifo_wen;
wire [2:0] w_str_wen;
wire [7:0] f_size;
wire f_size_valid;
wire out_fifo_ren;
wire [31:0] out_data_cnn;
wire finish_dinb;
wire [31:0] finish_data;
wire in_fifo_full;
wire in_fifo_empty;
wire out_fifo_empty;
wire bias_wen;
wire out_fifo_flush;
wire [2:0] out_fifo_flush_bytes;
wire out_pixels_done;

CNN_Engine cnn_engine_inst(
    .clk(clk),
    .rstn(rstn),
    .in_data(doutb),
    .in_fifo_wen(in_fifo_wen),
    .w_str_wen(w_str_wen),
    .bias_wen(bias_wen),
    .f_size(f_size),
    .f_size_valid(f_size_valid),
    .out_fifo_ren(out_fifo_ren),
    .out_fifo_flush(out_fifo_flush),
    .out_fifo_flush_bytes(out_fifo_flush_bytes),
    .out_data(out_data_cnn),
    .in_fifo_full(in_fifo_full),
    .in_fifo_empty(in_fifo_empty),
    .out_fifo_empty(out_fifo_empty),
    .out_pixels_done(out_pixels_done)
);

assign dinb = (finish_dinb) ? finish_data : out_data_cnn;

CNN_FSM cnn_fsm_inst(
    .clk(clk),
    .rstn(rstn),
    .doutb(doutb),
    .f_size(f_size),
    .f_size_valid(f_size_valid),
    .w_str_wen(w_str_wen),
    .bias_wen(bias_wen),
    .addr(addr),
    .enb(enb),
    .web(web),
    .in_fifo_full(in_fifo_full),
    .in_fifo_empty(in_fifo_empty),
    .in_fifo_wen(in_fifo_wen),
    .out_fifo_empty(out_fifo_empty),
    .out_fifo_ren(out_fifo_ren),
    .out_fifo_flush(out_fifo_flush),
    .out_fifo_flush_bytes(out_fifo_flush_bytes),
    .out_pixels_done(out_pixels_done),
    .finish_dinb(finish_dinb),
    .finish_data(finish_data),
    .done(done)
);

endmodule


module CNN_FSM(
    input clk,
    input rstn,

    input [31:0] doutb,

    output reg [7:0] f_size,
    output reg f_size_valid,

    output reg [2:0] w_str_wen,
    output reg bias_wen,

    output reg [9:0] addr,
    output enb,
    output reg web,
    input in_fifo_full,
    input in_fifo_empty,
    output reg in_fifo_wen,
    input out_fifo_empty,
    output reg out_fifo_ren,
    output out_fifo_flush,
    output [2:0] out_fifo_flush_bytes,
    input out_pixels_done,

    output reg finish_dinb,
    output reg [31:0] finish_data,
    output reg done
);

localparam [3:0]
    CHECK      = 4'd0,
    FETCH_INFO = 4'd1,
    LOAD       = 4'd2,
    RETURN     = 4'd3,
    NEXT_LAYER = 4'd4,
    DRAIN_LAYER = 4'd5,
    FINISH     = 4'd6;

reg [3:0] state, next_state;

reg [11:0] cnt0, cnt1;
reg [3:0] cnt;
reg [9:0] ini_end_cnt, des_end_cnt;
reg [9:0] final_output_base;
reg load_flag, return_flag;
reg start;
reg layer;
reg [7:0] original_N;

localparam check_cnt = 3;
localparam fetch_cnt = 7;
localparam start_addr = 6;
localparam cfg_addr = 12;
localparam status_addr = 13;
localparam [9:0] INTER_BASE = 10'd320;
localparam [9:0] INPUT_BASE = 10'd16;
localparam [9:0] WEIGHT0_BASE = 10'd0;
localparam [9:0] WEIGHT1_BASE = 10'd3;
localparam [9:0] BIAS0_ADDR = 10'd14;
localparam [9:0] BIAS1_ADDR = 10'd15;

wire [7:0] current_f_size;
wire [7:0] current_out_size;
wire [9:0] weight_base;
wire [9:0] bias_addr;
wire [9:0] input_base;
wire [9:0] output_base;

assign current_f_size = (layer == 1'b0) ? original_N : (original_N - 8'd2);
assign current_out_size = current_f_size - 8'd2;
assign weight_base = (layer == 1'b0) ? WEIGHT0_BASE : WEIGHT1_BASE;
assign bias_addr = (layer == 1'b0) ? BIAS0_ADDR : BIAS1_ADDR;
assign input_base = (layer == 1'b0) ? INPUT_BASE : INTER_BASE;
assign output_base = (layer == 1'b0) ? INTER_BASE : final_output_base;

always @(*) begin
    next_state = state;
    case(state)
        CHECK: begin
            if (cnt == 3 && start) next_state = FETCH_INFO;
            else next_state = CHECK;
        end
        FETCH_INFO: begin
            if (cnt == fetch_cnt) next_state = LOAD;
            else next_state = FETCH_INFO;
        end
        LOAD: begin
            if (load_flag || in_fifo_full) next_state = RETURN;
            else next_state = LOAD;
        end
        RETURN: begin
            if (return_flag && !layer) next_state = DRAIN_LAYER;
            else if (return_flag) next_state = FINISH;
            else if (out_fifo_empty) next_state = LOAD;
            else next_state = RETURN;
        end
        DRAIN_LAYER: begin
            if(in_fifo_empty && out_fifo_empty) next_state = NEXT_LAYER;
            else next_state = DRAIN_LAYER;
        end
        NEXT_LAYER: begin
            next_state = FETCH_INFO;
        end
        FINISH: begin
            if (cnt == 1) next_state = CHECK;
            else next_state = FINISH;
        end
        default: begin
            next_state = CHECK;
        end
    endcase
end

always @(posedge clk or negedge rstn) begin
    if(!rstn) state <= CHECK;
    else state <= next_state;
end

always @(posedge clk or negedge rstn) begin
    if(!rstn) begin
        cnt <= 0;
        cnt0 <= 0;
        cnt1 <= 0;
        start <= 0;
        f_size <= 0;
        f_size_valid <= 0;
        des_end_cnt <= 0;
        ini_end_cnt <= 0;
        load_flag <= 0;
        return_flag <= 0;
        w_str_wen <= 0;
        bias_wen <= 0;
        addr <= 0;
        web <= 0;
        in_fifo_wen <= 0;
        out_fifo_ren <= 0;
        finish_dinb <= 0;
        finish_data <= 0;
        done <= 0;
        final_output_base <= 0;
        layer <= 0;
        original_N <= 0;
    end
    else begin
       case(state)
            CHECK: begin
                cnt <= (cnt == check_cnt) ? 0 : cnt + 1;
                cnt0 <= 0;
                cnt1 <= 0;
                layer <= 0;
                web <= 0;
                w_str_wen <= 0;
                bias_wen <= 0;
                addr <= (cnt == 0) ? start_addr : 0;
                start <= (cnt == 0) ? 0 :
                    (cnt == 2) ? doutb[0] : start;
                f_size_valid <= 0;
                in_fifo_wen <= 0;
                out_fifo_ren <= 0;
                load_flag <= 0;
                return_flag <= 0;
                des_end_cnt <= 0;
                ini_end_cnt <= 0;
                finish_dinb <= 0;
                finish_data <= 0;
                done <= 0;
                original_N <= (cnt == 0) ? 0 : original_N;
                f_size <= (cnt == 0) ? 0 : f_size;
            end
            FETCH_INFO: begin
                // bram_model is a 1-cycle synchronous read, and w_str/bias
                // capture these registered enables one clock later.
                // cnt2 samples DataMem[12], cnt3 samples DataMem[13],
                // cnt4/5/6 capture weight words, and cnt7 captures bias
                // before arming CNN_Core with f_size_valid.
                cnt <= (cnt == fetch_cnt) ? 0 : cnt + 1;
                cnt0 <= (cnt == 4) ? input_base : cnt0;
                cnt1 <= (cnt == 4) ? output_base : cnt1;
                original_N <= (cnt == 2 && !layer) ? {2'b00, doutb[6:1]} : original_N;
                final_output_base <= (cnt == 3 && !layer) ?
                    ((doutb[10:1] == 10'd0) ? 10'd272 : doutb[10:1]) :
                    final_output_base;
                f_size <= (cnt == 2 && !layer) ? {2'b00, doutb[6:1]} : current_f_size;
                f_size_valid <= (cnt == fetch_cnt) ? 1 : 0;
                ini_end_cnt <= (cnt == 4) ? input_base + word_count_ceil4(current_f_size) : ini_end_cnt;
                des_end_cnt <= (cnt == 4) ? output_base + word_count_ceil4(current_out_size) : des_end_cnt;
                addr <= (cnt == 0) ? cfg_addr :
                    (cnt == 1) ? status_addr :
                    (cnt == 2) ? weight_base :
                    (cnt == 3) ? weight_base + 10'd1 :
                    (cnt == 4) ? weight_base + 10'd2 :
                    (cnt == 5) ? bias_addr :
                    (cnt == fetch_cnt) ? 10'd0 : addr;
                w_str_wen[0] <= (cnt == 3) ? 1 : 0;
                w_str_wen[1] <= (cnt == 4) ? 1 : 0;
                w_str_wen[2] <= (cnt == 5) ? 1 : 0;
                bias_wen <= (cnt == 6) ? 1 : 0;
                done <= 0;
            end
            LOAD: begin
                cnt <= (in_fifo_full || load_flag) ? 0 : cnt + 1;
                f_size_valid <= 0;
                addr <= cnt0;
                cnt0 <= (in_fifo_full && cnt == 0) ? cnt0 :
                    (!in_fifo_full && cnt0 == ini_end_cnt) ? cnt0 :
                    (in_fifo_full) ? addr - 1 : cnt0 + 1;
                in_fifo_wen <= (in_fifo_full || load_flag || addr == ini_end_cnt) ? 0 :
                    (cnt >= 1) ? 1 : 0;
                load_flag <= (!in_fifo_full && addr == ini_end_cnt) || (load_flag) ? 1 : 0;
                done <= 0;
            end
            RETURN: begin
                cnt <= (out_fifo_empty || return_flag) ? 0 : cnt + 1;
                f_size_valid <= 0;
                addr <= cnt1;
                cnt1 <= ((cnt == 0) || (cnt1 == des_end_cnt) || out_fifo_empty) ? cnt1 : cnt1 + 1;
                web <= (cnt == 0 || out_fifo_empty || return_flag) ? 0 : 1;
                out_fifo_ren <= (out_fifo_empty || return_flag) ? 0 : 1;
                return_flag <= (out_fifo_empty && cnt1 == des_end_cnt) ? 1 : 0;
                done <= 0;
            end
            DRAIN_LAYER: begin
                cnt <= 0;
                cnt0 <= 0;
                cnt1 <= 0;
                f_size_valid <= 0;
                load_flag <= 0;
                return_flag <= 0;
                w_str_wen <= 0;
                bias_wen <= 0;
                in_fifo_wen <= 0;
                out_fifo_ren <= 0;
                web <= 0;
                addr <= 0;
                done <= 0;
            end
            NEXT_LAYER: begin
                cnt <= 0;
                cnt0 <= 0;
                cnt1 <= 0;
                layer <= 1;
                f_size <= original_N - 8'd2;
                f_size_valid <= 0;
                load_flag <= 0;
                return_flag <= 0;
                w_str_wen <= 0;
                bias_wen <= 0;
                in_fifo_wen <= 0;
                out_fifo_ren <= 0;
                web <= 0;
                addr <= 0;
                done <= 0;
            end
            FINISH: begin
                cnt <= (cnt == 1) ? 0 : cnt + 1;
                addr <= (cnt == 0) ? status_addr : 0;
                web <= (cnt == 0) ? 1 : 0;
                finish_dinb <= (cnt == 0) ? 1 : 0;
                finish_data <= (cnt == 0) ? {21'd0, final_output_base, 1'b1} : 0;
                done <= (cnt == 0) ? 1 : 0;
            end
            default: begin
                cnt <= 0;
                cnt0 <= 0;
                cnt1 <= 0;
                start <= 0;
                f_size <= 0;
                f_size_valid <= 0;
                des_end_cnt <= 0;
                ini_end_cnt <= 0;
                load_flag <= 0;
                return_flag <= 0;
                w_str_wen <= 0;
                bias_wen <= 0;
                addr <= 0;
                web <= 0;
                in_fifo_wen <= 0;
                out_fifo_ren <= 0;
                finish_dinb <= 0;
                finish_data <= 0;
                done <= 0;
                final_output_base <= 0;
                layer <= 0;
                original_N <= 0;
            end
       endcase
    end
end

assign enb = 1'b1;
assign out_fifo_flush = (state == RETURN) && out_pixels_done && (out_fifo_flush_bytes != 3'd4) && (cnt1 == (des_end_cnt - 10'd1));
assign out_fifo_flush_bytes = final_word_bytes(current_out_size);

function [9:0] word_count_ceil4;
    input [7:0] size;
    reg [15:0] pixels;
    reg [15:0] words;
    begin
        pixels = size * size;
        words = (pixels + 16'd3) >> 2;
        word_count_ceil4 = words[9:0];
    end
endfunction

function [2:0] final_word_bytes;
    input [7:0] size;
    reg [15:0] pixels;
    reg [1:0] rem;
    begin
        pixels = size * size;
        rem = pixels[1:0];
        final_word_bytes = (rem == 2'd0) ? 3'd4 : {1'b0, rem};
    end
endfunction

endmodule
