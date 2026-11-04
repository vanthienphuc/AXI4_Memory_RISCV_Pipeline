module axi4_subsystem (
    input wire        clk,
    input wire        rst_n,

    // Native Interface from RISC-V Core
    input wire        rd_req,
    input wire        wr_req,
    input wire [31:0] addr,
    input wire [31:0] wdata,
    input wire [3:0] wstrb,
    
    output wire        bridge_busy,
    output wire        rvalid,
    output wire [31:0] rdata,
    output wire        rd_err,
    output wire        wr_done,
    output wire        wr_err
);

// AXI4 internal interconnect wires
    wire [31:0] axi_awaddr;
    wire        axi_awvalid;
    wire        axi_awready;
    
    wire [31:0] axi_wdata;
    wire [3:0] axi_wstrb;
    wire       axi_wvalid;
    wire       axi_wready;
    
    wire [1:0] axi_bresp;
    wire       axi_bvalid;
    wire       axi_bready;
    
    wire [31:0] axi_araddr;
    wire        axi_arvalid;
    wire        axi_arready;
    
    wire [31:0] axi_rdata;
    wire [1:0] axi_rresp;
    wire       axi_rvalid;
    wire       axi_rready;

    axi4_master_bridge u_master (
        .clk(clk),
        .rst_n(rst_n),
        .rd_req(rd_req),
        .wr_req(wr_req),
        .addr(addr),
        .wdata(wdata),
        .wstrb(wstrb),
        .bridge_busy(bridge_busy),
        .rvalid(rvalid),
        .rdata(rdata),
        .rd_err(rd_err),
        .wr_done(wr_done),
        .wr_err(wr_err),
        // AXI AW
        .m_axi_awaddr(axi_awaddr), 
        .m_axi_awvalid(axi_awvalid), 
        .m_axi_awready(axi_awready),
        // AXI W
        .m_axi_wdata(axi_wdata), 
        .m_axi_wstrb(axi_wstrb), 
        .m_axi_wvalid(axi_wvalid), 
        .m_axi_wready(axi_wready),
        // AXI B
        .m_axi_bresp(axi_bresp), 
        .m_axi_bvalid(axi_bvalid), 
        .m_axi_bready(axi_bready),
        // AXI AR
        .m_axi_araddr(axi_araddr), 
        .m_axi_arvalid(axi_arvalid), 
        .m_axi_arready(axi_arready),
        // AXI R
        .m_axi_rdata(axi_rdata), 
        .m_axi_rresp(axi_rresp), 
        .m_axi_rvalid(axi_rvalid), 
        .m_axi_rready(axi_rready)
    );

    axi4_slave_mem u_slave (
        .clk(clk),
        .rst_n(rst_n),
        // AXI AW
        .s_axi_awaddr(axi_awaddr), 
        .s_axi_awvalid(axi_awvalid), 
        .s_axi_awready(axi_awready),
        // AXI W
        .s_axi_wdata(axi_wdata), 
        .s_axi_wstrb(axi_wstrb), 
        .s_axi_wvalid(axi_wvalid), 
        .s_axi_wready(axi_wready),
        // AXI B
        .s_axi_bresp(axi_bresp), 
        .s_axi_bvalid(axi_bvalid), 
        .s_axi_bready(axi_bready),
        // AXI AR
        .s_axi_araddr(axi_araddr), 
        .s_axi_arvalid(axi_arvalid), 
        .s_axi_arready(axi_arready),
        // AXI R
        .s_axi_rdata(axi_rdata), 
        .s_axi_rresp(axi_rresp), 
        .s_axi_rvalid(axi_rvalid), 
        .s_axi_rready(axi_rready)
    );

endmodule




