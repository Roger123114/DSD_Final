`ifndef DATA_MEM_INIT_FILE
`define DATA_MEM_INIT_FILE "RAM_case0.mem"
`endif

module Data_mem(
    input         clka,
    input         ena,
    input         wea,
    input  [9:0]  addra,
    input  [31:0] dina,
    output [31:0] douta,
    input         clkb,
    input         enb,
    input         web,
    input  [9:0]  addrb,
    input  [31:0] dinb,
    output [31:0] doutb
);
`ifdef USE_XILINX_IP
    RAM u_ram_ip(
        .clka(clka),
        .wea(wea),
        .addra(addra),
        .dina(dina),
        .douta(douta),
        .clkb(clkb),
        .web(web),
        .addrb(addrb),
        .dinb(dinb),
        .doutb(doutb)
    );
`else
    reg [31:0] mem [0:1023];
    reg [31:0] douta_r, doutb_r;
    integer i;

    assign douta = douta_r;
    assign doutb = doutb_r;

    initial begin
        for (i = 0; i < 1024; i = i + 1) begin
            mem[i] = 32'd0;
        end
        $readmemh(`DATA_MEM_INIT_FILE, mem);
    end

    always @(posedge clka) begin
        if (ena) begin
            douta_r <= mem[addra];
            if (wea) begin
                mem[addra] <= dina;
            end
        end
    end

    always @(posedge clkb) begin
        if (enb) begin
            doutb_r <= mem[addrb];
            if (web) begin
                mem[addrb] <= dinb;
            end
        end
    end
`endif
endmodule
