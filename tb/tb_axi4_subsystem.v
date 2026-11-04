`timescale 1ns / 1ps

module tb_axi4_subsystem;
    reg         clk;
    reg         rst_n;
    reg         rd_req;
    reg         wr_req;
    reg  [31:0] addr;
    reg  [31:0] wdata;
    reg  [3:0]  wstrb;
    
    wire        bridge_busy;
    wire        rvalid;
    wire [31:0] rdata;
    wire        rd_err;
    wire        wr_done;
    wire        wr_err;

    axi4lite_subsystem dut (
        .clk(clk), .rst_n(rst_n),
        .rd_req(rd_req), .wr_req(wr_req),
        .addr(addr), .wdata(wdata), .wstrb(wstrb),
        .bridge_busy(bridge_busy), .rvalid(rvalid), .rdata(rdata),
        .rd_err(rd_err), .wr_done(wr_done), .wr_err(wr_err)
    );

    initial begin
        clk = 0;
        forever #5 clk = ~clk; 
    end

    // Task to simulate a CPU write instruction
    task cpu_write(input [31:0] t_addr, input [31:0] t_data);
        begin
            @(posedge clk);
            wr_req = 1; addr = t_addr; wdata = t_data; wstrb = 4'b1111;
            @(posedge clk);
            wr_req = 0; // CPU asserts req for only one cycle
            wait(wr_done);
            @(posedge clk);
        end
    endtask

    // Task to simulate a CPU read instruction
    task cpu_read(input [31:0] t_addr);
        begin
            @(posedge clk);
            rd_req = 1; addr = t_addr;
            @(posedge clk);
            rd_req = 0;
            wait(rvalid);
            @(posedge clk);
        end
    endtask

    initial begin
        rst_n = 0; rd_req = 0; wr_req = 0;
        addr = 0; wdata = 0; wstrb = 0;
        #20 rst_n = 1; #10;

        $display("=== START AXI4 STANDALONE TEST ===");

        // Test 1: Valid write and read within the 1KB region (Addresses 0x10 and 0x14)
        $display("Test 1: Valid write and read in the 1KB region (Addresses 0x10 and 0x14)");
        cpu_write(32'h0000_0010, 32'hAAAA_BBBB);
        cpu_write(32'h0000_0014, 32'h1111_2222);
        
        cpu_read(32'h0000_0010);
        if (rdata === 32'hAAAA_BBBB && !rd_err) $display("[PASS] Read 0x10 correct.");
        else $display("[FAIL] Read 0x10 wrong. Got %h", rdata);

        cpu_read(32'h0000_0014);
        if (rdata === 32'h1111_2222 && !rd_err) $display("[PASS] Read 0x14 correct.");
        else $display("[FAIL] Read 0x14 wrong. Got %h", rdata);

        // Test 2: Error Handling - Write outside the 1KB region (0x2000)
        $display("Test 2: Error Handling - Writing outside the 1KB range (0x2000)");
        cpu_write(32'h0000_2000, 32'hDEAD_BEEF);
        if (wr_err) $display("[PASS] Write Error Flag (DECERR) caught correctly.");
        else $display("[FAIL] Missed Write Error Flag!");

        // Test 3: Error Handling - Read outside the 1KB region (0x2000)
        $display("Test 3: Error Handling – Read outside the 1KB (0x2000) range");
        cpu_read(32'h0000_2000);
        if (rd_err) $display("[PASS] Read Error Flag (DECERR) caught correctly.");
        else $display("[FAIL] Missed Read Error Flag!");

        // Test 4: Partial Write (WSTRB)
        // Simulate SB (Store Byte) and SH (Store Halfword) instructions
        $display("Test 4: WSTRB Partial Write");
        // Write a full word (32-bit)
        cpu_write(32'h0000_0020, 32'hFFFF_FFFF);
        
        // Overwrite the lowest byte (wstrb = 4'b0001)
        @(posedge clk);
        wr_req = 1; addr = 32'h0000_0020; wdata = 32'h0000_00AA; wstrb = 4'b0001;
        @(posedge clk); wr_req = 0; wait(wr_done); @(posedge clk);
        
        // Overwrite the highest byte (wstrb = 4'b1000)
        @(posedge clk);
        wr_req = 1; addr = 32'h0000_0020; wdata = 32'hBB00_0000; wstrb = 4'b1000;
        @(posedge clk); wr_req = 0; wait(wr_done); @(posedge clk);

        // Read back to verify (Expected: BBFF_FFAA)
        cpu_read(32'h0000_0020);
        if (rdata === 32'hBBFF_FFAA) $display("[PASS] WSTRB Masking correct: %h", rdata);
        else $display("[FAIL] WSTRB Masking wrong. Got: %h", rdata);

        // Test 5: Back-to-Back Transactions (Consecutive reads/writes without idle cycles)
        $display("Test 5: Back-to-Back Transactions");
        cpu_write(32'h0000_0024, 32'h1111_1111);
        cpu_write(32'h0000_0028, 32'h2222_2222);
        cpu_write(32'h0000_002C, 32'h3333_3333);
        
        cpu_read(32'h0000_0024);
        if (rdata === 32'h1111_1111) $display("[PASS] B2B Read 1 OK");
        
        cpu_read(32'h0000_0028);
        if (rdata === 32'h2222_2222) $display("[PASS] B2B Read 2 OK");

        // Test 6: Read-After-Write (RAW) at the same address
        $display("Test 6: Read-After-Write (RAW)");
        cpu_write(32'h0000_0030, 32'h9876_5432);
        // As soon as wr_done is asserted, cpu_read asserts rd_req in the next cycle
        cpu_read(32'h0000_0030);
        if (rdata === 32'h9876_5432) $display("[PASS] RAW Data Integrity OK");
        else $display("[FAIL] RAW Data wrong. Got: %h", rdata);

        #50 $finish;
    end
endmodule

