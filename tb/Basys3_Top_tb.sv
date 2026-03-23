`timescale 1ns / 1ps

module Basys3_Top_tb();

    // 1. Local signals
    logic clk;
    logic btnC;
    logic [15:0] sw;
    logic uart_rx;
    wire [15:0] led;
    wire uart_tx;

    // 2. Instantiate the Unit Under Test (UUT)
    Basys3_Top uut (
        .CLK(clk),
        .BTN_C(btnC),
        .SW(sw),
        .LED(led),
        .UART_RXD(uart_rx),
        .UART_TXD(uart_tx),
        .SEG(),
        .DP(),
        .AN()
    );

    // 3. Clock generation (100MHz = 10ns period)
    always #5 clk = ~clk;

    // 4. UART Stimulus Task: Sends 16-channel stimulus packet (0xAA header + 32 bytes)
    task send_byte(input [7:0] data);
        integer j;
        begin
            // Start bit
            uart_rx = 0;
            #8680; // 115200 baud is approx 8680ns per bit
            // 8 Data bits (LSB first)
            for (j=0; j<8; j=j+1) begin
                uart_rx = data[j];
                #8680;
            end
            // Stop bit
            uart_rx = 1;
            #8680;
        end
    endtask

    // 5. Main Simulation Story
    initial begin
        // Init
        clk = 0;
        btnC = 1;
        sw = 0;
        uart_rx = 1; // Idle high

        #100 btnC = 0; // Release Reset
        #500;

        // --- TEST CASE 0: Program reward scalar = 1.5 (Q8.8 = 0x0180) ---
        send_byte(8'hDD);
        send_byte(8'h01);
        send_byte(8'h80);

        // --- TEST CASE 0B: Runtime threshold write burst (addr 0, count 2) ---
        // write threshold[0]=0x0030, threshold[1]=0x0040
        send_byte(8'hDE);
        send_byte(8'h00); // start_addr
        send_byte(8'h02); // count words
        send_byte(8'h00);
        send_byte(8'h30);
        send_byte(8'h00);
        send_byte(8'h40);

        // --- TEST CASE 0C: Runtime threshold readback (0xEE + addr) ---
        // Expected TX sequence: status (0xA6), data_hi, data_lo.
        send_byte(8'hEE);
        send_byte(8'h00);

        // --- TEST CASE 1: Send a high-alpha stimulus packet (16 channels) ---
        // Header 0xAA
        send_byte(8'hAA);
        
        // Stimuli: 32 bytes (16 neurons, 2 bytes Q8.8 each)
        // Let's send 0x0180 (1.5 in Q8.8) to neuron 0 to force a spike
        send_byte(8'h01); // N0 MSB
        send_byte(8'h80); // N0 LSB
        
        // Fill remaining 30 bytes with 0x0000
        repeat (30) send_byte(8'h00);

        #1000000; // Wait for the neuron to integrate and the UART to finish
        $display("Simulation complete. Check the ‘led’ and neuron potentials in the wave window.");
        $finish;
    end

endmodule
