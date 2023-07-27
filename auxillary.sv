// function logic waitTime (
//         input clk,              // 100MHz Clock
//         input waitTime          // Return value
//     );

//     int i;
//     if (waitTime == 3'd0)
//     begin
//         for (i = 0; i < 10000; i++)
//             @(posedge clk);
//         if (i == 10000) waitTime = 1'b1;
//         else            waitTime = 1'b0;
//     end

//     else if (waitTime == 3'd1)
//     begin
//         for (i = 0; i < 1600; i++)
//             @(posedge clk);
//         if (i == 1600)  waitTime = 1'b1;
//         else            waitTime = 1'b0;
//     end

//     else if (waitTime == 3'd2)
//     begin
//         #6
//         waitTime = 1'b1;
//     end

// endfunction