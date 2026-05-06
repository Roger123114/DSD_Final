module CNN(
    input              clk,
    input              rstn,
    input      [31:0]  doutb,
    output reg         web,
    output reg         enb,
    output reg [31:0]  dinb,
    output reg [9:0]   addr,
    output reg         done
);
    localparam [9:0] CFG_ADDR6    = 10'd6;
    localparam [9:0] CFG_ADDR12   = 10'd12;
    localparam [9:0] CFG_ADDR13   = 10'd13;
    localparam [9:0] BIAS0_ADDR   = 10'd14;
    localparam [9:0] BIAS1_ADDR   = 10'd15;
    localparam [9:0] IFMAP_BASE   = 10'd16;
    localparam [9:0] SCRATCH_BASE = 10'd704;

    localparam [4:0] ST_IDLE_REQ     = 5'd0,
                     ST_IDLE_GET     = 5'd1,
                     ST_CFG12_REQ    = 5'd2,
                     ST_CFG12_GET    = 5'd3,
                     ST_CFG13_REQ    = 5'd4,
                     ST_CFG13_GET    = 5'd5,
                     ST_BIAS0_REQ    = 5'd6,
                     ST_BIAS0_GET    = 5'd7,
                     ST_BIAS1_REQ    = 5'd8,
                     ST_BIAS1_GET    = 5'd9,
                     ST_W_REQ        = 5'd10,
                     ST_W_GET        = 5'd11,
                     ST_L1_INIT      = 5'd12,
                     ST_L2_INIT      = 5'd13,
                     ST_WIN_REQ      = 5'd14,
                     ST_WIN_GET      = 5'd15,
                     ST_PIXEL_PACK   = 5'd16,
                     ST_PACK_WRITE   = 5'd17,
                     ST_ADVANCE_PIX  = 5'd18,
                     ST_DONE_WRITE   = 5'd19,
                     ST_DONE_HOLD    = 5'd20;

    reg [4:0] state, nstate;

    reg       layer_sel;  // 0: layer 1, 1: layer 2
    reg [5:0] feature_size;
    reg [5:0] inter_size;
    reg [5:0] out_size;
    reg [9:0] output_start_addr;
    reg [9:0] load_word_idx;
    reg [9:0] calc_row;
    reg [9:0] calc_col;
    reg [9:0] row0_ptr;
    reg [9:0] row1_ptr;
    reg [9:0] row2_ptr;
    reg [3:0] read_idx;
    reg [9:0] pack_word_idx;
    reg [1:0] pack_cnt;
    reg [31:0] pack_reg;

    reg signed [7:0] bias0_code, bias1_code;
    reg signed [7:0] w0_0, w0_1, w0_2, w0_3, w0_4, w0_5, w0_6, w0_7, w0_8;
    reg signed [7:0] w1_0, w1_1, w1_2, w1_3, w1_4, w1_5, w1_6, w1_7, w1_8;
    reg signed [7:0] win0, win1, win2, win3, win4, win5, win6, win7, win8;
    reg signed [31:0] conv_acc;

    wire [9:0] read_elem_ptr;
    wire [9:0] read_word_addr;
    wire [1:0] read_byte_sel;
    wire signed [7:0] read_byte;
    wire signed [7:0] conv_code;
    wire [5:0] current_out_size;
    wire pixel_last;
    wire pack_write_needed;

    assign read_elem_ptr = window_elem_ptr(read_idx);
    assign read_word_addr = (layer_sel ? SCRATCH_BASE : IFMAP_BASE) + (read_elem_ptr >> 2);
    assign read_byte_sel = read_elem_ptr[1:0];
    assign read_byte = select_byte(doutb, read_byte_sel);
    assign conv_code = sat_q1_6(round_ties_to_even(conv_acc));
    assign current_out_size = layer_sel ? out_size : inter_size;
    assign pixel_last = (calc_row == ({4'd0, current_out_size} - 10'd1)) &&
                        (calc_col == ({4'd0, current_out_size} - 10'd1));
    assign pack_write_needed = (pack_cnt == 2'd3) || pixel_last;

    always @(*) begin
        conv_acc = 32'sd0;
        if (layer_sel) begin
            conv_acc = conv_acc + mul_q1_6(win0, w1_0);
            conv_acc = conv_acc + mul_q1_6(win1, w1_1);
            conv_acc = conv_acc + mul_q1_6(win2, w1_2);
            conv_acc = conv_acc + mul_q1_6(win3, w1_3);
            conv_acc = conv_acc + mul_q1_6(win4, w1_4);
            conv_acc = conv_acc + mul_q1_6(win5, w1_5);
            conv_acc = conv_acc + mul_q1_6(win6, w1_6);
            conv_acc = conv_acc + mul_q1_6(win7, w1_7);
            conv_acc = conv_acc + mul_q1_6(win8, w1_8);
            conv_acc = conv_acc + (sxt8(bias1_code) <<< 6);
        end
        else begin
            conv_acc = conv_acc + mul_q1_6(win0, w0_0);
            conv_acc = conv_acc + mul_q1_6(win1, w0_1);
            conv_acc = conv_acc + mul_q1_6(win2, w0_2);
            conv_acc = conv_acc + mul_q1_6(win3, w0_3);
            conv_acc = conv_acc + mul_q1_6(win4, w0_4);
            conv_acc = conv_acc + mul_q1_6(win5, w0_5);
            conv_acc = conv_acc + mul_q1_6(win6, w0_6);
            conv_acc = conv_acc + mul_q1_6(win7, w0_7);
            conv_acc = conv_acc + mul_q1_6(win8, w0_8);
            conv_acc = conv_acc + (sxt8(bias0_code) <<< 6);
        end
    end

    always @(*) begin
        case (state)
            ST_IDLE_REQ: begin
                nstate = ST_IDLE_GET;
            end
            ST_IDLE_GET: begin
                nstate = doutb[0] ? ST_CFG12_REQ : ST_IDLE_REQ;
            end
            ST_CFG12_REQ: begin
                nstate = ST_CFG12_GET;
            end
            ST_CFG12_GET: begin
                nstate = ST_CFG13_REQ;
            end
            ST_CFG13_REQ: begin
                nstate = ST_CFG13_GET;
            end
            ST_CFG13_GET: begin
                nstate = ST_BIAS0_REQ;
            end
            ST_BIAS0_REQ: begin
                nstate = ST_BIAS0_GET;
            end
            ST_BIAS0_GET: begin
                nstate = ST_BIAS1_REQ;
            end
            ST_BIAS1_REQ: begin
                nstate = ST_BIAS1_GET;
            end
            ST_BIAS1_GET: begin
                nstate = ST_W_REQ;
            end
            ST_W_REQ: begin
                nstate = ST_W_GET;
            end
            ST_W_GET: begin
                nstate = (load_word_idx == 10'd5) ? ST_L1_INIT : ST_W_REQ;
            end
            ST_L1_INIT: begin
                nstate = ST_WIN_REQ;
            end
            ST_L2_INIT: begin
                nstate = ST_WIN_REQ;
            end
            ST_WIN_REQ: begin
                nstate = ST_WIN_GET;
            end
            ST_WIN_GET: begin
                nstate = (read_idx == 4'd8) ? ST_PIXEL_PACK : ST_WIN_REQ;
            end
            ST_PIXEL_PACK: begin
                nstate = pack_write_needed ? ST_PACK_WRITE : ST_ADVANCE_PIX;
            end
            ST_PACK_WRITE: begin
                nstate = pixel_last ? (layer_sel ? ST_DONE_WRITE : ST_L2_INIT) : ST_ADVANCE_PIX;
            end
            ST_ADVANCE_PIX: begin
                nstate = ST_WIN_REQ;
            end
            ST_DONE_WRITE: begin
                nstate = ST_DONE_HOLD;
            end
            ST_DONE_HOLD: begin
                nstate = ST_IDLE_REQ;
            end
            default: begin
                nstate = ST_IDLE_REQ;
            end
        endcase
    end

    always @(*) begin
        enb = 1'b1;
        web = 1'b0;
        dinb = 32'd0;
        addr = 10'd0;

        case (state)
            ST_IDLE_REQ: begin
                addr = CFG_ADDR6;
            end
            ST_CFG12_REQ: begin
                addr = CFG_ADDR12;
            end
            ST_CFG13_REQ: begin
                addr = CFG_ADDR13;
            end
            ST_BIAS0_REQ: begin
                addr = BIAS0_ADDR;
            end
            ST_BIAS1_REQ: begin
                addr = BIAS1_ADDR;
            end
            ST_W_REQ: begin
                addr = load_word_idx;
            end
            ST_WIN_REQ: begin
                addr = read_word_addr;
            end
            ST_PACK_WRITE: begin
                addr = (layer_sel ? output_start_addr : SCRATCH_BASE) + pack_word_idx;
                dinb = pack_reg;
                web = 1'b1;
            end
            ST_DONE_WRITE: begin
                addr = CFG_ADDR13;
                dinb = {21'd0, output_start_addr, 1'b1};
                web = 1'b1;
            end
            default: begin
                addr = 10'd0;
            end
        endcase
    end

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            state <= ST_IDLE_REQ;
            layer_sel <= 1'b0;
            feature_size <= 6'd0;
            inter_size <= 6'd0;
            out_size <= 6'd0;
            output_start_addr <= 10'd0;
            load_word_idx <= 10'd0;
            calc_row <= 10'd0;
            calc_col <= 10'd0;
            row0_ptr <= 10'd0;
            row1_ptr <= 10'd0;
            row2_ptr <= 10'd0;
            read_idx <= 4'd0;
            pack_word_idx <= 10'd0;
            pack_cnt <= 2'd0;
            pack_reg <= 32'd0;
            bias0_code <= 8'd0;
            bias1_code <= 8'd0;
            done <= 1'b0;
            w0_0 <= 8'd0; w0_1 <= 8'd0; w0_2 <= 8'd0; w0_3 <= 8'd0; w0_4 <= 8'd0;
            w0_5 <= 8'd0; w0_6 <= 8'd0; w0_7 <= 8'd0; w0_8 <= 8'd0;
            w1_0 <= 8'd0; w1_1 <= 8'd0; w1_2 <= 8'd0; w1_3 <= 8'd0; w1_4 <= 8'd0;
            w1_5 <= 8'd0; w1_6 <= 8'd0; w1_7 <= 8'd0; w1_8 <= 8'd0;
            win0 <= 8'd0; win1 <= 8'd0; win2 <= 8'd0; win3 <= 8'd0; win4 <= 8'd0;
            win5 <= 8'd0; win6 <= 8'd0; win7 <= 8'd0; win8 <= 8'd0;
        end
        else begin
            state <= nstate;
            done <= (state == ST_DONE_WRITE);

            case (state)
                ST_CFG12_GET: begin
                    feature_size <= doutb[6:1];
                    inter_size <= doutb[6:1] - 6'd2;
                    out_size <= doutb[6:1] - 6'd4;
                end
                ST_CFG13_GET: begin
                    output_start_addr <= (doutb[10:1] == 10'd0) ? 10'd272 : doutb[10:1];
                end
                ST_BIAS0_GET: begin
                    bias0_code <= doutb[7:0];
                end
                ST_BIAS1_GET: begin
                    bias1_code <= doutb[7:0];
                    load_word_idx <= 10'd0;
                end
                ST_W_GET: begin
                    case (load_word_idx)
                        10'd0: begin
                            w0_0 <= doutb[31:24];
                            w0_1 <= doutb[23:16];
                            w0_2 <= doutb[15:8];
                            w0_3 <= doutb[7:0];
                        end
                        10'd1: begin
                            w0_4 <= doutb[31:24];
                            w0_5 <= doutb[23:16];
                            w0_6 <= doutb[15:8];
                            w0_7 <= doutb[7:0];
                        end
                        10'd2: begin
                            w0_8 <= doutb[31:24];
                        end
                        10'd3: begin
                            w1_0 <= doutb[31:24];
                            w1_1 <= doutb[23:16];
                            w1_2 <= doutb[15:8];
                            w1_3 <= doutb[7:0];
                        end
                        10'd4: begin
                            w1_4 <= doutb[31:24];
                            w1_5 <= doutb[23:16];
                            w1_6 <= doutb[15:8];
                            w1_7 <= doutb[7:0];
                        end
                        10'd5: begin
                            w1_8 <= doutb[31:24];
                            load_word_idx <= 10'd0;
                        end
                        default: begin
                            load_word_idx <= 10'd0;
                        end
                    endcase

                    if (load_word_idx != 10'd5) begin
                        load_word_idx <= load_word_idx + 10'd1;
                    end
                end
                ST_L1_INIT: begin
                    layer_sel <= 1'b0;
                    calc_row <= 10'd0;
                    calc_col <= 10'd0;
                    row0_ptr <= 10'd0;
                    row1_ptr <= {4'd0, feature_size};
                    row2_ptr <= ({4'd0, feature_size} << 1);
                    read_idx <= 4'd0;
                    pack_word_idx <= 10'd0;
                    pack_cnt <= 2'd0;
                    pack_reg <= 32'd0;
                end
                ST_L2_INIT: begin
                    layer_sel <= 1'b1;
                    calc_row <= 10'd0;
                    calc_col <= 10'd0;
                    row0_ptr <= 10'd0;
                    row1_ptr <= {4'd0, inter_size};
                    row2_ptr <= ({4'd0, inter_size} << 1);
                    read_idx <= 4'd0;
                    pack_word_idx <= 10'd0;
                    pack_cnt <= 2'd0;
                    pack_reg <= 32'd0;
                end
                ST_WIN_GET: begin
                    case (read_idx)
                        4'd0: win0 <= read_byte;
                        4'd1: win1 <= read_byte;
                        4'd2: win2 <= read_byte;
                        4'd3: win3 <= read_byte;
                        4'd4: win4 <= read_byte;
                        4'd5: win5 <= read_byte;
                        4'd6: win6 <= read_byte;
                        4'd7: win7 <= read_byte;
                        4'd8: win8 <= read_byte;
                        default: win0 <= win0;
                    endcase

                    if (read_idx != 4'd8) begin
                        read_idx <= read_idx + 4'd1;
                    end
                end
                ST_PIXEL_PACK: begin
                    pack_reg <= insert_pack_byte(pack_reg, pack_cnt, conv_code);
                    if (!pack_write_needed) begin
                        pack_cnt <= pack_cnt + 2'd1;
                    end
                end
                ST_PACK_WRITE: begin
                    pack_reg <= 32'd0;
                    pack_cnt <= 2'd0;
                    if (!pixel_last) begin
                        pack_word_idx <= pack_word_idx + 10'd1;
                    end
                end
                ST_ADVANCE_PIX: begin
                    read_idx <= 4'd0;
                    if (calc_col == ({4'd0, current_out_size} - 10'd1)) begin
                        calc_col <= 10'd0;
                        calc_row <= calc_row + 10'd1;
                        row0_ptr <= row0_ptr + 10'd3;
                        row1_ptr <= row1_ptr + 10'd3;
                        row2_ptr <= row2_ptr + 10'd3;
                    end
                    else begin
                        calc_col <= calc_col + 10'd1;
                        row0_ptr <= row0_ptr + 10'd1;
                        row1_ptr <= row1_ptr + 10'd1;
                        row2_ptr <= row2_ptr + 10'd1;
                    end
                end
                ST_DONE_HOLD: begin
                    layer_sel <= 1'b0;
                    load_word_idx <= 10'd0;
                    calc_row <= 10'd0;
                    calc_col <= 10'd0;
                    row0_ptr <= 10'd0;
                    row1_ptr <= 10'd0;
                    row2_ptr <= 10'd0;
                    read_idx <= 4'd0;
                    pack_word_idx <= 10'd0;
                    pack_cnt <= 2'd0;
                    pack_reg <= 32'd0;
                end
                default: begin
                end
            endcase
        end
    end

    function [9:0] window_elem_ptr;
        input [3:0] idx;
        begin
            case (idx)
                4'd0: window_elem_ptr = row0_ptr;
                4'd1: window_elem_ptr = row0_ptr + 10'd1;
                4'd2: window_elem_ptr = row0_ptr + 10'd2;
                4'd3: window_elem_ptr = row1_ptr;
                4'd4: window_elem_ptr = row1_ptr + 10'd1;
                4'd5: window_elem_ptr = row1_ptr + 10'd2;
                4'd6: window_elem_ptr = row2_ptr;
                4'd7: window_elem_ptr = row2_ptr + 10'd1;
                4'd8: window_elem_ptr = row2_ptr + 10'd2;
                default: window_elem_ptr = row0_ptr;
            endcase
        end
    endfunction

    function signed [7:0] select_byte;
        input [31:0] word_in;
        input [1:0] byte_sel;
        begin
            case (byte_sel)
                2'd0: select_byte = word_in[31:24];
                2'd1: select_byte = word_in[23:16];
                2'd2: select_byte = word_in[15:8];
                2'd3: select_byte = word_in[7:0];
                default: select_byte = 8'sd0;
            endcase
        end
    endfunction

    function [31:0] insert_pack_byte;
        input [31:0] word_in;
        input [1:0] byte_sel;
        input [7:0] byte_in;
        begin
            case (byte_sel)
                2'd0: insert_pack_byte = {byte_in, word_in[23:0]};
                2'd1: insert_pack_byte = {word_in[31:24], byte_in, word_in[15:0]};
                2'd2: insert_pack_byte = {word_in[31:16], byte_in, word_in[7:0]};
                2'd3: insert_pack_byte = {word_in[31:8], byte_in};
                default: insert_pack_byte = word_in;
            endcase
        end
    endfunction

    function signed [31:0] sxt8;
        input signed [7:0] value_in;
        begin
            sxt8 = {{24{value_in[7]}}, value_in};
        end
    endfunction

    function signed [31:0] mul_q1_6;
        input signed [7:0] a;
        input signed [7:0] b;
        begin
            mul_q1_6 = sxt8(a) * sxt8(b);
        end
    endfunction

    function signed [31:0] round_ties_to_even;
        input signed [31:0] value_in;
        reg sign_neg;
        reg [31:0] mag;
        reg [31:0] base_q;
        reg [5:0] rem_q;
        begin
            sign_neg = value_in[31];
            if (sign_neg) begin
                mag = ~value_in + 32'd1;
            end
            else begin
                mag = value_in;
            end

            base_q = mag >> 6;
            rem_q = mag[5:0];

            if (rem_q > 6'd32) begin
                base_q = base_q + 32'd1;
            end
            else if ((rem_q == 6'd32) && base_q[0]) begin
                base_q = base_q + 32'd1;
            end

            if (sign_neg) begin
                round_ties_to_even = -$signed(base_q);
            end
            else begin
                round_ties_to_even = $signed(base_q);
            end
        end
    endfunction

    function signed [7:0] sat_q1_6;
        input signed [31:0] value_in;
        begin
            if (value_in > 32'sd127) begin
                sat_q1_6 = 8'sd127;
            end
            else if (value_in < -32'sd128) begin
                sat_q1_6 = -8'sd128;
            end
            else begin
                sat_q1_6 = value_in[7:0];
            end
        end
    endfunction
endmodule
