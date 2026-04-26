module RISCV_CNN(
    input         clk,
    input         rstn,
    input         test_mode,
    input         test_we,
    input  [9:0]  test_addr,
    input  [31:0] test_wdata,
    output [31:0] test_rdata,
    output [9:0]  cpu_dmem_addr_debug,
    output        cpu_dmem_we_debug,
    output [9:0]  cnn_addr_debug,
    output        cnn_we_debug
);
    wire cpu_rstn;
    wire cpu_dmem_en, cpu_dmem_we;
    wire [9:0] cpu_dmem_addr;
    wire [31:0] cpu_dmem_wdata, cpu_dmem_rdata;

    wire mema_en, mema_we;
    wire [9:0] mema_addr;
    wire [31:0] mema_din, mema_dout;

    wire cnn_web, cnn_enb;
    wire [9:0] cnn_addr;
    wire [31:0] cnn_dinb, cnn_doutb;

    assign cpu_rstn = rstn & (~test_mode);
    assign mema_en = test_mode ? 1'b1 : cpu_dmem_en;
    assign mema_we = test_mode ? test_we : cpu_dmem_we;
    assign mema_addr = test_mode ? test_addr : cpu_dmem_addr;
    assign mema_din = test_mode ? test_wdata : cpu_dmem_wdata;
    assign cpu_dmem_rdata = mema_dout;
    assign test_rdata = mema_dout;
    assign cpu_dmem_addr_debug = cpu_dmem_addr;
    assign cpu_dmem_we_debug = cpu_dmem_we;
    assign cnn_addr_debug = cnn_addr;
    assign cnn_we_debug = cnn_web;

    Simple_CPU u_cpu(
        .CLK(clk),
        .RSTN(cpu_rstn),
        .dmem_en(cpu_dmem_en),
        .dmem_we(cpu_dmem_we),
        .dmem_addr(cpu_dmem_addr),
        .dmem_wdata(cpu_dmem_wdata),
        .dmem_rdata(cpu_dmem_rdata)
    );

    CNN u_cnn(
        .clk(clk),
        .rstn(rstn),
        .doutb(cnn_doutb),
        .web(cnn_web),
        .enb(cnn_enb),
        .dinb(cnn_dinb),
        .addr(cnn_addr)
    );

    Data_mem u_data_mem(
        .clka(clk),
        .ena(mema_en),
        .wea(mema_we),
        .addra(mema_addr),
        .dina(mema_din),
        .douta(mema_dout),
        .clkb(clk),
        .enb(cnn_enb),
        .web(cnn_web),
        .addrb(cnn_addr),
        .dinb(cnn_dinb),
        .doutb(cnn_doutb)
    );
endmodule
