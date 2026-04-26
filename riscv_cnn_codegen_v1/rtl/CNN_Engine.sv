module CNN_Engine(
    input clk,
    input rstn,
    input [31:0] in_data,
    input in_fifo_wen,
    input [2:0] w_str_wen,
    input [7:0] f_size,
    input f_size_valid,
    input out_fifo_ren,
    output logic [31:0] out_data,
    output logic in_fifo_full,
    output logic out_fifo_empty
);

logic out_fifo_full;

logic in_fifo_empty;
logic in_fifo_ren;
logic [7:0] in_fifo_dout;
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

logic [7:0] w00, w01, w02;
logic [7:0] w10, w11, w12;
logic [7:0] w20, w21, w22;
w_str w_str_inst(
    .clk(clk),
    .rstn(rstn),
    .in_data(in_data),
    .wen(w_str_wen),
    .w00(w00), .w01(w01), .w02(w02),
    .w10(w10), .w11(w11), .w12(w12),
    .w20(w20), .w21(w21), .w22(w22)
);

logic cnn_core_valid;
always_ff @( posedge clk or negedge rstn ) begin
    if(!rstn) begin
        cnn_core_valid <= 0;
    end
    else if( out_fifo_full ) begin
        cnn_core_valid <= 0;
    end
    else begin
        cnn_core_valid <= in_fifo_ren;
    end
end

localparam CNN_width = 20;
logic [CNN_width-1:0] out_data_cnn;
logic out_valid_cnn;
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

logic sat_round_valid;
logic [7:0] sat_round_out, sat_round_out_reg;
sat_round #(
    .in_i_width(8),
    .in_f_width(12),
    .out_i_width(2),
    .out_f_width(6)
) sat_round_inst(
    .in_num(out_data_cnn),
    .out_num(sat_round_out)
);
always_ff @( posedge clk or negedge rstn ) begin 
    if(!rstn) begin
        sat_round_valid <= 0;
        sat_round_out_reg <= 0;
    end
    else if(!out_fifo_full)begin
        sat_round_valid <= out_valid_cnn;
        sat_round_out_reg <= sat_round_out;
    end
end

FIFO_1to4 #(
    .DWIDTH(8),
    .DEPTH(16),
    .ADDR_WIDTH(4)
) fifo_1to4_inst (
    .clk(clk),
    .reset(rstn),
    .wen(sat_round_valid),
    .ren(out_fifo_ren),
    .din(sat_round_out_reg),
    .dout(out_data),
    .full(out_fifo_full),
    .empty(out_fifo_empty)
);

endmodule


module sat_round#(
    parameter in_i_width = 8,
    parameter in_f_width = 8,
    parameter out_i_width = 4,
    parameter out_f_width = 4
)(
    input [in_i_width+in_f_width-1:0] in_num,
    output logic [out_i_width+out_f_width-1:0] out_num
);

localparam in_width = in_i_width + in_f_width;
localparam out_width = out_i_width + out_f_width;
localparam guard_bit = in_f_width - out_f_width;
localparam round_width = in_width - guard_bit + 1;
// in_f_width - out_f_width >= 2

logic [round_width-1:0] round_num;
generate
    if( (in_f_width-out_f_width) >= 2 )begin
        assign round_num = round0(in_num);
    end
    else if( (in_f_width-out_f_width) == 1 ) begin
        assign round_num = round1(in_num);
    end
    else if( (in_f_width-out_f_width) == 0 )begin
        assign round_num = {in_num[in_width-1], in_num[in_width-1 : 0]};
    end
endgenerate

logic [out_width-1:0] sat_num;
assign sat_num = sat(round_num);

assign out_num = sat_num;

function automatic logic [round_width-1:0] round0;
    input [in_width-1:0] in;
    logic G, R, S;
    begin
        G = in[guard_bit];
        R = in[guard_bit-1];
        S = |in[guard_bit-2:0];

        if( (R&&S)||(R&&G) ) begin
            round0 = {in[in_width-1], in[in_width-1 -: round_width-1]} + 1;
        end
        else begin
            round0 = {in[in_width-1], in[in_width-1 -: round_width-1]};
        end
    end
endfunction

function automatic logic [round_width-1:0] round1;
    input [in_width-1:0] in;
    logic G, R;
    begin
        G = in[guard_bit];
        R = in[guard_bit-1];
        if( R&&G ) begin
            round1 = {in[in_width-1], in[in_width-1 -: round_width-1]} + 1;
        end
        else begin
            round1 = {in[in_width-1], in[in_width-1 -: round_width-1]};
        end
    end
endfunction

function automatic logic [out_width-1:0] sat;
    input [round_width-1:0] in;
    logic sign;
    begin
        sign = in[round_width-1];

        if( sign == 1 ) begin
            sat = (&in[round_width-2:out_width-1]==1)? in[out_width-1:0] : {1'b1, {(out_width-1){1'b0}}};
        end
        else begin
            sat = (|in[round_width-2:out_width-1]==1)? {1'b0, {(out_width-1){1'b1}}} : in[out_width-1:0];
        end
    end
endfunction

endmodule


module w_str(
    input clk,
    input rstn,
    input [31:0] in_data,
    input [2:0]wen,
    output logic [7:0] w00, w01, w02,
    output logic [7:0] w10, w11, w12,
    output logic [7:0] w20, w21, w22
);

always_ff @( posedge clk or negedge rstn ) begin
    if(!rstn) begin
        w00 <= 0; w01 <= 0; w02 <= 0;
        w10 <= 0; w11 <= 0; w12 <= 0;
        w20 <= 0; w21 <= 0; w22 <= 0;
    end
    else begin
        if( wen[0] ) begin
            w00 <= in_data[31:24];
            w01 <= in_data[23:16];
            w02 <= in_data[15:8];
            w10 <= in_data[7:0];
        end
        if( wen[1] ) begin
            w11 <= in_data[31:24];
            w12 <= in_data[23:16];
            w20 <= in_data[15:8];
            w21 <= in_data[7:0];
        end
        if( wen[2] ) begin
            w22 <= in_data[31:24];
        end
    end
end

endmodule


module FIFO_4to1#(
    parameter DWIDTH = 8,
    parameter DEPTH = 16, //必須是4的倍數
    parameter ADDR_WIDTH = 4
)(
    input clk, reset,
    input wen, ren,
    input [DWIDTH*4-1:0] din,
    output logic [DWIDTH-1:0] dout,
    output logic full, empty
);

logic [DWIDTH-1:0] mem[DEPTH-1:0];
logic [ADDR_WIDTH-1:0] wptr, rptr;
logic [ADDR_WIDTH-1:0] wptr_p1, wptr_p2, wptr_p3;
logic wptr_O, rptr_O;

always_ff @(posedge clk or negedge reset) begin
    if(!reset)begin
        for(int i=0; i<DEPTH; i=i+1) begin
            mem[i] <= 0;
        end
        wptr <= 0;
        wptr_p1 <= 1;
        wptr_p2 <= 2;
        wptr_p3 <= 3;
        wptr_O <= 0;
    end
    else if(wen && !full)begin
        mem[wptr] <= din[DWIDTH*4-1:DWIDTH*3];
        mem[wptr_p1] <= din[DWIDTH*3-1:DWIDTH*2];
        mem[wptr_p2] <= din[DWIDTH*2-1:DWIDTH*1];
        mem[wptr_p3] <= din[DWIDTH*1-1:DWIDTH*0];
        wptr <= (wptr==(DEPTH-4))? 0 : wptr + 4;
        wptr_p1 <= (wptr_p1==(DEPTH-3))? 1 : wptr_p1 + 4;
        wptr_p2 <= (wptr_p2==(DEPTH-2))? 2 : wptr_p2 + 4;
        wptr_p3 <= (wptr_p3==(DEPTH-1))? 3 : wptr_p3 + 4;
        wptr_O <= (wptr==(DEPTH-4))? ~wptr_O : wptr_O;
    end
end

always_ff @(posedge clk or negedge reset) begin
    if(!reset)begin
        dout <= 0;
        rptr <= 0;
        rptr_O <= 0;
    end
    else begin
        dout <= mem[rptr];
        rptr <= (ren && !empty && rptr==(DEPTH-1))? 0 : 
            (ren && !empty)? rptr + 1 : rptr;
        rptr_O <= (ren && !empty && rptr==(DEPTH-1))? ~rptr_O : rptr_O;
    end
end

assign full = (wptr_O^rptr_O) && (wptr==rptr || wptr_p1==rptr || wptr_p2==rptr || wptr_p3==rptr);
assign empty = (wptr==rptr) && (wptr_O==rptr_O);

endmodule

//注意FIFO的read latency是1 你在送出ren後的下一個cycle才能拿到dout的資料
module FIFO_1to4 #(
    parameter int DWIDTH     = 8,
    parameter int DEPTH      = 16, // 必須是 4 的倍數
    parameter int ADDR_WIDTH = 4
)(
    input  logic                 clk,
    input  logic                 reset,   // active-low (跟你原本一致)
    input  logic                 wen,
    input  logic                 ren,
    input  logic [DWIDTH-1:0]    din,
    output logic [DWIDTH*4-1:0]  dout,
    output logic                 full,
    output logic                 empty
);

logic [DWIDTH-1:0] mem [0:DEPTH-1];

logic [ADDR_WIDTH-1:0] wptr, rptr;
logic [ADDR_WIDTH-1:0] rptr_p1, rptr_p2, rptr_p3;
logic                  wptr_O, rptr_O;
assign rptr_p1 = rptr + 1;
assign rptr_p2 = rptr + 2;
assign rptr_p3 = rptr + 3;

// ============================================================
// Write logic: 1 word per write
// ============================================================
always_ff @(posedge clk or negedge reset) begin
    if (!reset) begin
        for (int i = 0; i < DEPTH; i++) begin
            mem[i] <= '0;
        end
        wptr   <= '0;
        wptr_O <= 1'b0;
    end
    else if (wen && !full) begin
        mem[wptr] <= din;
        if (wptr == DEPTH-1) begin
            wptr   <= '0;
            wptr_O <= ~wptr_O;
        end
        else begin
            wptr   <= wptr + 1;
            wptr_O <= wptr_O;
        end
    end
end

// ============================================================
// Read logic: 4 words per read -> pack into dout
// ============================================================
always_ff @(posedge clk or negedge reset) begin
    if (!reset) begin
        dout   <= '0;
        rptr   <= '0;
        rptr_O <= 1'b0;
    end
    else begin
        dout <= { mem[rptr], mem[rptr_p1], mem[rptr_p2], mem[rptr_p3] };
        if (ren && !empty) begin
            rptr <= (rptr >= DEPTH-4)? 0 : rptr + 4;
            rptr_O <= (rptr >= DEPTH-4)? ~rptr_O : rptr_O;
        end
    end
end

assign empty = ((wptr == rptr)||(wptr == rptr_p1)||(wptr == rptr_p2)||(wptr == rptr_p3)) && (wptr_O == rptr_O);
assign full  = (wptr == rptr) && (wptr_O != rptr_O);

endmodule




