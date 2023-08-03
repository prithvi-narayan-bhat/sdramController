module sdramController(
        input clk,                              // 50MHz clock                      | from uP
        input RESETn,                           // Reset            | Active low    | from uP
        input ADSn,                             // Address strobe   | Active low    | from uP
        input M_IOn,                            // memory/IO        | IO Active low | from uP
        input W_Rn,                             // Write/Read       | R Active low  | from uP
        input CSn,                              // Chip Select      | Active low    | from uP
        input [29:00] ADD,                      // 30 bit address                   | from uP
        input [03:00] BE,                       // Byte Enable signal               | from uP

        inout wire [31:00] data,                // 32bit data to read/write         | from/to uP
        inout wire [07:00] sdram_DQ,            // 1byte bidirectional data         | from/to SDRAM

        output reg ready,                       // Ready            | Active high   | to uP
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
    // Reset States
    parameter stateReset                = 6'd00;
    parameter stateResetWaitLock        = 6'd01;
    // Init State
    parameter stateInitWait100us        = 6'd02;
    parameter stateInitPrecharge        = 6'd03;
    parameter stateInitStartTrp         = 6'd04;
    parameter stateInitRefresh1         = 6'd05;
    parameter stateInitStartTrfc1       = 6'd06;
    parameter stateInitRefresh2         = 6'd07;
    parameter stateInitStartTrfc2       = 6'd08;
    parameter stateInitLMR              = 6'd09;
    parameter stateInitStartTmrd        = 6'd10;
    // Idle State
    parameter stateIdle                 = 6'd11;
    parameter stateIdleStartTrr         = 6'd12;
    // Auto refresh State
    parameter stateAutoRefresh          = 6'd13;
    parameter stateAutoRefreshPrecharge = 6'd14;
    parameter stateAutoRefreshStartTrp  = 6'd15;
    parameter stateAutoRefreshRefresh   = 6'd16;
    parameter stateAutoRefreshStartTrfc = 6'd17;
    // Write States
    parameter stateWrite                = 6'd18;
    parameter stateWriteActive          = 6'd19;
    parameter stateWriteNop1            = 6'd20;
    parameter stateWrite1               = 6'd21;
    parameter stateWrite2               = 6'd22;
    parameter stateWrite3               = 6'd23;
    parameter stateWrite4               = 6'd24;
    parameter stateWriteNop2            = 6'd25;
    parameter stateWritePrecharge       = 6'd26;
    parameter stateWriteStartTrp        = 6'd27;
    parameter stateWriteNop3            = 6'd28;
    // Read States
    parameter stateRead                 = 6'd29;
    parameter stateReadActive           = 6'd30;
    parameter stateReadNop1             = 6'd31;
    parameter stateReadCmd              = 6'd32;
    parameter stateReadNop2             = 6'd33;
    parameter stateReadNop3             = 6'd34;
    parameter stateRead1                = 6'd35;
    parameter stateRead2                = 6'd36;
    parameter stateRead3                = 6'd37;
    parameter stateRead4                = 6'd38;
    parameter stateReadNop4             = 6'd39;
    parameter stateReadPrecharge        = 6'd40;
    parameter stateReadStartTrp         = 6'd41;
    parameter stateReadNop5             = 6'd42;

    /*
        1MHz clock
            => T = 1/1MHz = 10ns
    */
    parameter wait100us = 5'd10000;             // 100us/10ns = 10000 cycles
    parameter waitTrfc  = 5'd7;                 // 70ns/10ns  = 7 cycles
    parameter waitTrp   = 5'd2;                 // 20ns/10ns  = 2 cycles
    parameter waitTmrd  = 5'd2;                 // 20ns/10ns  = 2 cycles
    parameter waitTrr   = 5'd1563;              // 15.625us/10ns = 1563 cycles
    parameter waitTrcd  = 5'd2;                 // 20ns/10ns  = 2 cycles


    // SDRAM commands
    parameter cmd_NOP       = 3'b111;           // WEn = H, RASn = H, CASn = H
    parameter cmd_PRECHARGE = 3'b001;           // WEn = L, RASn = L, CASn = H
    parameter cmd_LMR       = 3'b000;           // WEn = L, RASn = L, CASn = L
    parameter cmd_AREFRESH  = 3'b100;           // WEn = H, RASn = L, CASn = L
    parameter cmd_ACTIVE    = 3'b101;           // WEn = H, RASn = L, CASn = H
    parameter cmd_WRITE     = 3'b010;           // WEn = L, RASn = H, CASn = L
    parameter cmd_READ      = 3'b110;           // WEn = H, RASn = H, CASn = L

    reg [05:00] state;                          // Variable to hold state value
    reg lock, timeout, refresh_request;         // Variables for lock, timeout signal and refresh request signal
    reg [07:00] temp_DQ;                        // Temporary register to hold DQ value
    reg [31:00] temp_data;                      // Temporary register to hold data

    assign sdram_DQ = temp_DQ;
    assign data = temp_data;
    assign sdram_CSn = CSn;                     // Assign as is

    always_ff @ (posedge clk)
    begin
        if (!RESETn)
        begin
            state = stateReset;                                 // Set Reset state on reset
            ready <= 1'b0;                                      // Clear ready
        end

        else            lock = 1'b0;                            // Clear lock signal

        /*=============================================================================================================*
         *                                               INIT STATE                                                    *
         *=============================================================================================================*/
        case (state)                                            // Finite State Machine
            stateReset:
            begin
                state <= stateResetWaitLock;                    // Move to next state on reset
            end

            stateResetWaitLock:                                 // On state INIT
            begin
                lock = 1'b1;                                    // Generate lock signal
                refresh_request <= 1'b1;                        // Set refresh resquest on reset

                if (lock)   state <= stateInitWait100us;        // Move to next state on lock signal
                else        state <= stateResetWaitLock;        // Remain in same state
            end

            stateInitWait100us:
            begin
                delayNanoseconds(wait100us, timeout);           // Call a function to cause a 100us delay
                sdram_CLKE <= 1'd1;                             // Set clock enable high

                do
                    if (timeout) state <= stateInitPrecharge;   // Assign next state
                while (!timeout);                               // Wait until timeout has occured
            end

            stateInitPrecharge:
            begin
                sdram_CLKE <= 1'b1;                             // Set clock enable high
                state <= stateInitStartTrp;                     // Assign next state
            end

            stateInitStartTrp:
            begin
                delayNanoseconds(waitTrp, timeout);             // Call a function ot cause a 6ns delay

                do
                    if (timeout) state <= stateInitRefresh1;    // Assign next state
                while (!timeout);
            end

            stateInitRefresh1:
            begin
                state <= stateInitStartTrfc1;                   // Assign next state
            end

            stateInitStartTrfc1:
            begin
                delayNanoseconds(waitTrfc, timeout);            // call a function to cause a 16us delay

                do
                    if (timeout) state <= stateInitRefresh2;    // Assign next state
                while (!timeout);                               // Wait until timeout has occured
            end

            stateInitRefresh2:
            begin
                state <= stateInitStartTrfc2;                   // Assign next state
            end

            stateInitStartTrfc2:
            begin
                delayNanoseconds(waitTrfc, timeout);            // call a function to cause a 16us delay

                do
                    if (timeout)    state <= stateInitLMR;      // Assign next state
                while (!timeout);                               // Wait until timeout has occured
            end

            stateInitLMR:
            begin
                state <= stateInitStartTmrd;                    // Assign next state
            end

            stateInitStartTmrd:
            begin
                delayNanoseconds(waitTmrd, timeout);            // Wait for the commmand to be executed

                do
                    if (timeout) state <= stateIdle;            // Exit the state machine and set IDLE state on completion
                while (!timeout);                               // Wait until timeout has occured
            end

            /*=============================================================================================================*
             *                                               IDLE STATE                                                    *
             *=============================================================================================================*/
            stateIdle:
            begin
                refresh_request <= 1'b0;                        // Clear refresh_request
                state <= stateIdleStartTrr;
            end

            stateIdleStartTrr:
            begin
                delayNanoseconds(waitTrr, timeout);             // Call a function to count Trr cycles

                do
                    if (timeout)    refresh_request <= 1'b1;    // Set refresh_request
                while (!timeout);

                // Set main state to Auto Refresh if Chip select is low (neither read nor write)
                if (refresh_request && !CSn) state <= stateAutoRefresh;
                else if (W_Rn)  state <= stateWrite;
                else if (!W_Rn) state <= stateRead;
            end

            /*=============================================================================================================*
             *                                          AUTO REFRESH STATE                                                 *
             *=============================================================================================================*/

            stateAutoRefresh:
            begin
                state <= stateAutoRefreshPrecharge;
            end

            stateAutoRefreshPrecharge:
            begin
                sdram_CLKE <= 1'b1;                             // Set clock enable high
                state <= stateAutoRefreshStartTrp;              // Assign next state
            end

            stateAutoRefreshStartTrp:
            begin
                delayNanoseconds(waitTrp, timeout);             // Call a function ot cause a 6ns delay

                do
                    // Assign next state
                    if (timeout) state <= stateAutoRefreshRefresh;
                while (!timeout);                               // Wait until timeout has occured
            end

            stateAutoRefreshRefresh:
            begin
                state <= stateAutoRefreshStartTrfc;             // Assign next state
            end

            stateAutoRefreshStartTrfc:
            begin
                delayNanoseconds(waitTrfc, timeout);            // Call a function to cause a 16us delay
                refresh_request <= 1'b0;                        // Clear refresh request

                do
                    if (timeout)
                    begin
                        state <= stateIdle;                     // Return to IDLE state
                        ready <= 1'b1;                          // Set ready
                    end
                    else ready <= 1'b0;                         // Clear ready
                while (!timeout);
            end

            /*=============================================================================================================*
             *                                               WRITE STATE                                                   *
             *=============================================================================================================*/
            stateWrite:
            begin
                sdram_BA <= ADD[21:20];                         // Set bits 21:20 of input address to Bank enable
                state <= stateWriteActive;                      // Assign next state
            end

            stateWriteActive:
            begin
                sdram_BA <= ADD[21:20];                         // Set bits 21:20 of input address to Bank enable
                state <= stateWriteNop1;                        // Assign next state
            end

            stateWriteNop1:
            begin
                delayNanoseconds(waitTrcd, timeout);            // Call function to delay

                do
                    if (timeout) state <= stateWrite1;          // Assign next state
                while (!timeout);                               // Wait for the delay to occur
            end

            stateWrite1:
            begin
                temp_DQ <= data[07:00];                         // Send out the lower byte
                state <= stateWrite2;                           // Assign nextt state
            end

            stateWrite2:
            begin
                temp_DQ <= data[15:08];                         // Send out the second byte
                state <= stateWrite3;                           // Assign nextt state
            end

            stateWrite3:
            begin
                temp_DQ <= data[23:16];                         // Send out the third byte
                state <= stateWrite4;                           // Assign nextt state
            end

            stateWrite4:
            begin
                temp_DQ <= data[31:24];                         // Send out the fourth byte
                state <= stateWriteNop2;                        // Assign nextt state
            end

            stateWriteNop2:
            begin
                state <= stateWritePrecharge;                   // Assign next state
            end

            stateWritePrecharge:
            begin
                sdram_CLKE <= 1'b1;                             // Set clock enable high
                state      <= stateWriteStartTrp;               // Assign next state
            end

            stateWriteStartTrp:
            begin
                delayNanoseconds(waitTrp, timeout);             // Call a function ot cause a 6ns delay

                do
                    if (timeout) state <= stateWriteNop3;       // Assign next state
                while (!timeout);
            end

            stateWriteNop3:
            begin
                state <= stateIdle;                             // Assign next state
                ready <= 1'b1;                                  // Set ready
            end

            /*=============================================================================================================*
             *                                               READ STATE                                                    *
             *=============================================================================================================*/

            stateRead:
            begin
                sdram_BA <= ADD[21:20];                         // Set bits 21:20 of input address to Bank enable
                state <= stateReadActive;                       // Assign next state
            end

            stateReadActive:
            begin
                sdram_BA <= ADD[21:20];                         // Set bits 21:20 of input address to Bank enable
                state <= stateReadNop1;                         // Assign next state
            end

            stateReadNop1:
            begin
                delayNanoseconds(waitTrcd, timeout);            // Call function to cause delay

                do
                    if (timeout) state <= stateReadCmd;         // Assign next state
                while (!timeout);                               // Wait for the delay to occur
            end

            stateReadCmd:
            begin
                sdram_BA <= ADD[21:20];                         // Set bits 21:20 of input address to Bank enable
                state <= stateReadNop2;                         // Assign next state
            end

            stateReadNop2:
            begin
                sdram_BA <= ADD[21:20];                         // Set bits 21:20 of input address to Bank enable
                state <= stateReadNop3;                         // Assign next state
            end

            stateReadNop3:
            begin
                sdram_BA <= ADD[21:20];                         // Set bits 21:20 of input address to Bank enable
                state <= stateRead1;                            // Assign next state
            end

            stateRead1:
            begin
                temp_data[07:00] <= sdram_DQ;                   // Store the read value
                state <= stateRead2;                            // Assign next state
            end

            stateRead2:
            begin
                temp_data[15:08] <= sdram_DQ;                   // Store the read value
                state <= stateRead3;                            // Assign next state
            end

            stateRead3:
            begin
                temp_data[23:16] <= sdram_DQ;                   // Store the read value
                state <= stateRead4;                            // Assign next state
            end

            stateRead4:
            begin
                temp_data[31:24] <= sdram_DQ;                   // Store the read value
                state <= stateReadNop4;                         // Assign next state
            end

            stateReadNop4:
            begin
                state <= stateReadPrecharge;                    // Assign next state
            end

            stateReadPrecharge:
            begin
                delayNanoseconds(waitTrp, timeout);             // Call a function ot cause a 6ns delay

                do
                    if (timeout) state <= stateReadNop5;        // Assign next state
                while (!timeout);
            end

            stateReadNop5:
            begin
                state <= stateIdle;                             // Assign next state
                ready <= 1'b1;                                  // Set ready
            end
        endcase
    end

    /*=============================================================================================================*
     *                                               End of FSM                                                    *
     *=============================================================================================================*/


    // Combinational block to set 3 bit sdram_CMD bits
    always_comb
    begin
        casez (state)
            stateInitWait100us, stateInitStartTrp, stateInitStartTrfc1, stateInitStartTrfc2, stateIdle, stateAutoRefreshStartTrp, stateWrite, stateWriteNop1, stateWriteNop2, stateWriteNop3, stateRead, stateReadNop1, stateReadNop2, stateReadNop3, stateRead1, stateRead2, stateRead3, stateRead4, stateReadNop4, stateReadNop5:
            begin
                sdram_CMD <= cmd_NOP;                           // Issue NOP command
            end

            stateInitPrecharge, stateAutoRefreshPrecharge:
            begin
                sdram_CMD <= cmd_PRECHARGE;                     // Issue Precharge command
            end

            stateInitRefresh1, stateInitRefresh2, stateAutoRefreshRefresh:
            begin
                sdram_CMD <= cmd_AREFRESH;                      // Issue Refresh command
            end

            stateInitLMR:
            begin
                sdram_CMD <= cmd_LMR;                           // Issue LMR command
            end

            stateWriteActive, stateReadActive:
            begin
                sdram_CMD <= cmd_ACTIVE;                        // Issue Active command
            end

            stateWrite1:
            begin
                sdram_CMD <= cmd_WRITE;                         // Issue Write command
            end

            stateReadCmd:
            begin
                sdram_CMD <= cmd_READ;                          // Issue Read command
            end

            default:
            begin
                sdram_CMD <= cmd_NOP;                           // Issue NOP command
            end
        endcase
    end

    // Combinational block to set the 12 bit Multiplexed address bits
    always_ff @ (posedge clk)
    begin
        sdram_MUXADD[09] = 1'b0;                                // Unused bits
        sdram_MUXADD[11] = 1'b0;                                // Unused bits
        case (state)
            stateInitPrecharge:
            begin
                sdram_MUXADD[10] <= 1'b1;                       // Set A10 high to precharge all rows and columns
            end

            stateWriteActive:
            begin
                sdram_MUXADD[10] <= 1'b1;                       // Set A10 high to enable auto precharge
                sdram_MUXADD[08:00] <= ADD[18:07];              // Assign column address from bits [18:07] of input word address
            end

            stateWrite1:
            begin
                sdram_MUXADD[10] <= 1'b1;                       // Set A10 high to enable auto precharge
                sdram_MUXADD[08:00] <= ADD[06:00];              // Assign column address from the lower 7 bits of input word address
            end

            stateReadActive:
            begin
                sdram_MUXADD[10] <= 1'b1;                       // Set A10 high to enable auto precharge
                sdram_MUXADD[08:00] <= ADD[18:07];              // Assign column address from bits [18:07] of input word address
            end

            stateReadCmd:
            begin
                sdram_MUXADD[10] <= 1'b1;                       // Set A10 high to enable auto precharge
                sdram_MUXADD[08:00] <= ADD[06:00];              // Assign column address from the lower 7 bits of input word address
            end
        endcase
    end

endmodule
