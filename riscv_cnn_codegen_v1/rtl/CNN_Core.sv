module CNN_Core(
    input CLK,
    input RSTN,
    input stall_all,
    input [7:0] in_x,
    input in_valid,
    input [7:0] f_size,
    input f_size_valid,
    input [7:0] w00, w01, w02,
    input [7:0] w10, w11, w12,
    input [7:0] w20, w21, w22,
    output logic [19:0] out_num,
    output logic out_valid
);

logic [7:0] in_reg;
logic in_valid_reg;
always_ff@( posedge CLK or negedge RSTN ) begin
    if(!RSTN) begin
        in_reg <= 0;
        in_valid_reg <= 0;
    end
    else if(!stall_all) begin
        in_reg <= in_x;
        in_valid_reg <= in_valid;
    end
end

logic system_enable, fsm_enable;
FSM fsm0 (
    .CLK(CLK),
    .RSTN(RSTN),
    .stall_all(stall_all),
    .in_valid(in_valid_reg),
    .f_size_valid(f_size_valid),
    .f_size(f_size),
    .fsm_enable(fsm_enable),
    .out_valid(out_valid)
);

assign system_enable = fsm_enable && !stall_all;

logic [7:0] in0_d, in1_d, in2_d;
logic [7:0] in_LB1, in_LB2;
systolic systolic0 (
    .clk(CLK),
    .reset(RSTN),
    .enable(system_enable),
    .w00(w00), .w01(w01), .w02(w02),
    .w10(w10), .w11(w11), .w12(w12),
    .w20(w20), .w21(w21), .w22(w22),
    .in0(in_LB2), .in1(in_LB1), .in2(in_reg),
    .in0_d(in0_d), .in1_d(in1_d), .in2_d(in2_d),
    .out(out_num)
);

logic [7:0] LB_delay;
always_ff@( posedge CLK or negedge RSTN ) begin
    if(!RSTN) begin
        LB_delay <= 0;
    end
    else if( f_size_valid ) begin
        LB_delay <= f_size -3 -1;
    end
end

line_buffer #(
    .WIDTH(8),
    .DEPTH(32)
) line_buffer0 (
    .clk(CLK),
    .reset(RSTN),
    .enable(system_enable),
    .delay(LB_delay),
    .in(in2_d),
    .out(in_LB1)
);

line_buffer #(
    .WIDTH(8),
    .DEPTH(32)
) line_buffer1 (
    .clk(CLK),
    .reset(RSTN),
    .enable(system_enable),
    .delay(LB_delay),
    .in(in1_d),
    .out(in_LB2)
);


endmodule

module FSM(
    input CLK,
    input RSTN,
    input in_valid,
    input stall_all,
    input f_size_valid,
    input [7:0] f_size,
    output logic fsm_enable,
    output logic out_valid
);

logic [7:0] f_size_reg;
logic [7:0] wait_cycles0, wait_cycles1;
logic [7:0] ext_cycles0, ext_cycles1;
logic [7:0] pulse_cycles0;
logic [7:0] out_cycles0; 
logic [7:0] finish_cycles0;
always_ff@( posedge CLK or negedge RSTN ) begin
    if(!RSTN) begin
        f_size_reg <= 0;
        wait_cycles0 <= 0;
        wait_cycles1 <= 0;
        ext_cycles0 <= 0;
        ext_cycles1 <= 0;
        pulse_cycles0 <= 0;
        out_cycles0 <= 0;
        finish_cycles0 <= 0;
    end
    else if( f_size_valid ) begin
        f_size_reg <= f_size-1;
        wait_cycles0 <= 2;
        wait_cycles1 <= 2;
        ext_cycles0 <= f_size-1 -1;
        ext_cycles1 <= f_size-1;
        pulse_cycles0 <= 0;
        out_cycles0 <= 2;
        finish_cycles0 <= 1;
    end
end

typedef enum logic [2:0] {  
    IDLE,
    WAIT,
    OUT,
    PULSE,
    EXT,
    FINISH
} state_t;
state_t state, next_state;

logic [7:0] cnt0, cnt1;
	always_comb begin : FSM_comb
	    next_state = state;
	    case(state)
	        IDLE: begin
	            if (f_size_valid) next_state = WAIT;
	            else next_state = IDLE;
	        end
	        WAIT: begin
	            if (cnt0==wait_cycles0 && cnt1==wait_cycles1) next_state = OUT;
	            else next_state = WAIT;
	        end
	        OUT: begin
	            if (cnt0==(ext_cycles0) && cnt1==(ext_cycles1)) next_state = EXT;
	            else if (cnt0==(pulse_cycles0)) next_state = PULSE;
	            else next_state = OUT;
	        end
	        PULSE: begin
	            if (cnt0==(out_cycles0)) next_state = OUT;
	            else next_state = PULSE;
	        end
	        EXT: begin
	            if (cnt0==finish_cycles0) next_state = FINISH;
	            else next_state = EXT;
	        end
        FINISH: begin
            next_state = IDLE;
        end
    endcase
end

logic [1:0] cnt;
logic out_valid_reg, fsm_enable_reg;
always_ff@( posedge CLK or negedge RSTN ) begin
    if(!RSTN) begin
        state <= IDLE;
        fsm_enable_reg <= 0;
        out_valid_reg <= 0;
        cnt0 <= 0;
        cnt1 <= 0;
        cnt <= 0;
    end 
    else if(!stall_all) begin
        state <= next_state;
        case(state)
            IDLE: begin
                fsm_enable_reg <= 0;
                out_valid_reg <= 0;
                cnt0 <= 0;
                cnt1 <= 0;
                cnt <= 0;
            end
            WAIT: begin
                fsm_enable_reg <= 1;
                out_valid_reg <= 0;
                if(in_valid) begin
                    cnt0 <= (cnt0==f_size_reg)? 0 : cnt0+1;
                    cnt1 <= (cnt0==f_size_reg)? cnt1+1 : cnt1;
                end
            end
            OUT: begin
                fsm_enable_reg <= 1;
                out_valid_reg <= 1;
                if(in_valid) begin
                    cnt0 <= (cnt0==f_size_reg)? 0 : cnt0+1;
                    cnt1 <= (cnt0==f_size_reg)? cnt1+1 : cnt1;
                end
            end
            PULSE: begin
                fsm_enable_reg <= 1;
                out_valid_reg <= 0;
                if(in_valid) begin
                    cnt0 <= (cnt0==f_size_reg)? 0 : cnt0+1;
                    cnt1 <= (cnt0==f_size_reg)? cnt1+1 : cnt1;
                end
            end
            EXT: begin
                fsm_enable_reg <= 1;
                out_valid_reg <= 1;
                cnt0 <= cnt==0? 0 : cnt0+1;
                cnt1 <= 0;
                cnt <= cnt + 1;
            end
            FINISH: begin
                cnt0 <= 0;
                cnt1 <= 0;
            end
        endcase
    end
end

assign out_valid = out_valid_reg && (state==EXT || in_valid);
assign fsm_enable = fsm_enable_reg && (state==EXT || in_valid);

endmodule

module line_buffer#(
    parameter WIDTH = 8,
    parameter DEPTH = 256
)(
    input clk,
    input reset,
    input enable,
    input [WIDTH-1:0] in,
    input [7:0] delay,
    output logic [WIDTH-1:0] out
);

logic [WIDTH-1:0] delay_reg;
always_ff@( posedge clk or negedge reset ) begin
    if(!reset) begin
        delay_reg <= 0;
    end
    else begin
        delay_reg <= delay-2;
    end
end

logic [WIDTH-1:0] buffer [0:DEPTH-1];
integer i, j;
always_ff@( posedge clk or negedge reset ) begin
    if(!reset) begin
        for( i=DEPTH-1; i>=0; i=i-1 ) begin
            buffer[i] <= 0;
        end
    end
    else if( enable ) begin
        for( j=DEPTH-1; j>0; j=j-1 ) begin
            buffer[j] <= buffer[j-1];
        end
        buffer[0] <= in;
    end
end

always_ff@( posedge clk or negedge reset ) begin
    if(!reset) begin
        out <= 0;
    end
    else if( enable ) begin
        out <= buffer[delay_reg];
    end
end

endmodule


module systolic(
    input clk,
    input reset,
    input enable,
    input [7:0] w00, w01, w02,
    input [7:0] w10, w11, w12,
    input [7:0] w20, w21, w22,
    input [7:0] in0, in1, in2,
    output logic [7:0] in0_d, in1_d, in2_d,
    output logic [19:0] out
);

// 3x3 systolic array
// Row 0
logic [19:0] out00, out01, out02;
row_pe #(
    .WIDTH(8)
) row0 (
    .clk(clk),
    .reset(reset),
    .enable(enable),
    .w0(w02), .w1(w01), .w2(w00),
    .in(in0),
    .bias0(20'd0),
    .bias1(20'd0),
    .bias2(20'd0),
    .in_ddd(in0_d),
    .out0(out00), .out1(out01), .out2(out02)
);

// Row 1
logic [19:0] out10, out11, out12;
row_pe #(
    .WIDTH(8)
) row1 (
    .clk(clk),
    .reset(reset),
    .enable(enable),
    .w0(w12), .w1(w11), .w2(w10),
    .in(in1),
    .bias0(out00),
    .bias1(out01),
    .bias2(out02),
    .in_ddd(in1_d),
    .out0(out10), .out1(out11), .out2(out12)
);

// Row 2
logic [19:0] out20, out21, out22;
row_pe #(
    .WIDTH(8)
) row2 (
    .clk(clk),
    .reset(reset),
    .enable(enable),
    .w0(w22), .w1(w21), .w2(w20),
    .in(in2),
    .bias0(out10),
    .bias1(out11),
    .bias2(out12),
    .in_ddd(in2_d),
    .out0(out20), .out1(out21), .out2(out22)
);

always_ff@( posedge clk or negedge reset ) begin
    if(!reset) begin
        out <= 0;
    end
    else if( enable ) begin
        out <= out20 + out21 + out22;
    end
end

endmodule

module row_pe#(
    parameter WIDTH = 8
)(
    input clk,
    input reset,
    input enable,
    input [WIDTH-1:0] w0, w1, w2,
    input [WIDTH-1:0] in,
    input [19:0] bias0, bias1, bias2,
    output logic [WIDTH-1:0] in_ddd,
    output logic [19:0] out0, out1, out2
); 

logic [WIDTH-1:0] in_d0, in_d1, in_d2;
pe #(
    .WIDTH(WIDTH)
) pe0 (
    .clk(clk),
    .reset(reset),
    .enable(enable),
    .w(w0),
    .in(in),
    .bias(bias0),
    .in_d(in_d0),
    .out(out0)
);

pe #(
    .WIDTH(WIDTH)
) pe1 (
    .clk(clk),
    .reset(reset),
    .enable(enable),
    .w(w1),
    .in(in_d0),
    .bias(bias1),
    .in_d(in_d1),
    .out(out1)
);

pe #(
    .WIDTH(WIDTH)
) pe2 (
    .clk(clk),
    .reset(reset),
    .enable(enable),
    .w(w2),
    .in(in_d1),
    .bias(bias2),
    .in_d(in_d2),
    .out(out2)
);

assign in_ddd = in_d2;

endmodule

module pe#(
    parameter WIDTH = 8
)(
    input clk,
    input reset,
    input enable,
    input [WIDTH-1:0] w,
    input [WIDTH-1:0] in,
    input [19:0] bias,
    output logic [WIDTH-1:0] in_d,
    output logic [19:0] out
);

logic [2*WIDTH-1:0] mult0;
assign mult0 = $signed(w)*$signed(in);
logic [19:0] mult1;
assign mult1 = { {4{mult0[2*WIDTH-1]}}, mult0[2*WIDTH-1 : 0]} + bias;
always_ff@( posedge clk or negedge reset ) begin
    if(!reset) begin
        out <= 0;
        in_d <= 0;
    end
    else if( enable ) begin
        out <= mult1;
        in_d <= in;
    end
end

endmodule
