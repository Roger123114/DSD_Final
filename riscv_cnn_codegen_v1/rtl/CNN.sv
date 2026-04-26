module CNN(
    input clk,
    input rstn,

    input [31:0] doutb,
    output logic web, enb,
    output logic [31:0] dinb,
    output logic [9:0] addr
);

logic in_fifo_wen;
logic [2:0] w_str_wen;
logic [7:0] f_size;
logic f_size_valid;
logic out_fifo_ren;
logic [31:0] out_data_cnn;
logic finish_dinb;
CNN_Engine cnn_engine_inst(
    .clk(clk),
    .rstn(rstn),
    .in_data(doutb),
    .in_fifo_wen(in_fifo_wen),
    .w_str_wen(w_str_wen),
    .f_size(f_size),
    .f_size_valid(f_size_valid),
    .out_fifo_ren(out_fifo_ren),
    .out_data(out_data_cnn),
    .in_fifo_full(in_fifo_full),
    .out_fifo_empty(out_fifo_empty)
);
assign dinb = (finish_dinb)? 32'h4000_0000 : out_data_cnn;

CNN_FSM cnn_fsm_inst(
    .clk(clk),
    .rstn(rstn),
    .doutb(doutb),
    .f_size(f_size),
    .f_size_valid(f_size_valid),
    .w_str_wen(w_str_wen),
    .addr(addr),
    .enb(enb),
    .web(web),
    .in_fifo_full(in_fifo_full),
    .in_fifo_wen(in_fifo_wen),
    .out_fifo_empty(out_fifo_empty),
    .out_fifo_ren(out_fifo_ren),
    .finish_dinb(finish_dinb)
);

endmodule


module CNN_FSM(
    input clk,
    input rstn,

    input [31:0] doutb,

    output logic [7:0] f_size,
    output logic f_size_valid,

    output logic [2:0] w_str_wen,

    output logic [9:0] addr,
    output logic enb, web,
    input in_fifo_full,
    output logic in_fifo_wen,
    input out_fifo_empty,
    output logic out_fifo_ren,

    output logic finish_dinb
);

typedef enum logic [3:0] { 
    CHECK,
    FETCH_INFO,
    LOAD,
    RETURN,
    FINISH
} state_t;
state_t state, next_state;

logic [11:0] cnt0, cnt1;
logic [3:0] cnt;
logic [9:0] ini_end_cnt, des_end_cnt;
logic load_flag, return_flag;
	always_comb begin
	    next_state = state;
	    case(state)
	        CHECK: begin
	            if (cnt==3 && start) next_state = FETCH_INFO;
	            else next_state = CHECK;
	        end
	        FETCH_INFO: begin
	            if (cnt==fetch_cnt) next_state = LOAD;
	            else next_state = FETCH_INFO;
	        end
	        LOAD: begin
	            if (load_flag || in_fifo_full) next_state = RETURN;
	            else next_state = LOAD;
	        end
	        RETURN: begin
	            if (return_flag) next_state = FINISH;
	            else if (out_fifo_empty) next_state = LOAD;
	            else next_state = RETURN;
	        end
	        FINISH: begin
	            if (cnt==1) next_state = CHECK;
	            else next_state = FINISH;
	        end
    endcase
end

always_ff @( posedge clk or negedge rstn ) begin
    if(!rstn) state <= CHECK;
    else state <= next_state;
end

logic start;
localparam check_cnt = 3, fetch_cnt = 5;
localparam fmap = 16;
always_ff @( posedge clk or negedge rstn ) begin
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
        addr <= 0;
        web <= 0;
        in_fifo_wen <= 0;
        out_fifo_ren <= 0;
        finish_dinb <= 0;
    end
    else begin
       case(state)
            CHECK: begin
                cnt <= (cnt==check_cnt)? 0 : cnt + 1;
                cnt0 <= 0;
                cnt1 <= 0;
                web <= 0;
                w_str_wen <= 0;
                addr <= (cnt==0)? 10'd768 : 0;
                start <= (cnt==0)? 0 :
                    (cnt==2)? doutb[31] : start;
                f_size <= (cnt==0)? 0 :
                    (cnt==2)? doutb[23:16] : f_size;
                f_size_valid <= (cnt==2 && doutb[31])? 1 : 0;
                in_fifo_wen <= 0;
                out_fifo_ren <= 0;
                load_flag <= 0;
                return_flag <= 0;
                des_end_cnt <= 0;
                ini_end_cnt <= 0;
                finish_dinb <= 0;
            end
            FETCH_INFO: begin
                cnt <= (cnt==fetch_cnt)? 0 : cnt + 1;
                cnt0 <= fmap;
                cnt1 <= (cnt==2)? doutb[9:0] : cnt1;
                ini_end_cnt <= 
                    (cnt==1)? {{2{f_size[7]}}, f_size[7:1]} :
                    (cnt==2)? square(ini_end_cnt) : 
                    (cnt==3)? ini_end_cnt + cnt0 : ini_end_cnt;
                des_end_cnt <= 
                    (cnt==0)? m2(f_size) : 
                    (cnt==1)? {des_end_cnt[9], des_end_cnt[9:1]} : 
                    (cnt==2)? square(des_end_cnt) :     
                    (cnt==3)? des_end_cnt + cnt1 : des_end_cnt;
                addr <= (cnt==0)? 10'd769 :
                    (cnt==5)? 0 : addr+1;
                w_str_wen[0] <= (cnt==2)? 1 : 0;
                w_str_wen[1] <= (cnt==3)? 1 : 0;
                w_str_wen[2] <= (cnt==4)? 1 : 0;
            end
            LOAD: begin
                cnt <= (in_fifo_full || load_flag)? 0 : cnt + 1;
                addr <= cnt0;
                cnt0 <= (in_fifo_full && cnt==0)? cnt0 :
                    (!in_fifo_full && cnt0==ini_end_cnt)? cnt0 :
                    (in_fifo_full)? addr-1 : cnt0+1;
                in_fifo_wen <= (in_fifo_full || load_flag || addr==ini_end_cnt)? 0 : 
                    (cnt>=1)? 1 : 0;
                load_flag <= (!in_fifo_full && addr==ini_end_cnt)||(load_flag)? 1 : 0;
            end
            RETURN: begin
                cnt <= (out_fifo_empty || return_flag)? 0 : cnt + 1;
                addr <= cnt1;
                cnt1 <= ((cnt==0) || (cnt1==des_end_cnt) || out_fifo_empty)? cnt1 : cnt1+1;
                web <= (cnt==0 || out_fifo_empty || return_flag)? 0 : 1;
                out_fifo_ren <= (out_fifo_empty || return_flag)? 0 : 1;
                return_flag <= (out_fifo_empty && cnt1==des_end_cnt)? 1 : 0;
            end
            FINISH: begin
                cnt <= (cnt==1)? 0 : cnt + 1;
                addr <= (cnt==0)? 10'd768 : 0;
                web <= (cnt==0)? 1 : 0;
                finish_dinb <= (cnt==0)? 1 : 0;
            end
       endcase
    end
end

assign enb = 1;

function automatic logic [9:0] square(
input [9:0] x
);
logic [19:0] tmp;
begin
    tmp = x * x;
    square = tmp[9:0];
end
endfunction

function automatic logic [9:0] m2(
input [7:0] x
);
logic [7:0] tmp;
begin
    tmp = x - 2;
    m2 = {{2{tmp[7]}}, tmp[7:0]};
end 
endfunction

endmodule
