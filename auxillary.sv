task delayNanoseconds (
        input clk,              // 100MHz Clock
        input delayTimeNs,      // Return value
        output logic timeout    // Return value
    );

    int i;
    timeout = 0;
    for (i = 0; i < (delayTimeNs); i++)
        @(posedge clk);         // Wait for a positive edge of the clock

    timeout = 1;

    if (timeout)    return;     // Indicate delay has been effected

endtask