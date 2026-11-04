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
        forever #5 clk = ~clk; // Chu kỳ 10ns (100MHz)
    end

    // Task giả lập lệnh Ghi của CPU
    task cpu_write(input [31:0] t_addr, input [31:0] t_data);
        begin
            @(posedge clk);
            wr_req = 1; addr = t_addr; wdata = t_data; wstrb = 4'b1111;
            @(posedge clk);
            wr_req = 0; // CPU chỉ nháy req 1 chu kỳ
            wait(wr_done);
            @(posedge clk);
        end
    endtask

    // Task giả lập lệnh Đọc của CPU
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
        // Khởi tạo
        rst_n = 0; rd_req = 0; wr_req = 0;
        addr = 0; wdata = 0; wstrb = 0;
        #20 rst_n = 1; #10;

        $display("=== START AXI4 STANDALONE TEST ===");

        // Test 1: Ghi và Đọc hợp lệ trong vùng 1KB (Địa chỉ 0x10 và 0x14)
        $display("Test 1: Valid write and read in the 1KB region (Addresses 0x10 and 0x14)");
        cpu_write(32'h0000_0010, 32'hAAAA_BBBB);
        cpu_write(32'h0000_0014, 32'h1111_2222);
        
        cpu_read(32'h0000_0010);
        if (rdata === 32'hAAAA_BBBB && !rd_err) $display("[PASS] Read 0x10 correct.");
        else $display("[FAIL] Read 0x10 wrong. Got %h", rdata);

        cpu_read(32'h0000_0014);
        if (rdata === 32'h1111_2222 && !rd_err) $display("[PASS] Read 0x14 correct.");
        else $display("[FAIL] Read 0x14 wrong. Got %h", rdata);

        // Test 2: Error Handling - Ghi ngoài vùng 1KB (0x2000)
        $display("Test 2: Error Handling - Writing outside the 1KB range (0x2000)");
        cpu_write(32'h0000_2000, 32'hDEAD_BEEF);
        if (wr_err) $display("[PASS] Write Error Flag (DECERR) caught correctly.");
        else $display("[FAIL] Missed Write Error Flag!");

        // Test 3: Error Handling - Đọc ngoài vùng 1KB (0x2000)
        $display("Test 3: Error Handling – Read outside the 1KB (0x2000) range");
        cpu_read(32'h0000_2000);
        if (rd_err) $display("[PASS] Read Error Flag (DECERR) caught correctly.");
        else $display("[FAIL] Missed Read Error Flag!");

        // ---------------------------------------------------------
        // Test 4: Ghi một phần (Partial Write / WSTRB)
        // Mô phỏng lệnh SB (Store Byte) và SH (Store Halfword)
        // ---------------------------------------------------------
        $display("--- Test 4: WSTRB Partial Write ---");
        // Bước 1: Ghi full-word (32-bit)
        cpu_write(32'h0000_0020, 32'hFFFF_FFFF);
        
        // Bước 2: Ghi đè 1 Byte thấp nhất (wstrb = 4'b0001)
        @(posedge clk);
        wr_req = 1; addr = 32'h0000_0020; wdata = 32'h0000_00AA; wstrb = 4'b0001;
        @(posedge clk); wr_req = 0; wait(wr_done); @(posedge clk);
        
        // Bước 3: Ghi đè Byte cao nhất (wstrb = 4'b1000)
        @(posedge clk);
        wr_req = 1; addr = 32'h0000_0020; wdata = 32'hBB00_0000; wstrb = 4'b1000;
        @(posedge clk); wr_req = 0; wait(wr_done); @(posedge clk);

        // Đọc lại kiểm tra (Kỳ vọng: BBFF_FFAA)
        cpu_read(32'h0000_0020);
        if (rdata === 32'hBBFF_FFAA) $display("[PASS] WSTRB Masking correct: %h", rdata);
        else $display("[FAIL] WSTRB Masking wrong. Got: %h", rdata);

        // ---------------------------------------------------------
        // Test 5: Back-to-Back (Đọc/Ghi liên tiếp không nghỉ)
        // ---------------------------------------------------------
        $display("--- Test 5: Back-to-Back Transactions ---");
        cpu_write(32'h0000_0024, 32'h1111_1111);
        cpu_write(32'h0000_0028, 32'h2222_2222);
        cpu_write(32'h0000_002C, 32'h3333_3333);
        
        cpu_read(32'h0000_0024);
        if (rdata === 32'h1111_1111) $display("[PASS] B2B Read 1 OK");
        
        cpu_read(32'h0000_0028);
        if (rdata === 32'h2222_2222) $display("[PASS] B2B Read 2 OK");

        // ---------------------------------------------------------
        // Test 6: Read-After-Write (RAW) Cùng một địa chỉ
        // ---------------------------------------------------------
        $display("--- Test 6: Read-After-Write (RAW) ---");
        cpu_write(32'h0000_0030, 32'h9876_5432);
        // Ngay khi wr_done vừa bật, chu kỳ sau task cpu_read sẽ ép rd_req = 1 lập tức
        cpu_read(32'h0000_0030);
        if (rdata === 32'h9876_5432) $display("[PASS] RAW Data Integrity OK");
        else $display("[FAIL] RAW Data wrong. Got: %h", rdata);

        #50 $finish;
    end
endmodule









// ========Version Khác=========
`timescale 1ns/1ps

module tb_axi4_subsystem;
    reg clk = 0;
    reg rst_n = 0;

    always #5 clk = ~clk;

    // --- AXI Bus Signals ---
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

    // =================================================================
    // Khởi tạo Modules
    // =================================================================
    axi4_subsystem dut (
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
        .wr_err(wr_err)
    );

    // =================================================================
    // TASKS (Giống phong cách của dma_top_tb)
    // =================================================================
    
    // Task ghi dữ liệu qua AXI (giống apb_write)
    task automatic axi_write(input [31:0] t_addr, input [31:0] t_data);
        begin
            @(posedge clk);
            // Đợi bridge rảnh trước khi gửi request
            while (bridge_busy) @(posedge clk);
            
            // Phát request ghi
            wr_req = 1;
            addr   = t_addr;
            wdata  = t_data;
            wstrb  = 4'b1111;  // Ghi full 4 bytes
            
            @(posedge clk);
            wr_req = 0;
            
            // Chờ ghi hoàn tất
            while (!wr_done) @(posedge clk);
            @(posedge clk);
        end
    endtask

    // Task đọc dữ liệu qua AXI (giống apb_read)
    task automatic axi_read(input [31:0] t_addr, output [31:0] t_data);
        begin
            @(posedge clk);
            // Đợi bridge rảnh trước khi gửi request
            while (bridge_busy) @(posedge clk);
            
            // Phát request đọc
            rd_req = 1;
            addr   = t_addr;
            
            @(posedge clk);
            rd_req = 0;
            
            // Chờ dữ liệu hợp lệ
            while (!rvalid) @(posedge clk);
            
            // Lấy dữ liệu
            t_data = rdata;
            @(posedge clk);
        end
    endtask

    // Task kiểm tra đọc ghi cơ bản
    task automatic test_write_read(
        input [31:0] test_addr,
        input [31:0] test_data
    );
        reg [31:0] read_data;
        
        $display("[TEST] Writing 0x%h to address 0x%h", test_data, test_addr);
        axi_write(test_addr, test_data);
        
        $display("[TEST] Reading from address 0x%h", test_addr);
        axi_read(test_addr, read_data);
        
        if (read_data === test_data) begin
            $display("[PASS] Data match: Write=0x%h, Read=0x%h", test_data, read_data);
        end else begin
            $display("[ERROR] Data mismatch: Write=0x%h, Read=0x%h", test_data, read_data);
            $fatal;
        end
    endtask

    // Task kiểm tra lỗi ngoài vùng địa chỉ
    task automatic test_out_of_range(
        input [31:0] test_addr,
        input [31:0] test_data
    );
        reg [31:0] read_data;
        reg        error_detected;
        
        $display("[TEST] Testing out-of-range access at address 0x%h", test_addr);
        
        // Test ghi ngoài vùng
        error_detected = 0;
        axi_write(test_addr, test_data);
        
        // Sau khi ghi, kiểm tra cờ lỗi
        @(posedge clk);
        if (wr_err) begin
            $display("[PASS] Write error flag detected correctly");
            error_detected = 1;
        end
        
        if (!error_detected) begin
            $display("[ERROR] Write error flag not detected for out-of-range access");
            $fatal;
        end
        
        // Test đọc ngoài vùng
        error_detected = 0;
        axi_read(test_addr, read_data);
        
        // Sau khi đọc, kiểm tra cờ lỗi
        @(posedge clk);
        if (rd_err) begin
            $display("[PASS] Read error flag detected correctly");
            error_detected = 1;
        end
        
        if (!error_detected) begin
            $display("[ERROR] Read error flag not detected for out-of-range access");
            $fatal;
        end
    endtask

    // =================================================================
    // MAIN INITIAL BLOCK
    // =================================================================
    initial begin
        $display("[TB] Starting AXI4 Subsystem Test");
        $dumpfile("tb_axi4_subsystem.vcd");
        $dumpvars(0, tb_axi4_subsystem);
        
        // Dump các module con (giống dma_top_tb)
        $dumpvars(0, tb_axi4_subsystem.dut);
        
        // Khởi tạo các tín hiệu
        rd_req = 0;
        wr_req = 0;
        addr   = 0;
        wdata  = 0;
        wstrb  = 0;

        // Reset hệ thống
        rst_n = 0;
        #50;
        rst_n = 1;
        #20;

        // =============================================================
        // TEST 1: Ghi và đọc trong vùng địa chỉ hợp lệ
        // =============================================================
        $display("\n=== TEST 1: Valid Address Range (0x0000_0000 - 0x0000_03FF) ===");
        
        // Test 1a: Ghi/đọc tại địa chỉ 0x10
        test_write_read(32'h0000_0010, 32'hAAAA_BBBB);
        
        // Test 1b: Ghi/đọc tại địa chỉ 0x14
        test_write_read(32'h0000_0014, 32'h1111_2222);
        
        // Test 1c: Ghi/đọc tại địa chỉ 0x100
        test_write_read(32'h0000_0100, 32'hDEAD_BEEF);
        
        // Test 1d: Ghi/đọc tại địa chỉ biên (0x3FC)
        test_write_read(32'h0000_03FC, 32'hCAFE_BABE);

        // =============================================================
        // TEST 2: Ghi/đọc ngoài vùng địa chỉ (Error Handling)
        // =============================================================
        $display("\n=== TEST 2: Out-of-Range Access (Error Handling) ===");
        
        // Test 2a: Ghi/đọc tại địa chỉ 0x2000 (ngoài vùng 1KB)
        test_out_of_range(32'h0000_2000, 32'h1234_5678);
        
        // Test 2b: Ghi/đọc tại địa chỉ 0x1000 (ngoài vùng 1KB)
        test_out_of_range(32'h0000_1000, 32'h89AB_CDEF);

        // =============================================================
        // TEST 3: Stress Test - Ghi đọc nhiều lần
        // =============================================================
        $display("\n=== TEST 3: Stress Test (Multiple Access) ===");
        
        for (int i = 0; i < 10; i++) begin
            automatic [31:0] test_addr = 32'h0000_0000 + (i * 4);
            automatic [31:0] test_data = 32'hA000_0000 + i;
            test_write_read(test_addr, test_data);
        end

        // =============================================================
        // Kết thúc test
        // =============================================================
        #1000;
        $display("\n==========================================");
        $display("[ALL PASS] All test cases passed successfully!");
        $display("==========================================");
        $finish;
    end
endmodule


