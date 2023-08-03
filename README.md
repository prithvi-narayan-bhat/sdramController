# sdramController

## Finite State Machine
Following are the states in the Finite State Machine (FSM)
00. stateReset                : System enters state machine here
01. stateResetWaitLock        : Waits for the PLL to lock and synchronize phased clock at (clk2 / 2)
02. stateInitWait100us        : Wait a 100us for clock to stabilize
03. stateInitPrecharge        : Set CLKE high and send out the precharge command
04. stateInitStartTrp         : Start the Trp counter
05. stateInitRefresh1         : Perform the auto refresh action for the first time
06. stateInitStartTrfc1       : Start the Trfc counter
07. stateInitRefresh2         : Perform the auto refresh action for the second time
08. stateInitStartTrfc2       : Start the Trfc counter
09. stateInitLMR              : Load the Load mode register into the SDRAM
10. stateInitStartTmrd        : Start the Tmrd counter
11. stateIdle                 : Enter Idle state
12. stateIdleStartTrr         : Start timer for auto refresh
13. stateAutoRefresh          : Move to auto refresh if timer expires
14. stateAutoRefreshPrecharge : Issue Precharge command
15. stateAutoRefreshStartTrp  : Start Trp counter
16. stateAutoRefreshRefresh   : Issue Refresh command
17. stateAutoRefreshStartTrfc : Start Trfc command
18. stateWrite                : Move to write state
19. stateWriteActive          : Issue active command
20. stateWriteNop1            : Issue a NOP command
21. stateWrite1               : Issue a write command and Write 1st Byte
22. stateWrite2               : Write 2nd Byte
23. stateWrite3               : Write 3rd Byte
24. stateWrite4               : Write 4th Byte
25. stateWriteNop2            : Issue a NOP command
26. stateWritePrecharge       : Issue Precharge command
27. stateWriteStartTrp        : Start Trp counter
28. stateWriteNop3            : Issue a NOP command
29. stateRead                 : Enter Read state
30. stateReadActive           : Issue a active command
31. stateReadNop1             : Issue a NOP command
32. stateReadCmd              : Issue a read command
33. stateReadNop2             : Issue a NOP command
34. stateReadNop3             : Issue a NOP command
35. stateRead1                : Read 1st Byte
36. stateRead2                : Read 2nd Byte
37. stateRead3                : Read 3rd Byte
38. stateRead4                : Read 4th Byte
39. stateReadNop4             : Issue a NOP command
40. stateReadPrecharge        : Issue Precharge command
41. stateReadStartTrp         : Start a Trp counter
42. stateReadNop5             : Issue a NOP command