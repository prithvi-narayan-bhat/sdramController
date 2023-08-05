task delayNanoseconds (
        input delayTimeNs,      // Return value
        input RESETn,
        output logic timeout    // Return value
    );

    int i = delayTimeNs;
    timeout = 0;                // Clear timeout
    while ( i > 0)
    begin
        i--;                    // Decrement
        if (!RESETn)    break;
    end

    if (i == 0) timeout = 1;                // Set timeout

    if (timeout)    return;     // Indicate delay has been effected

endtask