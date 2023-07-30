module sdramController(
        input clk,                              // 50MHz clock                      | from uP
        input RESETn,                           // Reset            | Active low    | from uP
        input ready,                            // Ready            | Active high   | from uP
        input ADSn,                             // Address strobe   | Active low    | from uP
        input M_IOn,                            // memory/IO        | IO Active low | from uP
        input W_Rn,                             // Write/Read       | R Active low  | from uP
        input [29:00] ADD,                      // 30 bit address                   | from uP
        input [03:00] BE,                       // Byte Enable signal               | from uP

        inout [31:00] data,                     // 32bit data to read/write         | from/to uP
        inout [07:00] sdram_DQ,                 // 1byte bidirectional data         | from/to SDRAM

        output reg sdram_CLK,                   // 100Mhz clock output              | to SDRAM
        output reg sdram_CLKE,                  // Clock enable                     | to SDRAM
        output reg sdram_DQM,                   // mux to select bank               | to SDRAM
        output reg sdram_CSn,                   // Chip select; active low          | to SDRAM
        output reg [02:00] sdram_CMD,           // includes WEn, RASn, CASn         | to SDRAM
        output reg [11:00] sdram_MUXADD,        // Multiplexed address              | to SDRAM
        output reg [01:00] sdram_BA             // Bank address                     | to SDRAM
    );

    // Include files
    `include "auxillary.sv"

    // States in the finite state machine
    parameter state_INIT    = 3'd0;             // Initial state
    parameter state_IDLE    = 3'd1;             // Idle state
    parameter state_REFRESH = 3'd2;             // Auto refresh state
    parameter state_READ    = 3'd3;             // Read state
    parameter state_WRITE   = 3'd4;             // Write state

    // States in the INIT state
    parameter stateInitReset        = 4'd0;
    parameter stateInitWait100us    = 4'd1;
    parameter stateInitPrecharge    = 4'd2;
    parameter stateInitWaitTrp      = 4'd3;
    parameter stateInitAutoRefresh1 = 4'd4;
    parameter stateInitAutoRefresh2 = 4'd5;
    parameter stateInitLMR          = 4'd6;
    parameter stateInitTmrd         = 4'd7;

    /*
        1MHz clock
            => T = 1/1MHz = 10ns
    */
    parameter wait100us = 3'd100;               // 100us/10ns = 10000 cycles
    parameter waitTrfc  = 3'd7;                 // 70ns/10ns  = 7 cycles
    parameter waitTrp   = 3'd2;                 // 20ns/10ns  = 2 cycles
    parameter waitTmrd  = 3'd2;                 // 20ns/10ns  = 2 cycles


    // SDRAM commands
    parameter cmd_NOP       = 3'b111;           // WEn = H, RASn = H, CASn = H
    parameter cmd_PRECHARGE = 3'b001;           // WEn = L, RASn = L, CASn = H
    parameter cmd_LMR       = 3'b000;           // WEn = L, RASn = L, CASn = L

    reg [02:00] state;                          // Variable to hold state value
    reg [04:00] initState;                      // Variable to hold internal state value in the INIT state
    reg lock, timeout;                          // Variables for lock, timeout signal

    always_ff @ (posedge clk)
    begin

        if (!RESETn)
        begin
            state = state_INIT;                                     // Set INIT state on reset
            lock  = 1'b1;                                           // Generate lock signal
        end
        else
        begin
            lock = 1'b0;                                            // Clear lock signal
        end

        case (state)                                                // Finite State Machine
            state_INIT:                                             // On state INIT
            begin

                // State machine internal to the INIT state and before the IDLE state
                initState = stateInitReset;

                case (initState)
                    stateInitReset:
                    begin
                        if (lock) initState <= stateInitWait100us;
                        else
                        begin
                            sdram_CLKE  <= 1'd0;                    // Set clock enable low
                            sdram_CMD   <= cmd_NOP;                 // Set NOP command
                        end
                    end

                    stateInitWait100us:
                    begin
                        delayNanoseconds(clk, wait100us, timeout);  // Call a function to cause a 100us delay
                        if (timeout)
                        begin
                            initState   <= stateInitPrecharge;      // Assign next state
                            sdram_CLKE  <= 1'd1;                    // Set clock enable high
                            sdram_CMD   <= cmd_NOP;                 // Set NOP command
                        end
                    end

                    stateInitPrecharge:
                    begin
                        initState        <= stateInitWaitTrp;       // Assign next state
                        sdram_CLKE       <= 1'b1;                   // Set clock enable high
                        sdram_CMD        <= cmd_PRECHARGE;          // Set Precharge command
                        sdram_MUXADD[10] <= 1'b1;                   // Set A10 high to precharge all rows and columns
                    end

                    stateInitWaitTrp:
                    begin
                        sdram_CMD = cmd_NOP;                                    // Set NOP command while waiting
                        delayNanoseconds(clk, waitTrp, timeout);                // Call a function ot cause a 6ns delay
                        if (timeout)    initState <= stateInitAutoRefresh1;     // Assign next state
                    end

                    stateInitAutoRefresh1:
                    begin
                        delayNanoseconds(clk, waitTrfc, timeout);               // call a function to cause a 16us delay
                        sdram_CMD <= cmd_NOP;                                   // Set NOP command while waiting
                        if (timeout)    initState <= stateInitAutoRefresh2;     // Assign next state
                    end

                    stateInitAutoRefresh2:
                    begin
                        delayNanoseconds(clk, waitTrfc, timeout);               // call a function to cause a 16us delay
                        sdram_CMD <= cmd_NOP;                                   // Set NOP command while waiting
                        if (timeout)    initState <= stateInitLMR;              // Assign next state
                    end

                    stateInitLMR:
                    begin
                        sdram_CMD = cmd_LMR;                                    // Set LMR command
                        delayNanoseconds(clk, waitTmrd, timeout);               // Wait for the commmand to be executed
                        if (timeout) state <= state_IDLE;                       // Exit the state machine and set IDLE state on completion
                    end
                endcase
            end
        endcase
    end
endmodule
