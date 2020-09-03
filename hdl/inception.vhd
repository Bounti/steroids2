library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use IEEE.STD_LOGIC_ARITH.ALL;

use work.inception_pkg.all;

USE std.textio.all;
use ieee.std_logic_textio.all;

entity inception is
  Generic (
    PERIOD_RANGE    : natural := 63;
    BIT_COUNT_SIZE  : natural := 6;
    MAX_IO_REG_SIZE : natural := 64 
  );
  Port (
    aclk:       in std_logic;  -- Clock
    aresetn:    in std_logic;  -- Synchronous, active low, reset

    led:            out std_logic_vector(7 downto 0); -- LEDs

    irq_in:         in std_logic;
    irq_ack:        out std_logic;
    ----------------------
    -- jtag ctrl master --
    ----------------------
    TDO		    : in  STD_LOGIC;
    TCK		    : out  STD_LOGIC;
    TMS		    : out  STD_LOGIC;
    TDI		    : out  STD_LOGIC;
    TRST            : out  STD_LOGIC;

    -----------------------
    -- slave fifo master --
    -----------------------
    clk_out	   : out std_logic;                               ---output clk 100 Mhz and 180 phase shift
    fdata          : inout std_logic_vector(31 downto 0);
    sladdr         : out std_logic_vector(1 downto 0);
    sloe	   : out std_logic;                               ---output output enable select
    slop	   : out std_logic;                               ---output write select

    slwr_rdy	   : in std_logic;
    slwrirq_rdy	   : in std_logic;
    slrd_rdy	   : in std_logic

  );
end entity inception;

architecture beh of inception is

  constant STATE_START_BEGIN_OFFSET : natural := 0;
  constant STATE_START_END_OFFSET   : natural := 3;
  
  constant STATE_END_BEGIN_OFFSET   : natural := 4;
  constant STATE_END_END_OFFSET     : natural := 7;

  constant BITCOUNT_BEGIN_OFFSET    : natural := STATE_END_END_OFFSET+1;
  constant BITCOUNT_END_OFFSET      : natural := BITCOUNT_BEGIN_OFFSET+BIT_COUNT_SIZE-1;

  constant PERIOD_BEGIN_OFFSET      : natural := BITCOUNT_END_OFFSET+1;
  constant PERIOD_END_OFFSET        : natural := PERIOD_BEGIN_OFFSET+6-1;

  constant PAYLOAD_BEGIN_OFFSET      : natural := PERIOD_END_OFFSET+1;
  constant PAYLOAD_END_OFFSET       : natural := PAYLOAD_BEGIN_OFFSET+MAX_IO_REG_SIZE-1;

  -- Jtag ctrl signals
  signal jtag_bit_count:     std_logic_vector(BIT_COUNT_SIZE-1 downto 0);
  signal jtag_shift_strobe:  std_logic;
  signal jtag_busy:          std_logic;
  signal jtag_state_start:   std_logic_vector(3 downto 0);
  signal jtag_state_end:     std_logic_vector(3 downto 0);
  signal jtag_state_current: std_logic_vector(3 downto 0);
  signal jtag_di:            std_logic_vector(MAX_IO_REG_SIZE-1 downto 0);
  signal jtag_do:            std_logic_vector(MAX_IO_REG_SIZE-1 downto 0);
  signal period:             natural range 0 to PERIOD_RANGE;    


  component JTAG_Ctrl_Master is
    Generic (
           PERIOD_RANGE    : natural := PERIOD_RANGE; 
           BIT_COUNT_SIZE  : natural := BIT_COUNT_SIZE;
           MAX_IO_REG_SIZE : natural := MAX_IO_REG_SIZE
    );
    Port (
      CLK			: in  STD_LOGIC;
      aresetn                   : in  STD_LOGIC;
      -- JTAG Part
      period        : in  natural range 0 to PERIOD_RANGE;
      BitCount			: in  STD_LOGIC_VECTOR (BIT_COUNT_SIZE-1 downto 0);
      Shift_Strobe	: in  STD_LOGIC;								-- eins aktiv...
      TDO		        : in  STD_LOGIC;
      TCK		        : out  STD_LOGIC;
      TMS		        : out  STD_LOGIC;
      TDI		        : out  STD_LOGIC;
      TRst		      : out  STD_LOGIC;
      Busy		      : out  STD_LOGIC;
      StateStart		: in	 std_logic_vector(3 downto 0);
      StateEnd			: in	 std_logic_vector(3 downto 0);
      StateCurrent	: out	 std_logic_vector(3 downto 0);
      -- Ram Part
      Din		        : in  STD_LOGIC_VECTOR (MAX_IO_REG_SIZE-1 downto 0);
      Dout			    : out STD_LOGIC_VECTOR (MAX_IO_REG_SIZE-1 downto 0)
  );
  end component;

  component fifo_ram is
  generic(
    width: natural := 32;
    addr_size: natural := 10
  );
  port(
    aclk:  in  std_logic;
    aresetn: in std_logic;
    empty: out std_logic;
    full:  out std_logic;
    put:   in  std_logic;
    get:   in  std_logic;
    din:   in  std_logic_vector(width-1 downto 0);
    dout:  out std_logic_vector(width-1 downto 0)
  );
  end component;

  component fifo_ram_32_to_64 is
  generic(
    width: natural := 32;
    addr_size: natural := 10
  );
  port(
    aclk:  in  std_logic;
    aresetn: in std_logic;
    empty: out std_logic;
    full:  out std_logic;
    put:   in  std_logic;
    get:   in  std_logic;
    din:   in  std_logic_vector(width-1 downto 0);
    dout:  out std_logic_vector((width*2)-1 downto 0)
  );
  end component;

  component tristate is
  port (
    fdata_in : out std_logic_vector(31 downto 0);
    fdata    : inout std_logic_vector(31 downto 0);
    fdata_out_d : in std_logic_vector(31 downto 0);
    tristate_en_n : in std_logic
  );
  end component;

  component P_ODDR2 is
  port (
    aclk       : in std_logic;
    clk_out    : out std_logic;
    aresetn    : in std_logic
  );
  end component;

  type cmd_read_state_t is (IDLE,READ,START_JTAG,WAIT_START,WAIT_COMPLETION,CHECK_FOR_READBACK,PREPARE_READBACK,DO_READBACK,PREPARE_SECOND_READBACK,DO_SECOND_READBACK);
  signal cmd_read_state : cmd_read_state_t;
  
  signal jtag_write_back   : std_logic;

  signal cmd_empty,data_empty,irq_empty: std_logic;
  signal cmd_full,data_full,irq_full:   std_logic;
  signal cmd_put,data_put,irq_put:     std_logic;
  signal cmd_get,data_get,irq_get:     std_logic;
  signal cmd_din,data_din,irq_din:     std_logic_vector(31 downto 0);
  signal cmd_dout:                     std_logic_vector(63 downto 0);
  signal data_dout,irq_dout:           std_logic_vector(31 downto 0);

  -- fx3 interface
  signal tristate_en_n:                   std_logic;
  signal fdata_in,fdata_in_d,fdata_out_d: std_logic_vector(31 downto 0);
  signal slrd_rdy_d,slwr_rdy_d,slwrirq_rdy_d:           std_logic;

  type sl_state_t is (idle,prepare_read,prepare_write_irq,prepare_write_data,read1,read2,read3,read4,read5,write0,write1,write2);
  signal sl_state: sl_state_t;
  signal sl_is_irq: std_logic;

  -- irq
  signal irq_sync, irq_d1, irq_d2, irq_d3: std_logic;
  type irq_state_t is (idle,forward_event,done);
  signal irq_state: irq_state_t;
  signal irq_id_addr: std_logic_vector(31 downto 0);

 begin
  
  -----------------------------
  -- synchronize irq_in line --
  -----------------------------
  irq_sync <= irq_d3;
  irq_sync_proc: process(aclk)
  begin
    if(aclk'event and aclk='1')then
      if(aresetn='0')then
        irq_d1 <= '0';
	irq_d2 <= '0';
	irq_d2 <= '0';
      else
        irq_d1 <= irq_in;
	irq_d2 <= irq_d1;
	irq_d3 <= irq_d2;
      end if;
    end if;
  end process irq_sync_proc;

  -----------------------
  --irq_in state machine --
  -----------------------
  irq_ack <= '1' when irq_state = done else '0';
  irq_fsm_proc: process(aclk)
  begin
    if(aclk'event and aclk='1')then
      if(aresetn='0')then
	irq_state <= idle;
      else
        case irq_state is
    	    when idle =>
	          if(irq_sync='1')then
	            irq_state <= forward_event;
	          end if;
	        when forward_event =>
	          irq_state <= done;
	        when done =>
	          if(irq_sync='0')then
	            irq_state <= idle;
	          end if;
	        when others =>
	          irq_state <= done;
	       end case;
      end if;
    end if;
  end process irq_fsm_proc;


  --------------------------------------------------------
  -- local fifo to store commands reveived from the fx3 --
  --------------------------------------------------------
  cmd_fifo_inst : fifo_ram_32_to_64
    generic map(
      width => 32,
      addr_size => 4
    )
    port map(
      aclk => aclk,
      aresetn => aresetn,
      empty => cmd_empty,
      full => cmd_full,
      put => cmd_put,
      get => cmd_get,
      din => cmd_din,
      dout => cmd_dout
    );

  -------------------------------------------------------------
  -- local fifo to store data received from the jtag machine --
  -------------------------------------------------------------
  data_fifo_inst: fifo_ram
    generic map(
      width => 32,
      addr_size => 4
    )
    port map(
      aclk     => aclk,
      aresetn  => aresetn,
      empty    => data_empty,
      full     => data_full,
      put      => data_put,
      get      => data_get,
      din      => data_din,
      dout     => data_dout
    );

  ------------------------------------------------------------------
  -- local fifo to store irq id data coming from the jtag machine --
  ------------------------------------------------------------------
  irq_fifo_inst: fifo_ram
    generic map(
      width => 32,
      addr_size => 4
    )
    port map(
      aclk     => aclk,
      aresetn  => aresetn,
      empty    => irq_empty,
      full     => irq_full,
      put      => irq_put,
      get      => irq_get,
      din      => irq_din,
      dout     => irq_dout
    );

  -------------------------------------
  -- logic to interface with the fx3 --
  -------------------------------------

  tristate_inst: tristate
  port map(
    fdata_in      => fdata_in,
    fdata         => fdata,
    fdata_out_d   => fdata_out_d,
    tristate_en_n => tristate_en_n 
  );

  -- io flops
  input_flops_proc: process(aclk)
  begin
    if(aclk'event and aclk='1')then
      if(aresetn='0')then
        slrd_rdy_d <= '0';
	      slwr_rdy_d <= '0';
	      slwrirq_rdy_d <= '0';
	      fdata_in_d <= (others=>'0');
      else
        slrd_rdy_d <= slrd_rdy;
      	slwr_rdy_d <= slwr_rdy;
	      slwrirq_rdy_d <= slwrirq_rdy;
	      fdata_in_d <= fdata_in;
     end if;
    end if;
  end process input_flops_proc;

  --led <= fdata_in_d(31 downto 24);

  -- state machine
  cmd_din <= fdata_in_d;
  cmd_put <= '1' when (sl_state=read5) else '0';
  fdata_out_d <= irq_dout when (sl_is_irq='1') else data_dout;
  data_get <= '1' when (sl_state=prepare_write_data) else '0';
  irq_get  <= '1' when (sl_state=prepare_write_irq ) else '0';
  --tristate_en_n <= '0' when (sl_state=write1) else '1';
  fx3_sl_master_fsm_proc: process(aclk)
  begin
    if(aclk'event and aclk='1')then
      if(aresetn='0')then
        sl_state <= idle;
	      slop <= '0';
	      sloe <= '0';
	      tristate_en_n <= '1';
	      sladdr <= "00";
	      sl_is_irq <= '0';
      else
        case sl_state is
	        when idle =>
	          if(slwrirq_rdy_d='1' and irq_empty='0')then
              sl_state <= prepare_write_irq;
	            sladdr <= "01";
	            sl_is_irq <= '1';
	          elsif(slwr_rdy_d='1' and data_empty='0')then
	            sl_state <= prepare_write_data;
	            sladdr <= "00";
	            sl_is_irq <= '0';
	          elsif(slrd_rdy_d='1' and cmd_full='0')then
	            sl_state <= prepare_read;
	            sladdr <= "11";
	            sl_is_irq <= '0';
	          end if;
	        when prepare_read =>
            sl_state <= read1;
	          slop <= '1';
	          sloe <= '1';
          when prepare_write_data =>
	          sl_state <= write0;
	          tristate_en_n <= '0';
	        when prepare_write_irq =>
	          sl_state <= write0;
	          tristate_en_n <= '0';
	        when read1 =>
	          sl_state <= read2;
	          slop <= '0';
	        when read2 =>
	          sl_state <= read3;
	        when read3 =>
	          sl_state <= read4;
	        when read4 =>
	          sl_state <= read5;
	          sloe <= '0';
	        when read5 =>
	          sl_state <= idle;
	       -- when read6 =>
	       --   sl_state <= read7;
	       -- when read7 =>
	       --   sl_state <= read8;
	       -- when read8 =>
	       --   sl_state <= idle;
	        when write0 =>
	          sl_state <= write1;
	          slop <= '1';
	        when write1 =>
	          sl_state <= write2;
	          slop <= '0';
	          tristate_en_n <= '1';
          when write2 =>
	          sl_state <= idle;
	        when others =>
	          sl_state <= idle;
	          slop <= '0';
	          sloe <= '0';
	          tristate_en_n <= '1';
	          sladdr <= "00";
        end case;
      end if;
    end if;
  end process fx3_sl_master_fsm_proc;
 
  -- cmd_read_state_logic is in charge of poping jtag commands 
  -- from the cmd_fifo. The cmd_fifo receives 32bits commands however 
  -- the jtag fsm process 64bits commands. So, this fsm pop jtag commands
  -- when ever it is possible and push 64bits packet in a ring buffer.
  -- Using this logic, the jtag state machine never wait for inputs and
  -- we can diserve jtag commands at once. Futhermore, the ring buffer 
  -- enables read without any delay so we can prepare next commands right 
  -- after. Some timing constraints has to be respected for the cmd_fifo.
  -- For instance the flags for the cmd_fifo are updated one cycle after 
  -- a push or pop. 

  cmd_read_state_logic: process(aclk)
  begin
    if( aclk'event and aclk = '1' ) then
      if( aresetn = '0' ) then
        cmd_read_state <= IDLE;
        jtag_state_start    <= TEST_LOGIC_RESET;
        jtag_bit_count      <= std_logic_vector(to_unsigned(0,BIT_COUNT_SIZE));
        jtag_state_end      <= TEST_LOGIC_RESET;
        jtag_di             <= std_logic_vector(to_unsigned(0,MAX_IO_REG_SIZE));
        jtag_write_back     <= '0'; 
        period              <= 63;
        jtag_shift_strobe   <= '0';
        irq_put             <= '0';
      else 
          case cmd_read_state is
            when IDLE =>
              jtag_shift_strobe   <= '0';
              if( cmd_empty = '0' and jtag_busy = '0' ) then
                cmd_read_state <= READ;
              end if;
              jtag_write_back     <= '0'; 
            when READ =>
                jtag_shift_strobe   <= '0';
                cmd_read_state <= START_JTAG;
            when START_JTAG =>
              jtag_shift_strobe     <= '1';
              jtag_state_start      <= cmd_dout( 3 downto 0 );
              jtag_state_end        <= cmd_dout( 7 downto 4 );
              jtag_bit_count        <= cmd_dout( 13 downto 8 );
              --period                <= to_integer(unsigned(cmd_dout( 19 downto 14)));
              jtag_di               <= "000000000000000000000"&cmd_dout( 62 downto 20);
              jtag_write_back       <= cmd_dout( 63 );
              cmd_read_state        <= WAIT_START;
            when WAIT_START      =>
              if( jtag_busy = '1' ) then
                cmd_read_state <= WAIT_COMPLETION;
              end if;
            when WAIT_COMPLETION =>
              if( jtag_busy = '0' ) then
                cmd_read_state <= CHECK_FOR_READBACK;
              end if;
            when CHECK_FOR_READBACK =>
              if( jtag_write_back = '1' ) then
                  cmd_read_state      <= PREPARE_READBACK;
              else
                  cmd_read_state      <= IDLE;
              end if;
            when PREPARE_READBACK =>
              if( data_full = '1' ) then
                cmd_read_state        <= PREPARE_READBACK;
              else
                cmd_read_state        <= DO_READBACK;
              end if;
            when DO_READBACK         =>
                cmd_read_state          <= PREPARE_SECOND_READBACK;
            when PREPARE_SECOND_READBACK         =>
              if( data_full = '1' ) then
                cmd_read_state        <= PREPARE_SECOND_READBACK;
              else
                cmd_read_state        <= DO_SECOND_READBACK;
              end if;
            when DO_SECOND_READBACK         =>
                cmd_read_state          <= IDLE;
            when others =>
              cmd_read_state <= IDLE;        
          end case;
      end if;
    end if;
  end process cmd_read_state_logic;

  --led <= cmd_empty&cmd_full&data_empty&data_full&irq_empty&irq_full&jtag_write_back&write_back_pending;
  led(4 downto 0)   <= slrd_rdy_d&slwr_rdy_d&slwrirq_rdy_d&jtag_busy&data_full;

  data_din  <= jtag_do(63 downto 32) when cmd_read_state = DO_SECOND_READBACK else jtag_do(31 downto 0);

	irq_din <= (others=>'1');

  -- cmd_read_out_logic set the outputs of the cmd_read_state_logic process
  cmd_read_out_logic: process(cmd_read_state)
  begin
      case cmd_read_state is
        when IDLE =>
          led(7 downto 5)<= "100";
          cmd_get        <= '0';
          data_put       <= '0';
        when READ =>
          led(7 downto 5)<= "010";
          cmd_get        <= '1';
          data_put       <= '0';
        when START_JTAG =>
          led(7 downto 5)<= "110";
          cmd_get        <= '0';
          data_put       <= '0';
        when WAIT_START =>
          led(7 downto 5)<= "101";
          cmd_get        <= '0';
          data_put       <= '0';
        when WAIT_COMPLETION =>
          led(7 downto 5)<= "101";
          cmd_get        <= '0';
          data_put       <= '0';
        when CHECK_FOR_READBACK =>
          led(7 downto 5)<= "101";
          cmd_get        <= '0';
          data_put       <= '0';
        when PREPARE_READBACK =>
          led(7 downto 5)<= "111";
          cmd_get        <= '0';
          data_put       <= '0';
        when DO_READBACK =>
          led(7 downto 5)<= "111";
          cmd_get        <= '0';
          data_put       <= '1';
        when PREPARE_SECOND_READBACK =>
          led(7 downto 5)<= "111";
          cmd_get        <= '0';
          data_put       <= '0';
        when DO_SECOND_READBACK =>
          led(7 downto 5)<= "111";
          cmd_get        <= '0';
          data_put       <= '1';
        when others =>
          led(7 downto 5)<= "000";
          cmd_get        <= '0';
          data_put       <= '0';
      end case;
  end process cmd_read_out_logic; 

  jtag_ctrl_mater_inst: JTAG_Ctrl_Master
    port map(
      CLK          => aclk,
      aresetn      => aresetn,
      period       => 32,
      BitCount     => jtag_bit_count,
      Shift_Strobe => jtag_shift_strobe,
      TDO          => TDO,
      TCK          => TCK,
      TMS          => TMS,
      TDI          => TDI,
      TRst         => TRST,
      Busy         => jtag_busy,
      StateStart   => jtag_state_start,
      StateEnd     => jtag_state_end,
      StateCurrent => jtag_state_current,
      Din          => jtag_di,
      Dout         => jtag_do
    );

  
  ODDR2_inst: P_ODDR2
  port map(
    aclk      => aclk, 
    clk_out   => clk_out,
    aresetn   => aresetn
  );

  -- LED outputs
  --led <= jtag_state_current;

end architecture beh;



