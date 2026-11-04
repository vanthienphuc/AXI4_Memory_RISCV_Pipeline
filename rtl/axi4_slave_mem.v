module axi4_slave_mem (
    input wire        clk,
    input wire        rst_n,

    // AXI4-Lite Slave Interface
    // AW Channel
    input wire [31:0] s_axi_awaddr,
    input wire        s_axi_awvalid,
    output wire       s_axi_awready,
    
    // W Channel
    input wire [31:0] s_axi_wdata,
    input wire [3:0]  s_axi_wstrb,
    input wire        s_axi_wvalid,
    output wire       s_axi_wready,
    
    // B Channel
    output wire [1:0] s_axi_bresp,
    output wire       s_axi_bvalid,
    input wire        s_axi_bready,
    
    // AR Channel
    input wire [31:0] s_axi_araddr,
    input wire        s_axi_arvalid,
    output wire       s_axi_arready,
    
    // R Channel
    output wire [31:0] s_axi_rdata,
    output wire [1:0]  s_axi_rresp,
    output wire        s_axi_rvalid,
    input wire         s_axi_rready
);

// SRAM 1KB = 256 words x 32-bit
    reg [31:0] sram [0:255];
    
    // States
    localparam S_W_IDLE = 1'b0, S_W_RESP = 1'b1;
    localparam S_R_IDLE = 1'b0, S_R_DATA = 1'b1;

    reg w_state;
    reg r_state;

    // Internal registers for Write
    reg aw_latched;
    reg w_latched;
    reg [31:0] latched_awaddr;
    reg [31:0] latched_wdata;
    reg [3:0]  latched_wstrb;
    reg [1:0]  bresp_reg;

    // Internal registers for Read
    reg [31:0] rdata_reg;
    reg [1:0]  rresp_reg;

    // =========================================================
    // WRITE FSM
    // =========================================================
    wire aw_fire = s_axi_awvalid && s_axi_awready;
    wire w_fire = s_axi_wvalid && s_axi_wready;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            w_state <= S_W_IDLE;
            aw_latched <= 1'b0;
            w_latched <= 1'b0;
            bresp_reg <= 2'b00;
            
            latched_awaddr <= 32'd0;
            latched_wdata <= 32'd0;
            latched_wstrb <= 4'd0;
        end else begin
            case (w_state)
                S_W_IDLE: begin
                    // Independent handshake each channel
                    if (aw_fire) begin
                        aw_latched <= 1'b1;
                        latched_awaddr <= s_axi_awaddr;
                    end
                    if (w_fire) begin
                        w_latched <= 1'b1;
                        latched_wdata <= s_axi_wdata;
                        latched_wstrb <= s_axi_wstrb;
                    end

                    // Check completed AW&W channels
                    if ((aw_latched || aw_fire) && (w_latched || w_fire)) begin
                        w_state <= S_W_RESP;

                        // Address Decoder: Check if the address falls within the 1KB range (0x000 - 0x3FF)
                        // Retrieve the latched address (if previously latched) or the current address on the bus
                        if ((aw_latched ? latched_awaddr : s_axi_awaddr) <= 32'h0000_0400) begin
                            bresp_reg <= 2'b00; // OKAY
                        end else begin
                            bresp_reg <= 2'b11; // DECERR 
                        end
                    end
                end

                S_W_RESP: begin
                    if (s_axi_bvalid && s_axi_bready) begin
                        w_state <= S_W_IDLE;
                        aw_latched <= 1'b0;
                        w_latched <= 1'b0;
                    end
                end
            endcase
        end
    end

    // Write to physical SRAM
    wire mem_we = (w_state == S_W_IDLE) && (aw_latched || aw_fire) && (w_latched || w_fire);
    wire [31:0] write_addr = aw_latched ? latched_awaddr : s_axi_awaddr;
    wire [31:0] write_data = w_latched ? latched_wdata : s_axi_wdata;
    wire [3:0] write_strb = w_latched ? latched_wstrb : s_axi_wstrb;
    wire addr_is_valid = (write_addr < 32'h0000_0400);

    always @(posedge clk) begin
        if (mem_we && addr_is_valid) begin
            // Handle byte masked writes (wstrb)
            if (write_strb[0]) sram[write_addr[9:2]][7:0] <= write_data[7:0];
            if (write_strb[1]) sram[write_addr[9:2]][15:8] <= write_data[15:8];
            if (write_strb[2]) sram[write_addr[9:2]][23:16] <= write_data[23:16];
            if (write_strb[3]) sram[write_addr[9:2]][31:24] <= write_data[31:24];
        end
    end

    assign s_axi_awready = (w_state == S_W_IDLE) && !aw_latched;
    assign s_axi_wready = (w_state == S_W_IDLE) && !w_latched;
    assign s_axi_bvalid = (w_state == S_W_RESP);
    assign s_axi_bresp = bresp_reg;

    // =========================================================
    // READ FSM
    // =========================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_state <= S_R_IDLE;
            rdata_reg <= 32'd0;
            rresp_reg <= 2'b00;
        end else begin
            case (r_state)
                S_R_IDLE: begin
                    if (s_axi_arvalid && s_axi_arready) begin
                        r_state <= S_R_DATA;

                        // Address Decoder & Đọc SRAM
                        if (s_axi_araddr < 32'h0000_0400) begin
                            rdata_reg <= sram[s_axi_araddr[9:2]];
                            rresp_reg <= 2'b00; // OKAY
                        end else begin
                            rdata_reg <= 32'd0;
                            rresp_reg <= 2'b11; // DECERR
                        end
                    end
                end

                S_R_DATA: begin
                    if (s_axi_rvalid && s_axi_rready) begin
                        r_state <= S_R_IDLE;
                    end
                end
            endcase
        end
    end

    assign s_axi_arready = (r_state == S_R_IDLE);
    assign s_axi_rvalid = (r_state == S_R_DATA);
    assign s_axi_rdata = rdata_reg;
    assign s_axi_rresp = rresp_reg;
endmodule



                





