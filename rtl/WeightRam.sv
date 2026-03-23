/*
 * SHIP OF THESEUS - SYNAPTIC WEIGHT RAM
 *
 * Stores live Q8.8 synaptic weights for STDP learning.
 * Read side is combinational (all weights exposed simultaneously).
 * Write side is synchronous — accepts writes from STDP controllers
 * or from UART 0xDE burst commands (addr 16–31 mapped to entries 0–15).
 *
 * Structure mirrors NeuronParamRam exactly.
 */

module WeightRam #(
    parameter integer DEPTH = 16,
    parameter logic [15:0] DEFAULT_WEIGHT = 16'h0100  // 1.0 in Q8.8
) (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        we,
    input  logic [7:0]  waddr,
    input  logic [15:0] wdata,
    output logic [15:0] weight_q [0:DEPTH-1]
);

    logic [15:0] mem [0:DEPTH-1];

    initial begin
        for (int i = 0; i < DEPTH; i++) begin
            mem[i] = DEFAULT_WEIGHT;
        end
        // $readmemh is ignored in synthesis if file not found; defaults above apply.
        $readmemh("parameters_weights.mem", mem);
    end

    // No async reset — learned weights survive soft reset.
    always_ff @(posedge clk) begin
        if (we && (waddr < DEPTH)) begin
            mem[waddr] <= wdata;
        end
    end

    always_comb begin
        for (int i = 0; i < DEPTH; i++) begin
            weight_q[i] = mem[i];
        end
    end

endmodule
