module hazard_detect(
    input Is_Load_E,
    input [4:0] addrD_E,
    input [4:0] addrA_D, addrB_D,
    input UsesRs1_D, UsesRs2_D,
    input bridge_busy,          // updated from AXI Bridge
    output stall_load,
    output stall_axi           // Issue a command to lock the pipeline
);
    assign stall_load = Is_Load_E && (addrD_E != 5'b0) &&
                        ((UsesRs1_D && (addrD_E == addrA_D)) ||
                         (UsesRs2_D && (addrD_E == addrB_D))) && !bridge_busy;
                         
    assign stall_axi = bridge_busy;
endmodule

