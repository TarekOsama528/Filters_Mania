module adder_tree #(
    parameter FRACTIONAL_PART = 16,
    parameter INTEGER_PART    = 16,
    parameter COUNT           = 768   // any positive integer
)(
    input  wire signed [FRACTIONAL_PART+INTEGER_PART-1:0] a [COUNT],
    output logic signed [FRACTIONAL_PART+INTEGER_PART-1:0] sum
);

    localparam WIDTH = FRACTIONAL_PART + INTEGER_PART;
    localparam logic signed [WIDTH-1:0] MAX_VAL = {1'b0, {(WIDTH-1){1'b1}}};
    localparam logic signed [WIDTH-1:0] MIN_VAL = {1'b1, {(WIDTH-1){1'b0}}};
    localparam STAGES = $clog2(COUNT);

    // Temporary array to store intermediate sums
    logic signed [WIDTH+STAGES:0] stage [0:COUNT-1];
    integer i, n, next_n;

    always_comb begin
        // Initialize
        for (i = 0; i < COUNT; i++)
            stage[i] = a[i];

        // Iteratively reduce until one sum remains
        n = COUNT;
        while (n > 1) begin
            next_n = (n + 1) >> 1; // ceil(n/2)
            for (i = 0; i < next_n; i++) begin
                if (2*i + 1 < n)
                    stage[i] = stage[2*i] + stage[2*i + 1];
                else
                    stage[i] = stage[2*i]; // carry forward leftover
            end
            n = next_n;
        end

        if (stage[0] > MAX_VAL)
            sum = MAX_VAL;
        else if (stage[0] < MIN_VAL)
            sum = MIN_VAL;
        else
            sum = stage[0];
    end

endmodule
