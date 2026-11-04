module Program_Counter (
    input wire         clk,
    input wire         rst_n,
    input wire         en,
    input wire  [31:0] PC_in,
    output reg  [31:0] PC_out
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            PC_out <= 32'b0;
        end else if (en) begin
            PC_out <= PC_in;
        end
    end

endmodule


