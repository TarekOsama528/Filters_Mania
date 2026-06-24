module PISO #(parameter N=8) (
    input logic clk,
    input logic rst_n,
    input logic [N-1:0] parallel_in,
    output logic serial_out,
    output logic done
);
    // Internal signals
    logic [N-1:0] shift_reg;
    logic [($clog2(N)-1):0] bit_count;

    // Shift register logic
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            shift_reg <= {N{1'b0}};
            bit_count <= {($clog2(N)){1'b0}};
            serial_out <= 1'b0;
            done <= 1'b0;
        end else begin
            if (bit_count < N) begin
                shift_reg <= {shift_reg[N-2:0], parallel_in[bit_count]};
                serial_out <= shift_reg[N-1];
                bit_count <= bit_count + 1;
                done <= 1'b0; // Indicate that shifting is in progress
            end else begin
                bit_count <= {($clog2(N)){1'b0}}; // Reset bit count after sending all bits
                done <= 1'b1; // Indicate that shifting is complete
            end
        end
    end
endmodule