module sdramController(
        input CLK,                              // 50MHz clock                      | from uP
        input RESETn,                           // Reset            | Active low    | from uP
        input ADSn,                             // Address strobe   | Active low    | from uP
        input M_IOn,                            // memory/IO        | IO Active low | from uP
        input W_Rn,                             // Write/Read       | R Active low  | from uP
        input CSn,                              // Chip Select      | Active low    | from uP
        input [29:00] ADD,                      // 30 bit address                   | from uP
        input [03:00] BE,                       // Byte Enable signal               | from uP

        inout wire [31:00] data,                // 32bit data to read/write         | from/to uP
        inout wire [07:00] sdram_DQ,            // 1byte bidirectional data         | from/to SDRAM

        output reg READYn,                      // Ready            | Active high   | to uP
        output reg sdram_CLK,                   // 100Mhz clock output              | to SDRAM
        output reg sdram_CKE,                   // Clock enable                     | to SDRAM
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
    parameter stateResetWaitLock        = 6'd00;
    // Init State
    parameter stateInitWait100us        = 6'd01;
    parameter stateInitPrecharge        = 6'd02;
    parameter stateInitNop1             = 6'd03;
    parameter stateInitRefresh1         = 6'd04;
    parameter stateInitNop2             = 6'd05;
    parameter stateInitRefresh2         = 6'd06;
    parameter stateInitNop3             = 6'd07;
    parameter stateInitLMR              = 6'd08;
    parameter stateInitNop4             = 6'd09;
    // Idle State
    parameter stateIdle                 = 6'd10;
    parameter stateIdleStartTrr         = 6'd11;
    // Auto refresh State
    parameter stateAutoRefreshPrecharge = 6'd14;
    parameter stateAutoRefreshNop1  = 6'd15;
    parameter stateAutoRefreshRefresh   = 6'd16;
    parameter stateAutoRefreshNop2 = 6'd17;
    // Write States
    parameter stateWriteActive          = 6'd18;
    parameter stateWriteNop1            = 6'd19;
    parameter stateWrite1               = 6'd20;
    parameter stateWrite2               = 6'd21;
    parameter stateWrite3               = 6'd22;
    parameter stateWrite4               = 6'd23;
    parameter stateWriteNop2            = 6'd24;
    parameter stateWritePrecharge       = 6'd25;
    parameter stateWriteNop3            = 6'd26;
    parameter stateWriteNop4            = 6'd27;
    parameter stateWriteNop5            = 6'd28;
    parameter stateWriteNop6            = 6'd29;
    // Read States
    parameter stateReadActive           = 6'd30;
    parameter stateReadNop1             = 6'd31;
    parameter stateReadCmd              = 6'd32;
    parameter stateReadNop2             = 6'd33;
    parameter stateRead1                = 6'd34;
    parameter stateRead2                = 6'd35;
    parameter stateRead3                = 6'd36;
    parameter stateRead4                = 6'd37;
    parameter stateReadNop3             = 6'd38;
    parameter stateReadPrecharge        = 6'd39;
    parameter stateReadStartTrp         = 6'd40;
    parameter stateReadNop4             = 6'd41;
    parameter stateReadNop5             = 6'd42;
    // Idle 2 states
    parameter stateIdle2                = 6'd43;
    parameter stateIdleStartTrr2        = 6'd44;

    /*
        1MHz clock
            => T = 1/1MHz = 10ns
    */
    parameter wait100us = 12'd10000;            // 100us/10ns = 10000 cycles
    parameter waitTrfc  = 12'd6;                // 70ns/10ns  = 7 cycles
    parameter waitTrp   = 12'd2;                // 20ns/10ns  = 2 cycles
    parameter waitTmrd  = 12'd2;                // 20ns/10ns  = 2 cycles
    parameter waitTrr   = 12'd1563;             // 15.625us/10ns = 1563 cycles
    parameter waitTrcd  = 12'd2;                // 20ns/10ns  = 2 cycles
    parameter waitTwr   = 12'd2;                // 20ns/10ns  = 2 cycles


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

    always_ff @ (posedge CLK)
    begin
        if (!RESETn)
        begin
            state = stateResetWaitLock;                         // Set Reset state on reset
            READYn <= 1'b1;                                     // Clear READYn
        end

        else            lock = 1'b0;                            // Clear lock signal

        /*=============================================================================================================*
         *                                               INIT STATE                                                    *
         *=============================================================================================================*/
        case (state)                                            // Finite State Machine
            stateResetWaitLock:                                 // On state INIT
            begin
                lock = 1'b1;                                    // Generate lock signal
                refresh_request <= 1'b1;                        // Set refresh resquest on reset
                READYn <= 1'b1;                                 // Set READYn

                if (lock)   state <= stateInitWait100us;        // Move to next state on lock signal
                else        state <= stateResetWaitLock;        // Remain in same state
            end

            stateInitWait100us:
            begin
                delayNanoseconds(wait100us, RESETn, timeout);   // Call a function to cause a 100us delay
                READYn <= 1'b1;                                 // Set READYn
                sdram_CKE <= 1'd1;                              // Set clock enable high

                do
                    if (timeout) state <= stateInitPrecharge;   // Assign next state
                while (!timeout);                               // Wait until timeout has occured
            end

            stateInitPrecharge:
            begin
                sdram_CKE <= 1'b1;                             // Set clock enable high
                state <= stateInitNop1;                         // Assign next state
                sdram_CKE <= 1'd1;                              // Set clock enable high
                READYn <= 1'b1;                                 // Set READYn
            end

            stateInitNop1:
            begin
                state <= stateInitRefresh1;                     // Assign next state
            end

            stateInitRefresh1:
            begin
                state <= stateInitNop2;                         // Assign next state
                sdram_CKE <= 1'd1;                              // Set clock enable high
                READYn <= 1'b1;                                 // Set READYn
            end

            stateInitNop2:
            begin
                delayNanoseconds(waitTrfc, RESETn, timeout);    // call a function to cause a 16us delay
                READYn <= 1'b1;                                 // Set READYn

                do
                    if (timeout) state <= stateInitRefresh2;    // Assign next state
                while (!timeout);                               // Wait until timeout has occured
                sdram_CKE <= 1'd1;                              // Set clock enable high
            end

            stateInitRefresh2:
            begin
                state <= stateInitNop3;                         // Assign next state
                sdram_CKE <= 1'd1;                              // Set clock enable high
                READYn <= 1'b1;                                 // Set READYn
            end

            stateInitNop3:
            begin
                delayNanoseconds(waitTrfc, RESETn, timeout);    // call a function to cause a 16us delay

                do
                    if (timeout)    state <= stateInitLMR;      // Assign next state
                while (!timeout);                               // Wait until timeout has occured
                sdram_CKE <= 1'd1;                              // Set clock enable high
                READYn <= 1'b1;                                 // Set READYn
            end

            stateInitLMR:
            begin
                state <= stateInitNop4;                         // Assign next state
                sdram_CKE <= 1'd1;                              // Set clock enable high
                READYn <= 1'b1;                                 // Set READYn
            end

            stateInitNop4:
            begin
                READYn <= 1'b1;                                 // Set READYn
                state <= stateIdle;                             // Exit the state machine and set IDLE state on completion
                sdram_CKE <= 1'd1;                              // Set clock enable high
            end

            /*=============================================================================================================*
             *                                               IDLE STATE                                                    *
             *=============================================================================================================*/
            stateIdle:
            begin
                refresh_request <= 1'b0;                        // Clear refresh_request
                state <= stateIdleStartTrr;
                READYn <= 1'b0;                                 // Set READYn
            end

            stateIdleStartTrr:
            begin
                delayNanoseconds(waitTrr, RESETn, timeout);     // Call a function to count Trr cycles
                READYn <= 1'b1;                                 // Set READYn

                do
                    if (timeout)    refresh_request <= 1'b1;    // Set refresh_request
                while (!timeout);

                // Set main state to Auto Refresh if Chip select is low (neither read nor write)
                if (refresh_request && !CSn) state <= stateAutoRefreshPrecharge;
                else if (!refresh_request && W_Rn)  state <= stateWriteActive;
                else if (!refresh_request && !W_Rn) state <= stateReadActive;
                else state <= stateIdle;
            end

            stateIdle2:
            begin
                refresh_request <= 1'b0;                        // Clear refresh_request
                state <= stateIdleStartTrr2;                    // Assign next state
                READYn <= 1'b0;                                 // Clear READYn
            end

            stateIdleStartTrr2:
            begin
                delayNanoseconds(waitTrr, RESETn, timeout);     // Call a function to count Trr cycles
                READYn <= 1'b1;                                 // Set READYn

                do
                    if (timeout)    refresh_request <= 1'b1;    // Set refresh_request
                while (!timeout);

                // Set main state to Auto Refresh if Chip select is low (neither read nor write)
                if (refresh_request && !CSn) state <= stateAutoRefreshPrecharge;
                else if (!refresh_request && W_Rn)  state <= stateWriteActive;
                else if (!refresh_request && !W_Rn) state <= stateReadActive;
                else state <= stateIdle;
            end

            /*=============================================================================================================*
             *                                          AUTO REFRESH STATE                                                 *
             *=============================================================================================================*/
            stateAutoRefreshPrecharge:
            begin
                sdram_CKE <= 1'b1;                              // Set clock enable high
                state <= stateAutoRefreshNop1;                  // Assign next state
                READYn <= 1'b1;                                 // Set READYn
            end

            stateAutoRefreshNop1:
            begin
                state <= stateAutoRefreshRefresh;               // Assign next state
            end

            stateAutoRefreshRefresh:
            begin
                state <= stateAutoRefreshNop2;                  // Assign next state
                READYn <= 1'b1;                                 // Set READYn
            end

            stateAutoRefreshNop2:
            begin
                delayNanoseconds(waitTrfc, RESETn, timeout);    // Call a function to cause a 16us delay
                refresh_request <= 1'b0;                        // Clear refresh request

                do
                    if (timeout)
                    begin
                        state <= stateIdle;                     // Return to IDLE state
                        READYn <= 1'b0;                         // Clear READYn
                    end
                    else READYn <= 1'b1;                        // Set READYn
                while (!timeout);
            end

            /*=============================================================================================================*
             *                                               WRITE STATE                                                   *
             *=============================================================================================================*/
            stateWriteActive:
            begin
                sdram_BA <= ADD[20:19];                         // Set bits 21:20 of input address to Bank enable
                state <= stateWriteNop1;                        // Assign next state
                READYn <= 1'b1;                                 // Set READYn
            end

            stateWriteNop1:
            begin
                state <= stateWrite1;                           // Assign next state
            end

            stateWrite1:
            begin
                temp_DQ <= data[07:00];                         // Send out the lower byte
                state <= stateWrite2;                           // Assign nextt state
                READYn <= 1'b1;                                 // Set READYn
            end

            stateWrite2:
            begin
                temp_DQ <= data[15:08];                         // Send out the second byte
                state <= stateWrite3;                           // Assign nextt state
                READYn <= 1'b1;                                 // Set READYn
            end

            stateWrite3:
            begin
                temp_DQ <= data[23:16];                         // Send out the third byte
                READYn <= 1'b1;                                 // Set READYn
                state <= stateWrite4;                           // Assign nextt state
            end

            stateWrite4:
            begin
                temp_DQ <= data[31:24];                         // Send out the fourth byte
                state <= stateWriteNop2;                        // Assign nextt state
                READYn <= 1'b1;                                 // Set READYn
            end

            stateWriteNop2:
            begin
                READYn <= 1'b1;                                 // Set READYn
                state <= stateWritePrecharge;                   // Assign next state
            end

            stateWritePrecharge:
            begin
                READYn <= 1'b1;                                 // Set READYn
                state <= stateWriteNop3;                        // Assign next state
            end

            stateWriteNop3:
            begin
                READYn <= 1'b1;                                 // Clear READYn
                state <= stateWriteNop4;                        // Assign next state
            end

            stateWriteNop4:
            begin
                READYn <= 1'b0;                                 // Clear READYn
                state <= stateWriteNop5;                        // Assign next state
            end

            stateWriteNop5:
            begin
                READYn <= 1'b0;                                 // Clear READYn
                state <= stateWriteNop6;                        // Assign next state
            end

            stateWriteNop6:
            begin
                READYn <= 1'b0;                                 // Clear READYn
                state <= stateIdle2;                            // Assign next state
            end

            /*=============================================================================================================*
             *                                               READ STATE                                                    *
             *=============================================================================================================*/

            stateReadActive:
            begin
                sdram_BA <= ADD[20:19];                         // Set bits 21:20 of input address to Bank enable
                state <= stateReadNop1;                         // Assign next state
                READYn <= 1'b1;                                 // Set READYn
            end

            stateReadNop1:
            begin
                READYn <= 1'b1;                                 // Set READYn
                state <= stateReadCmd;                          // Assign next state
            end

            stateReadCmd:
            begin
                READYn <= 1'b1;                                 // Set READYn
                sdram_BA <= ADD[20:19];                         // Set bits 21:20 of input address to Bank enable
                state <= stateReadNop2;                         // Assign next state
            end

            stateReadNop2:
            begin
                READYn <= 1'b1;                                 // Set READYn
                sdram_BA <= ADD[20:19];                         // Set bits 21:20 of input address to Bank enable
                state <= stateRead1;                            // Assign next state
            end

            stateRead1:
            begin
                READYn <= 1'b1;                                 // Set READYn
                temp_data[07:00] <= sdram_DQ;                   // Store the read value
                state <= stateRead2;                            // Assign next state
            end

            stateRead2:
            begin
                READYn <= 1'b1;                                 // Set READYn
                temp_data[15:08] <= sdram_DQ;                   // Store the read value
                state <= stateRead3;                            // Assign next state
            end

            stateRead3:
            begin
                READYn <= 1'b1;                                 // Set READYn
                temp_data[23:16] <= sdram_DQ;                   // Store the read value
                state <= stateRead4;                            // Assign next state
            end

            stateRead4:
            begin
                READYn <= 1'b1;                                 // Set READYn
                temp_data[31:24] <= sdram_DQ;                   // Store the read value
                state <= stateReadNop3;                         // Assign next state
            end

            stateReadNop3:
            begin
                state <= stateReadNop4;                         // Assign next state
                READYn <= 1'b0;                                 // Clear READYn
            end

            stateReadNop4:
            begin
                state <= stateReadNop5;                         // Assign next state
                READYn <= 1'b0;                                 // Clear READYn
            end

            stateReadNop5:
            begin
                state <= stateIdle2;                            // Assign next state
                READYn <= 1'b0;                                 // Clear READYn
            end
        endcase
    end

    /*=============================================================================================================*
     *                                               End of FSM                                                    *
     *=============================================================================================================*/

    assign sdram_DQ = temp_DQ;                                  // Assign write data
    assign data = temp_data;                                    // Assign the read data
    assign sdram_CSn = CSn;                                     // Assign as is

    // Combinational block to set 3 bit sdram_CMD bits
    always_comb
    begin
        case (state)
            stateInitWait100us, stateInitNop1, stateInitNop2, stateInitNop3, stateIdle, stateAutoRefreshNop1, stateWriteNop1, stateWriteNop2, stateWriteNop3,stateWriteNop6, stateReadNop1, stateReadNop2, stateRead1, stateRead2, stateRead4, stateReadNop3, stateReadStartTrp, stateReadNop4, stateReadNop5:
            begin
                sdram_CMD <= cmd_NOP;                           // Issue NOP command
            end

            stateInitPrecharge, stateAutoRefreshPrecharge, stateWritePrecharge, stateRead3:
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
    always_comb
    begin
        case (state)
            stateInitPrecharge, stateAutoRefreshPrecharge:
            begin
                sdram_MUXADD[10] <= 1'b1;                       // Set A10 high to precharge all rows and columns
                sdram_MUXADD[08:00] <= 9'bx;                    // Don't care for other bits in this state
                sdram_MUXADD[09] <= 1'b0;                       // Unused bits
                sdram_MUXADD[11] <= 1'b0;                       // Unused bits
            end

            stateWriteActive:
            begin
                sdram_MUXADD[11:00] <= ADD[18:07];              // Assign row address
            end

            stateWrite1:
            begin
                sdram_MUXADD[08:00] <= ADD[06:00];              // Assign column address from the lower 7 bits of input word address
                sdram_MUXADD[10] <= 1'b0;                       // Set A10 low to disable auto precharge
                sdram_MUXADD[09] <= 1'b0;                       // Unused bits
                sdram_MUXADD[11] <= 1'b0;                       // Unused bits
            end

            stateReadActive:
            begin
                sdram_MUXADD[11:00] <= ADD[18:07];              // Assign row address
            end

            stateReadCmd:
            begin
                sdram_MUXADD[08:00] <= ADD[06:00];              // Assign column address from the lower 7 bits of input word address
                sdram_MUXADD[10] <= 1'b0;                       // Set A10 low to disable auto precharge
                sdram_MUXADD[09] <= 1'b0;                       // Unused bits
                sdram_MUXADD[11] <= 1'b0;                       // Unused bits
            end

            default:                                            // Don't care for other states
            begin
                sdram_MUXADD[10] <= 1'bx;                       // Don't care for other bits in this state
                sdram_MUXADD[08:00] <= 9'bx;                    // Don't care for other bits in this state
                sdram_MUXADD[09] <= 1'b0;                       // Unused bits
                sdram_MUXADD[11] <= 1'b0;                       // Unused bits
            end
        endcase
    end

    // Combinational block to generate sdram_DQM signal
    always_comb
    begin
        case (state)
            stateRead1, stateWrite1:
            begin
                sdram_DQM <= BE[0];                             // Assign value in BE[0]
            end

            stateRead2, stateWrite2:
            begin
                sdram_DQM <= BE[1];                             // Assign value in BE[1]
            end

            stateRead3, stateWrite3:
            begin
                sdram_DQM <= BE[2];                             // Assign value in BE[2]
            end

            stateRead4, stateWrite4:
            begin
                sdram_DQM <= BE[3];                             // Assign value in BE[3]
            end

            default:
            begin
                sdram_DQM <= 1'bx;                             // Assign value in BE[3]
            end
        endcase
    end

endmodule