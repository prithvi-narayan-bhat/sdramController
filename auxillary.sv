task delayNanoseconds (
        input delayTimeNs,      // Return value
        output logic timeout    // Return value
    );

    int i = delayTimeNs;
    timeout = 0;                // Clear timeout
    while ( i > 0)
        i--;                    // Decrement

    timeout = 1;                // Set timeout

    if (timeout)    return;     // Indicate delay has been effected

endtask