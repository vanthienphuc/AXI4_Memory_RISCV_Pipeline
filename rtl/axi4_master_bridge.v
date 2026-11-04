module axi4_master_bridge (
    input wire        clk,
    input wire        rst_n,

    // Interface RISC-V Core
    input wire        rd_req,
    input wire        wr_req,
    input wire [31:0] addr,
    input wire [31:0] wdata,
    input wire [3:0]  wstrb,

    output wire        bridge_busy, // Busy flag for Hazard Unit
    
    output reg         rvalid,
    output reg [31:0] rdata,
    output reg        rd_err, // Read error flag

    output reg        wr_done,
    output reg        wr_err, // Write error flag

    // AXI4-Lite Master Interface
    // AW Channel
    output wire [31:0] m_axi_awaddr,
    output wire        m_axi_awvalid,
    input wire         m_axi_awready,
    
    // W Channel
    output wire [31:0] m_axi_wdata,
    output wire [3:0]  m_axi_wstrb,
    output wire        m_axi_wvalid,
    input wire         m_axi_wready,
    
    // B Channel
    input wire [1:0]  m_axi_bresp,
    input wire        m_axi_bvalid,
    output wire       m_axi_bready,
    
    // AR Channel
    output wire [31:0] m_axi_araddr,
    output wire        m_axi_arvalid,
    input wire         m_axi_arready,
    
    // R Channel
    input wire [31:0] m_axi_rdata,
    input wire [1:0]  m_axi_rresp,
    input wire        m_axi_rvalid,
    output wire       m_axi_rready
);

    // FSM States
    localparam R_IDLE     = 2'b00;
    localparam R_AR_VALID = 2'b01;
    localparam R_WAIT     = 2'b10;

    localparam W_IDLE       = 2'b00;
    localparam W_AW_W_VALID = 2'b01;
    localparam W_B_WAIT     = 2'b10;

    // State Registers
    reg [1:0] r_state, r_next;
    reg [1:0] w_state, w_next;

    // Internal Registers for Payload & Control
    reg [31:0] latched_raddr;
    reg [31:0] latched_waddr;
    reg [31:0] latched_wdata;
    reg [3:0] latched_wstrb;
    
    reg aw_done;
    reg w_done;

    assign bridge_busy = (r_state != R_IDLE) || (w_state != W_IDLE);

    // =========================================================
    // READ FSM
    // =========================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_state <= R_IDLE;
            rvalid <= 1'b0;
            rdata <= 32'd0;
        end else begin
            rvalid <= 1'b0; 
            rd_err <= 1;
            
            case (r_state)
                R_IDLE: begin
                    if (rd_req) begin
                        latched_raddr <= addr;
                        r_state <= R_AR_VALID;
                    end
                end
                
                R_AR_VALID: begin
                    if (m_axi_arvalid && m_axi_arready) begin
                        r_state <= R_WAIT;
                    end
                end
                
                R_WAIT: begin
                    if (m_axi_rvalid && m_axi_rready) begin
                        rdata <= m_axi_rdata;
                        rd_err <= (m_axi_rresp != 2'b00); // Set error flag if rresp != OKAY
                        rvalid <= 1'b1; // Send rvalid = 1 for CPU
                        r_state <= R_IDLE;
                    end
                end
            endcase
        end
    end

    // Signal output channel Read 
    assign m_axi_araddr = latched_raddr;
    assign m_axi_arvalid = (r_state == R_AR_VALID);
    assign m_axi_rready = (r_state == R_WAIT);

    // =========================================================
    // WRITE FSM
    // =========================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            w_state <= W_IDLE;
            aw_done <= 1'b0;
            w_done <= 1'b0;
            wr_done <= 1'b0;
            wr_err <= 1'b0;
        end else begin
            wr_done <= 1'b0;
            wr_err  <= 1'b0;
            
            case (w_state)
                W_IDLE: begin
                    if (wr_req) begin
                        latched_waddr <= addr;
                        latched_wdata <= wdata;
                        latched_wstrb <= wstrb;
                        aw_done <= 1'b0;
                        w_done <= 1'b0;
                        w_state <= W_AW_W_VALID;
                    end
                end
                
                W_AW_W_VALID: begin
                    // Update flag when each channel cuccessfully completes handshake
                    if (m_axi_awvalid && m_axi_awready) aw_done <= 1'b1;
                    if (m_axi_wvalid && m_axi_wready)   w_done  <= 1'b1;
                    
                    // Change state when AW&W channels are complete
                    if ((aw_done || (m_axi_awvalid && m_axi_awready)) && 
                        (w_done  || (m_axi_wvalid  && m_axi_wready))) begin
                        w_state <= W_B_WAIT;
                    end
                end
                
                W_B_WAIT: begin
                    if (m_axi_bvalid && m_axi_bready) begin
                        wr_err  <= (m_axi_bresp != 2'b00); // Set error flag if bresp != OKAY.
                        wr_done <= 1'b1; // Send wr_done = 1 for CPU
                        w_state <= W_IDLE;
                    end
                end
            endcase
        end
    end

    // Signal output channel for Write
    assign m_axi_awaddr = latched_waddr;
    assign m_axi_wdata = latched_wdata;
    assign m_axi_wstrb = latched_wstrb;
    
    // VALID automatic drop to 0 if flag _done has been set 1, avoid Deadlock
    assign m_axi_awvalid = (w_state == W_AW_W_VALID) & ~aw_done;
    assign m_axi_wvalid = (w_state == W_AW_W_VALID) & ~w_done;
    assign m_axi_bready = (w_state == W_B_WAIT);

endmodule




