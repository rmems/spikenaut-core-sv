/*
 * SHIP OF THESEUS - RUNTIME NEURON PARAMETER RAM
 *
 * Stores live threshold values used by LifNeuron instances.
 * Read side is combinational for all neurons; write side is synchronous
 * so UART updates can patch thresholds without reprogramming FPGA.
 */

module NeuronParamRam #(
    parameter integer DEPTH = 16,
    parameter logic [15:0] DEFAULT_THRESHOLD = 16'h004B
) (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        we,
    input  logic [7:0]  waddr,
    input  logic [15:0] wdata,
    output logic [15:0] threshold_q [0:DEPTH-1]
);

    logic [15:0] mem [0:DEPTH-1];

    initial begin
        for (int i = 0; i < DEPTH; i++) begin
            mem[i] = DEFAULT_THRESHOLD;
        end
        // $readmemh is ignored in synthesis if file not found; defaults above apply.
        $readmemh("parameters.mem", mem);
    end

    // No async reset — learned thresholds survive soft reset.
    always_ff @(posedge clk) begin
        if (we && (waddr < DEPTH)) begin
            mem[waddr] <= wdata;
        end
    end

    always_comb begin
        for (int i = 0; i < DEPTH; i++) begin
            threshold_q[i] = mem[i];
        end
    end

endmodule
