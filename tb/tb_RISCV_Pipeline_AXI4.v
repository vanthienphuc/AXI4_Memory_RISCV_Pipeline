`timescale 1ns / 1ps
module tb_RISCV_Pipeline_AXI4;
    reg clk;
    reg rst_n;

    // Specialized counters for performance analysis
    integer total_cycles;
    integer load_use_hazard_cycles; // Stall do Load-Use Hazard
    
    integer axi_write_trans; // Count the number of Store executions via AXI
    integer axi_read_trans; // Count the number of Load executions via AXI
    integer axi_write_stall_cycles; // Pipeline cycle stalled due to AXI Write
    integer axi_read_stall_cycles; // Pipeline cycle stalled due to AXI read

    integer actual_x7;

    RISCV_Pipeline_AXI4 dut (
        .clk(clk),
        .rst_n(rst_n)
    );

always #5 clk = ~clk;

    initial begin
        $dumpfile("wave.vcd");
        $dumpvars(0, tb_RISCV_Pipeline_AXI4);
        
        $readmemh("./mem/imem.hex", dut.IMEM_inst.memory);
        $readmemh("./mem/dmem_init.hex", dut.u_axi_subsystem.u_slave.sram);
        
        clk = 0;
        rst_n = 0;
        total_cycles = 0;
        load_use_hazard_cycles = 0;
        axi_write_trans = 0;
        axi_read_trans = 0;
        axi_write_stall_cycles = 0;
        axi_read_stall_cycles = 0;
        
        #20;
        rst_n = 1;
    end

    always @(posedge clk) begin
        if (rst_n) begin
            total_cycles = total_cycles + 1;

            // Count hazard load-use
            if (dut.stall_load == 1'b1) begin
                load_use_hazard_cycles = load_use_hazard_cycles + 1;
            end

            // Count completed AXI transactions
            if (dut.wr_done_axi == 1'b1) begin
                axi_write_trans = axi_write_trans + 1;
            end
            if (dut.rvalid_axi == 1'b1) begin
                axi_read_trans = axi_read_trans + 1;
            end

            if (dut.stall_axi == 1'b1) begin
                if (dut.MemRW_M == 1'b1) begin
                    axi_write_stall_cycles = axi_write_stall_cycles + 1;
                end else if (dut.Is_Load_M == 1'b1) begin
                    axi_read_stall_cycles = axi_read_stall_cycles + 1;
                end
            end
        end

        actual_x7 = dut.Reg_inst.registers[7];

        if (actual_x7 == 32'd1) begin
            $display("==========================================================");
            $display("[ PASSED] PIPELINE & AXI4 TEST COMPLETED SUCCESSFULLY");
            $display("----------------------------------------------------------");
            $display(" PERFORMANCE STATISTICS:");
            $display(" - Total Execution Cycles        : %0d", total_cycles);
            $display(" - Pipeline Load-Use Stall Cycles: %0d", load_use_hazard_cycles);
            $display("----------------------------------------------------------");
            $display(" AXI4 TRANSACTION PROFILING:");
            $display(" - Total AXI Write (Store) Trans : %0d", axi_write_trans);
            $display(" - Total AXI Write Wait Cycles   : %0d", axi_write_stall_cycles);
            $display(" - Total AXI Read (Load) Trans   : %0d", axi_read_trans);
            $display(" - Total AXI Read Wait Cycles    : %0d", axi_read_stall_cycles);
            $display(" - Total AXI Overhead (Wait-State): %0d cycles", (axi_write_stall_cycles + axi_read_stall_cycles));
            $display("==========================================================");
            $finish;
        end
        else if (actual_x7 == 32'hFFFF_FFFF) begin
            $display("==========================================================");
            $display("[ FAILED] LOGIC OR TIMING ERROR DETECTED");
            $display(" CPU branched to the 'fail' path in test.S");
            $display(" Total Cycles Before Failure: %0d", total_cycles);
            $display("==========================================================");
            $finish;
        end
        
        if (total_cycles > 5000) begin
            $display("[ TIMEOUT] Simulation stalled at %0d cycles!", total_cycles);
            $finish;
        end
    end
endmodule


