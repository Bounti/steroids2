#!/bin/bash

./a.out TEST_LOGIC_RESET TEST_LOGIC_RESET 1  0 0
#                                              1010
./a.out SHIFT_IR         SHIFT_IR         4  0 A
#                                              01010000000000000000000000000000010
./a.out SHIFT_DR         RUN_TEST_IDLE    35 0 280000002
#                                              00000000000000000000000000000000100
./a.out SHIFT_DR         RUN_TEST_IDLE    35 0 4
#                                              00000000000000000000000000000001011
./a.out SHIFT_IR         SHIFT_DR         4  0 B
#                                              01000100000000000000000001000000000
./a.out SHIFT_DR         RUN_TEST_IDLE    35 0 220000200

