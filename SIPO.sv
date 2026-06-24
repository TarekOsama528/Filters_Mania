module SIPO #(parameter DATA_WIDTH = 8)
(
    input wire clk,
    input wire rst_n,
    input wire serial_in,
    output reg [DATA_WIDTH-1:0] parallel_out,
    output reg valid
);

    reg [DATA_WIDTH-1:0] shift_reg;
    reg [$clog2(DATA_WIDTH):0] bit_count;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            shift_reg <= 0;
            parallel_out <= 0;
            bit_count <= 0;
            valid <= 0;
        end else begin
            if (bit_count < DATA_WIDTH) begin
                bit_count <= bit_count + 1;
                shift_reg <= {shift_reg[DATA_WIDTH-2:0], serial_in};
                valid <= 0; // Not valid until all bits are received
            end else begin
                bit_count <= 0;
                valid <= 1; // Set valid when all bits are received
                parallel_out <= shift_reg; // Output the parallel data
            end
        end
    end
endmodule