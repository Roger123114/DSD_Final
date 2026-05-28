module CNN_Engine(
    input clk,
    input rstn,
    input [31:0] in_data,
    input in_fifo_wen,
    input [2:0] w_str_wen,
    input bias_wen,
    input [7:0] f_size,
    input f_size_valid,
    input out_fifo_ren,
    input out_fifo_flush,
    input [2:0] out_fifo_flush_bytes,
    output [31:0] out_data,
    output in_fifo_full,
    output in_fifo_empty,
    output out_fifo_empty,
    output out_pixels_done
);

wire out_fifo_full;
wire in_fifo_ren;
wire [7:0] in_fifo_dout;

FIFO_4to1 #(
    .DWIDTH(8),
    .DEPTH(16),
    .ADDR_WIDTH(4)
) fifo_4to1_inst (
    .clk(clk),
    .reset(rstn),
    .wen(in_fifo_wen),
    .ren(in_fifo_ren),
    .din(in_data),
    .dout(in_fifo_dout),
    .full(in_fifo_full),
    .empty(in_fifo_empty)
);

assign in_fifo_ren = (!in_fifo_empty && !out_fifo_full);

wire [7:0] w00, w01, w02;
wire [7:0] w10, w11, w12;
wire [7:0] w20, w21, w22;
reg [7:0] bias;

w_str w_str_inst(
    .clk(clk),
    .rstn(rstn),
    .in_data(in_data),
    .wen(w_str_wen),
    .w00(w00), .w01(w01), .w02(w02),
    .w10(w10), .w11(w11), .w12(w12),
    .w20(w20), .w21(w21), .w22(w22)
);

always @(posedge clk or negedge rstn) begin
    if(!rstn) begin
        bias <= 0;
    end
    else if(bias_wen) begin
        bias <= in_data[7:0];
    end
end

reg cnn_core_valid;

always @(posedge clk or negedge rstn) begin
    if(!rstn) begin
        cnn_core_valid <= 0;
    end
    else if(out_fifo_full) begin
        cnn_core_valid <= 0;
    end
    else begin
        cnn_core_valid <= in_fifo_ren;
    end
end

localparam CNN_width = 20;
wire [CNN_width-1:0] out_data_cnn;
wire [CNN_width-1:0] out_data_cnn_bias;
wire signed [CNN_width-1:0] bias_q12;
wire out_valid_cnn;

CNN_Core cnn_core_inst(
    .CLK(clk),
    .RSTN(rstn),
    .in_x(in_fifo_dout),
    .stall_all(out_fifo_full),
    .in_valid(cnn_core_valid),
    .f_size(f_size),
    .f_size_valid(f_size_valid),
    .w00(w00), .w01(w01), .w02(w02),
    .w10(w10), .w11(w11), .w12(w12),
    .w20(w20), .w21(w21), .w22(w22),
    .out_num(out_data_cnn),
    .out_valid(out_valid_cnn)
);

reg sat_round_valid;
reg sat_round_stage_valid;
reg [CNN_width-1:0] sat_round_in_reg;
wire [7:0] sat_round_out;
reg [7:0] sat_round_out_reg;
reg [15:0] output_pixel_count;
reg [15:0] output_pixel_total;
wire out_fifo_byte_wen;

assign bias_q12 = {{6{bias[7]}}, bias, 6'b0};
assign out_data_cnn_bias = $signed(out_data_cnn) + bias_q12;

sat_round #(
    .in_i_width(8),
    .in_f_width(12),
    .out_i_width(2),
    .out_f_width(6)
) sat_round_inst(
    .in_num(sat_round_in_reg),
    .out_num(sat_round_out)
);

always @(posedge clk or negedge rstn) begin
    if(!rstn) begin
        sat_round_valid <= 0;
        sat_round_stage_valid <= 0;
        sat_round_in_reg <= 0;
        sat_round_out_reg <= 0;
        output_pixel_count <= 0;
        output_pixel_total <= 0;
    end
    else if(f_size_valid) begin
        sat_round_valid <= 0;
        sat_round_stage_valid <= 0;
        sat_round_in_reg <= 0;
        sat_round_out_reg <= 0;
        output_pixel_count <= 0;
        output_pixel_total <= output_pixel_total_from_size(f_size);
    end
    else if(!out_fifo_full) begin
        // Pipeline bias-add and round/saturate into separate cycles for timing.
        sat_round_stage_valid <= out_valid_cnn;
        sat_round_in_reg <= out_data_cnn_bias;
        sat_round_valid <= sat_round_stage_valid;
        sat_round_out_reg <= sat_round_out;
        if(out_fifo_byte_wen) begin
            output_pixel_count <= output_pixel_count + 16'd1;
        end
    end
end

assign out_fifo_byte_wen = sat_round_valid && (output_pixel_count < output_pixel_total);
assign out_pixels_done = (output_pixel_total != 0) && (output_pixel_count == output_pixel_total);

FIFO_1to4 #(
    .DWIDTH(8),
    .DEPTH(16),
    .ADDR_WIDTH(4)
) fifo_1to4_inst (
    .clk(clk),
    .reset(rstn),
    .wen(out_fifo_byte_wen),
    .ren(out_fifo_ren),
    .flush(out_fifo_flush),
    .flush_bytes(out_fifo_flush_bytes),
    .din(sat_round_out_reg),
    .dout(out_data),
    .full(out_fifo_full),
    .empty(out_fifo_empty)
);

function [15:0] output_pixel_total_from_size;
    input [7:0] size;
    reg [7:0] out_size;
    begin
        out_size = size - 8'd2;
        output_pixel_total_from_size = out_size * out_size;
    end
endfunction

endmodule


module sat_round#(
    parameter in_i_width = 8,
    parameter in_f_width = 8,
    parameter out_i_width = 4,
    parameter out_f_width = 4
)(
    input [in_i_width+in_f_width-1:0] in_num,
    output [out_i_width+out_f_width-1:0] out_num
);

localparam in_width = in_i_width + in_f_width;
localparam out_width = out_i_width + out_f_width;
localparam guard_bit = in_f_width - out_f_width;
localparam round_width = in_width - guard_bit + 1;

wire [round_width-1:0] round_num;
wire [out_width-1:0] sat_num;

generate
    if((in_f_width - out_f_width) >= 2) begin : gen_round0
        assign round_num = round0(in_num);
    end
    else if((in_f_width - out_f_width) == 1) begin : gen_round1
        assign round_num = round1(in_num);
    end
    else if((in_f_width - out_f_width) == 0) begin : gen_round2
        assign round_num = {in_num[in_width-1], in_num[in_width-1:0]};
    end
endgenerate

assign sat_num = sat(round_num);
assign out_num = sat_num;

function [round_width-1:0] round0;
    input [in_width-1:0] in;
    reg G, R, S;
    begin
        G = in[guard_bit];
        R = in[guard_bit-1];
        S = |in[guard_bit-2:0];

        if((R && S) || (R && G)) begin
            round0 = {in[in_width-1], in[in_width-1 -: round_width-1]} + 1;
        end
        else begin
            round0 = {in[in_width-1], in[in_width-1 -: round_width-1]};
        end
    end
endfunction

function [round_width-1:0] round1;
    input [in_width-1:0] in;
    reg G, R;
    begin
        G = in[guard_bit];
        R = in[guard_bit-1];
        if(R && G) begin
            round1 = {in[in_width-1], in[in_width-1 -: round_width-1]} + 1;
        end
        else begin
            round1 = {in[in_width-1], in[in_width-1 -: round_width-1]};
        end
    end
endfunction

function [out_width-1:0] sat;
    input [round_width-1:0] in;
    reg sign;
    begin
        sign = in[round_width-1];

        if(sign == 1) begin
            sat = (&in[round_width-2:out_width-1] == 1) ? in[out_width-1:0] : {1'b1, {(out_width-1){1'b0}}};
        end
        else begin
            sat = (|in[round_width-2:out_width-1] == 1) ? {1'b0, {(out_width-1){1'b1}}} : in[out_width-1:0];
        end
    end
endfunction

endmodule


module w_str(
    input clk,
    input rstn,
    input [31:0] in_data,
    input [2:0] wen,
    output reg [7:0] w00, w01, w02,
    output reg [7:0] w10, w11, w12,
    output reg [7:0] w20, w21, w22
);

always @(posedge clk or negedge rstn) begin
    if(!rstn) begin
        w00 <= 0; w01 <= 0; w02 <= 0;
        w10 <= 0; w11 <= 0; w12 <= 0;
        w20 <= 0; w21 <= 0; w22 <= 0;
    end
    else begin
        if(wen[0]) begin
            w00 <= in_data[31:24];
            w01 <= in_data[23:16];
            w02 <= in_data[15:8];
            w10 <= in_data[7:0];
        end
        if(wen[1]) begin
            w11 <= in_data[31:24];
            w12 <= in_data[23:16];
            w20 <= in_data[15:8];
            w21 <= in_data[7:0];
        end
        if(wen[2]) begin
            w22 <= in_data[31:24];
        end
    end
end

endmodule


module FIFO_4to1#(
    parameter DWIDTH = 8,
    parameter DEPTH = 16,
    parameter ADDR_WIDTH = 4
)(
    input clk,
    input reset,
    input wen,
    input ren,
    input [DWIDTH*4-1:0] din,
    output reg [DWIDTH-1:0] dout,
    output full,
    output empty
);

reg [DWIDTH-1:0] mem[DEPTH-1:0];
reg [ADDR_WIDTH-1:0] wptr, rptr;
reg [ADDR_WIDTH-1:0] wptr_p1, wptr_p2, wptr_p3;
reg wptr_O, rptr_O;
integer i;

always @(posedge clk or negedge reset) begin
    if(!reset) begin
        for(i = 0; i < DEPTH; i = i + 1) begin
            mem[i] <= 0;
        end
        wptr <= 0;
        wptr_p1 <= 1;
        wptr_p2 <= 2;
        wptr_p3 <= 3;
        wptr_O <= 0;
    end
    else if(wen && !full) begin
        mem[wptr]    <= din[DWIDTH*4-1:DWIDTH*3];
        mem[wptr_p1] <= din[DWIDTH*3-1:DWIDTH*2];
        mem[wptr_p2] <= din[DWIDTH*2-1:DWIDTH*1];
        mem[wptr_p3] <= din[DWIDTH*1-1:DWIDTH*0];
        wptr <= (wptr == (DEPTH-4)) ? 0 : wptr + 4;
        wptr_p1 <= (wptr_p1 == (DEPTH-3)) ? 1 : wptr_p1 + 4;
        wptr_p2 <= (wptr_p2 == (DEPTH-2)) ? 2 : wptr_p2 + 4;
        wptr_p3 <= (wptr_p3 == (DEPTH-1)) ? 3 : wptr_p3 + 4;
        wptr_O <= (wptr == (DEPTH-4)) ? ~wptr_O : wptr_O;
    end
end

always @(posedge clk or negedge reset) begin
    if(!reset) begin
        dout <= 0;
        rptr <= 0;
        rptr_O <= 0;
    end
    else begin
        dout <= mem[rptr];
        rptr <= (ren && !empty && rptr == (DEPTH-1)) ? 0 :
            (ren && !empty) ? rptr + 1 : rptr;
        rptr_O <= (ren && !empty && rptr == (DEPTH-1)) ? ~rptr_O : rptr_O;
    end
end

assign full = (wptr_O ^ rptr_O) && (wptr == rptr || wptr_p1 == rptr || wptr_p2 == rptr || wptr_p3 == rptr);
assign empty = (wptr == rptr) && (wptr_O == rptr_O);

endmodule


module FIFO_1to4 #(
    parameter DWIDTH = 8,
    parameter DEPTH = 16,
    parameter ADDR_WIDTH = 4
)(
    input clk,
    input reset,
    input wen,
    input ren,
    input flush,
    input [2:0] flush_bytes,
    input [DWIDTH-1:0] din,
    output reg [DWIDTH*4-1:0] dout,
    output full,
    output empty
);

reg [DWIDTH-1:0] mem [0:DEPTH-1];

reg [ADDR_WIDTH-1:0] wptr, rptr;
wire [ADDR_WIDTH-1:0] rptr_p1, rptr_p2, rptr_p3;
reg [ADDR_WIDTH:0] count;
wire [2:0] pop_count;
wire [2:0] pack_count;
wire can_write;
wire can_read;
integer k;

assign rptr_p1 = rptr + 1;
assign rptr_p2 = rptr + 2;
assign rptr_p3 = rptr + 3;
assign pop_count = (count >= 5'd4) ? 3'd4 : count[2:0];
assign pack_count = (flush && count < 5'd4) ? flush_bytes : pop_count;
assign can_write = wen && !full;
assign can_read = ren && !empty;

always @(posedge clk or negedge reset) begin
    if(!reset) begin
        for(k = 0; k < DEPTH; k = k + 1) begin
            mem[k] <= 0;
        end
        wptr   <= 0;
        rptr   <= 0;
        count  <= 0;
        dout   <= 0;
    end
    else begin
        if(can_write) begin
            mem[wptr] <= din;
            wptr <= wptr + 1;
        end

        if(can_read) begin
            dout <= {
                mem[rptr],
                (pack_count > 3'd1) ? mem[rptr_p1] : {DWIDTH{1'b0}},
                (pack_count > 3'd2) ? mem[rptr_p2] : {DWIDTH{1'b0}},
                (pack_count > 3'd3) ? mem[rptr_p3] : {DWIDTH{1'b0}}
            };
            rptr <= rptr + pop_count;
        end

        count <= count + (can_write ? 5'd1 : 5'd0) - (can_read ? {2'b00, pop_count} : 5'd0);
    end
end

assign empty = (count < 5'd4) && !(flush && flush_bytes != 0 && count >= {2'b00, flush_bytes});
assign full  = (count == DEPTH);

endmodule
