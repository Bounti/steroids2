#include <stdio.h>
#include <stdlib.h>

#define BYTE_TO_BINARY_PATTERN "%c%c%c%c%c%c%c%c"
#define BYTE_TO_BINARY(byte)  \
  (byte & 0x80 ? '1' : '0'), \
  (byte & 0x40 ? '1' : '0'), \
  (byte & 0x20 ? '1' : '0'), \
  (byte & 0x10 ? '1' : '0'), \
  (byte & 0x08 ? '1' : '0'), \
  (byte & 0x04 ? '1' : '0'), \
  (byte & 0x02 ? '1' : '0'), \
  (byte & 0x01 ? '1' : '0')

char usage[] = "./packet_forge <state_start> <state_end> <bitcount> <period> <payload>\n" \
"TEST_LOGIC_RESET  0\n"\
"RUN_TEST_IDLE     1\n"\
"SELECT_DR         2\n"\
"CAPTURE_DR        3\n"\
"SHIFT_DR          4\n"\
"EXIT1_DR          5\n"\
"PAUSE_DR          6\n"\
"EXIT2_DR          7\n"\
"UPDATE_DR         8\n"\
"SELECT_IR         9\n"\
"CAPTURE_IR        10\n"\
"SHIFT_IR          11\n"\
"EXIT1_IR          12\n"\
"PAUSE_IR          13\n"\
"EXIT2_IR          14\n"\
"UPDATE_IR         15\n";

char* JTAG_STATES_STR[] = {"TEST_LOGIC_RESET",
"RUN_TEST_IDLE",
"SELECT_DR",
"CAPTURE_DR",
"SHIFT_DR",
"EXIT1_DR",
"PAUSE_DR",
"EXIT2_DR",
"UPDATE_DR",
"SELECT_IR",
"CAPTURE_IR",
"SHIFT_IR",
"EXIT1_IR",
"PAUSE_IR",
"EXIT2_IR",
"UPDATE_IR"};

enum JTAG_STATE{SHIFT_DR, SHIFT_IR, IDLE, RESET};

unsigned int decode_state(char* arg) {
  int i;
  for(i=0; i<=0x10; i++)
    if( strcmp(JTAG_STATES_STR[i], arg) == 0)
      return i;
}

int main(int argc, char** argv) {

  char state_start;
  char state_end;
  char bitcount;
  char period;
  unsigned long payload;

  if( argc < 6 ) {
    printf("%s\n", usage);
    return 0;
  }

  //state_start = atoi(argv[1]) & 0xF;
  // Check parameter state_start
  //if( state_start > 0xF) {
  //  printf("state_start has to be less than 15");
  //  return 0;
  //}
  unsigned int decoded_jtag_state = decode_state(argv[1]);
  if( decoded_jtag_state == -1 ) {
    printf("state_start is not a valid value");
    return 0;
  }
  state_start = decoded_jtag_state;

  //state_end = atoi(argv[2]) & 0xF;
  // Check parameter state_end
  //if( state_end > 0xF) {
  //  printf("state_end has to be less than 15");
  //  return 0;
  //}
  decoded_jtag_state = decode_state(argv[2]);
  if( decoded_jtag_state == -1 ) {
    printf("state_start is not a valid value");
    return 0;
  }
  state_end = decoded_jtag_state;

  bitcount = atoi(argv[3]) & 0x3F;
  // Check bitcount parameter
  if( bitcount > 0x3F ) {
    printf("bitcount has to be less than 63");
    return 0;
  }

  period = atoi(argv[4]) & 0x3F;
  // Check period parameter
  if( period > 0x3F ) {
    printf("bitcount has to be less than 63");
    return 0;
  }

  payload = (unsigned long)strtol(argv[5], NULL, 16) & 0x1FFFFFFFFFFF;
  //payload = atoi(argv[5]) & 0x1FFFFFFFFFFF;
  // Check payload parameter : 44bits length
  if( payload > 0x1FFFFFFFFFFF ) {
    printf("payload have to be less than 0x1FFFFFFFFFFF (3,518437209×10¹³)");
    return 0;
  }

  unsigned long packet = 0;

  packet = (state_start & 0xF);
  packet |= (state_end   & 0xF) << 4;
  packet |= (bitcount    & 0x3F) << 8;
  packet |= (period      & 0x3F) << 14;
  packet |= (payload     & 0x1FFFFFFFFFFF) << 20;

  printf("packet: \n"BYTE_TO_BINARY_PATTERN" "BYTE_TO_BINARY_PATTERN" "BYTE_TO_BINARY_PATTERN" "BYTE_TO_BINARY_PATTERN"  "BYTE_TO_BINARY_PATTERN"  "BYTE_TO_BINARY_PATTERN"  "BYTE_TO_BINARY_PATTERN"  "BYTE_TO_BINARY_PATTERN" \n",
  BYTE_TO_BINARY(packet>>56), BYTE_TO_BINARY(packet>>48), BYTE_TO_BINARY(packet>>40), BYTE_TO_BINARY(packet>>32), BYTE_TO_BINARY(packet>>24), BYTE_TO_BINARY(packet>>16), BYTE_TO_BINARY(packet>>8), BYTE_TO_BINARY(packet));

  printf("packet: %08lx%08lx\n",(packet>>32)&0xFFFFFFFF,(packet&0xFFFFFFFF));
}
