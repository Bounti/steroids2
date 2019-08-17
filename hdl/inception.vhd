library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.inception_pkg.all;

USE std.textio.all;
use ieee.std_logic_textio.all;

entity inception is
  Generic (
    PERIOD_RANGE    : natural := 63;
    BIT_COUNT_SIZE  : natural := 6;
    MAX_IO_REG_SIZE : natural := 43 
  );
  Port (
    aclk:       in std_logic;  -- Clock
    aresetn:    in std_logic;  -- Synchronous, active low, reset

    led:            out std_logic_vector(3 downto 0); -- LEDs
    jtag_state_led: out std_logic_vector(3 downto 0);

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
    clk_out    : out std_logic
  );
  end component;

  component ring_buffer is
  generic (
    RAM_WIDTH : natural := 64;
    RAM_DEPTH : natural := 2
  );
  port (
      aclk    : in std_logic;
      aresetn : in std_logic;
      wr_en   : in std_logic;
      wr_data : in std_logic_vector(RAM_WIDTH - 1 downto 0);
      dec     : in std_logic;
      rd_data : out std_logic_vector(RAM_WIDTH - 1 downto 0);
      empty   : out std_logic;
      full    : out std_logic
  );
  end component;

  type cmd_read_state_t is (RESET,IDLE,READ_START,READ_END,SAVE);
  signal cmd_read_state : cmd_read_state_t;
  
  signal jtag_do_buffer: std_logic_vector(MAX_IO_REG_SIZE - 1 downto 0);  
  type write_back_logic_state_t is (IDLE,WAIT_SEQ_COMPLETION,WRITE_BACK_PART1,WRITE_BACK_PART1_WAIT,WRITE_BACK_PART2);
  signal write_back_logic_state: write_back_logic_state_t;
  signal write_back_ready: std_logic;

  type jtag_st_t is (idle,idle2,read_cmd,read_addr,run_cmd,wait_cmd,write_back_h,write_back_l,done_cmd,done);
  type jtag_op_t is (read,read_irq,write,reset);
  type jtag_state_t is record
    st: jtag_st_t;
    op: jtag_op_t;
    step:   natural range 0 to NSTEPS_RST-1;
    size:   natural range 0 to 4;
    number: natural range 0 to 2**24-1;
    addr:   std_logic_vector(31 downto 0);
  end record;

  signal jtag_state : jtag_state_t;

  type usb_to_jtag_state_t is (RESET,IDLE,WAIT_JTAG,EXEC,DUTY_CYCLE);
  signal jtag_write_back   : std_logic;
  signal usb_to_jtag_state : usb_to_jtag_state_t;
  signal cmd_read_buffer : std_logic_vector(31 downto 0);
  signal cmd_cnt         : std_logic;

  signal cmd_empty,data_empty,irq_empty: std_logic;
  signal cmd_full,data_full,irq_full:   std_logic;
  signal cmd_put,data_put,irq_put:     std_logic;
  signal cmd_get,data_get,irq_get:     std_logic;
  signal cmd_din,data_din,irq_din:     std_logic_vector(31 downto 0);
  signal cmd_dout,data_dout,irq_dout:   std_logic_vector(31 downto 0);


  signal jtag_cmd_full, jtag_cmd_empty, jtag_cmd_dec, jtag_cmd_put: std_logic;
  signal jtag_cmd_din, jtag_cmd_dout: std_logic_vector(63 downto 0);

  signal cmd_done: std_logic;

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
  -- irq address --------------
  -----------------------------
  --irq_id_addr_proc: process(aclk)
  --begin
  --  if(aclk'event and aclk='1')then
  --    if(aresetn='0')then
  --      if(daisy_normal_n='1')then
  --        irq_id_addr <= IRQ_ID_ADDR_DEFAULT_STM32L152RE;
	--else
  --        irq_id_addr <= IRQ_ID_ADDR_DEFAULT_LPC1850;
	--end if;
  --    elsif(btn1_re='1')then
  --      irq_id_addr <= std_logic_vector(r);
  --    end if;
  --  end if;
  --end process irq_id_addr_proc;

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
	    if(cmd_done='1')then
	      irq_state <= done;
	    end if;
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
  cmd_fifo_inst : fifo_ram
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


  ring_buffer_inst: ring_buffer
    port map(
      aclk         => aclk,
      aresetn      => aresetn,
      wr_en        => jtag_cmd_put,
      wr_data      => jtag_cmd_din,
      dec          => jtag_cmd_dec,
      rd_data      => jtag_cmd_dout,  
      empty        => jtag_cmd_empty, 
      full         => jtag_cmd_full
    );
 
  -- This state machine read back TDO bits that are sent to 
  -- the data fifo and then forwarded to the FX3.
  -- We do not need to check if the fifo is full here as 
  -- the jtag state machine will not start a jtag command 
  -- if the fifo has not enough space. We need to backup 
  -- TDO as the jtag state machine does not wait for read 
  -- read back completion.
  write_back_logic: process(aclk)
  begin
    if( aclk'event and aclk = '1' ) then
      if( aresetn = '0' ) then
        write_back_logic_state <= IDLE;
        write_back_ready <= '0';
        data_put <= '0';
      else 
        case write_back_logic_state is
          when IDLE =>
            if( jtag_busy = '1' ) then
              write_back_logic_state <= WAIT_SEQ_COMPLETION;
              write_back_ready <= '0';
            end if;
            data_put <= '0';
          WHEN WAIT_SEQ_COMPLETION =>
            if( jtag_busy = '0' and jtag_write_back = '1' ) then
              -- Start first write back of tdo
              jtag_do_buffer <= jtag_do(MAX_IO_REG_SIZE-1 downto 0);
              write_back_logic_state <= WRITE_BACK_PART1; 
            elsif( jtag_busy = '0' and jtag_write_back = '0' ) then
              write_back_logic_state <= IDLE;
            end if;
          WHEN WRITE_BACK_PART1 =>
            data_din <= jtag_do_buffer(31 downto 0);
            data_put <= '1';
            write_back_logic_state <= WRITE_BACK_PART1_WAIT;
          WHEN WRITE_BACK_PART1_WAIT =>
            data_put <= '0';
            write_back_logic_state <= WRITE_BACK_PART2;
          WHEN WRITE_BACK_PART2 =>
            data_din <= "000000000000000000000"&jtag_do_buffer(MAX_IO_REG_SIZE-1 downto 32);
            data_put <= '1';
            write_back_logic_state <= IDLE;
            write_back_ready <= '1';
        end case;
      end if;
    end if;
  end process write_back_logic;

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
        cmd_read_state <= RESET;
      else 
          case cmd_read_state is
            when RESET =>
              cmd_read_state  <= IDLE;
            when IDLE =>
              if( cmd_empty = '0' and jtag_cmd_full = '0' ) then
                cmd_read_state <= READ_START;
              end if;
            when READ_START =>
              cmd_read_state <= READ_END;
            when READ_END   =>
              cmd_read_state <= SAVE;
            when SAVE =>
              cmd_read_state <= IDLE;
            when others =>
              cmd_read_state <= IDLE;
          end case;
      end if;
    end if;
  end process cmd_read_state_logic;

  -- cmd_read_out_logic set the outputs of the cmd_read_state_logic process
  cmd_read_out_logic: process(cmd_read_state)
  begin
      case cmd_read_state is
        when RESET =>
          cmd_get       <= '0';
          jtag_cmd_put  <= '0';
          cmd_cnt       <= '0';
        when IDLE =>
          jtag_cmd_put  <= '0';
          cmd_get       <= '0';
        when READ_START =>
          cmd_get <= '1';
        when READ_END =>
          cmd_get <= '0';
        when SAVE =>
          if( cmd_cnt = '0' ) then
            cmd_read_buffer <= cmd_dout;
            cmd_cnt         <= '1';
          else
            jtag_cmd_din <= cmd_dout&cmd_read_buffer;
            jtag_cmd_put <= '1';
            cmd_cnt      <= '0';
          end if;
          cmd_get                 <= '0';
        when others =>
          cmd_get      <= '0';
      end case;
  end process cmd_read_out_logic; 

  -- usb to jtag converter
  usb_to_jtag_state_logic: process(aclk)
  begin
    if( aclk'event and aclk = '1' ) then
      if( aresetn = '0' ) then
        usb_to_jtag_state    <= idle;
      else 
        case usb_to_jtag_state is
          when RESET        =>
            usb_to_jtag_state <= IDLE;
          when IDLE         =>
            if( jtag_cmd_empty = '0' and jtag_busy = '0' ) then
              usb_to_jtag_state <= EXEC;
            end if;
          when EXEC =>
            usb_to_jtag_state <= DUTY_CYCLE;
          when DUTY_CYCLE         =>
            usb_to_jtag_state   <= IDLE;
          when others       =>
            usb_to_jtag_state    <= IDLE;     
        end case;   
      end if;  
    end if;
  end process usb_to_jtag_state_logic;

  -- USB to JTAG converter
  usb_to_jtag_out_logic: process(usb_to_jtag_state)
  begin   
    case usb_to_jtag_state is
      when RESET     => 
          jtag_state_led      <= (others=> '0');
          jtag_state_start    <= TEST_LOGIC_RESET;
          jtag_bit_count      <= std_logic_vector(to_unsigned(0,BIT_COUNT_SIZE));
          jtag_state_end      <= TEST_LOGIC_RESET;
          jtag_di             <= std_logic_vector(to_unsigned(0,MAX_IO_REG_SIZE));
          jtag_write_back     <= '0'; 
          period              <= 1;
          jtag_shift_strobe   <= '0';
          jtag_cmd_dec        <= '0';
      when IDLE      =>
        jtag_state_led        <= "0001";
        jtag_cmd_dec          <= '0';
        jtag_shift_strobe     <= '0';
      when DUTY_CYCLE=>
        jtag_state_led        <= "0010";
        jtag_cmd_dec          <= '0';
      when EXEC      =>
        jtag_state_led        <= "0100";
        jtag_cmd_dec          <= '1';
        -- exec jtag command
        jtag_state_start      <= jtag_cmd_dout( 3 downto 0 );
        jtag_state_end        <= jtag_cmd_dout( 7 downto 4 );
        jtag_bit_count        <= jtag_cmd_dout( 13 downto 8 );
        period                <= to_integer(unsigned(jtag_cmd_dout( 19 downto 14)));
        jtag_di               <= jtag_cmd_dout( 62 downto 20);
        jtag_write_back       <= jtag_cmd_dout( 63 );
        --jtag_state_start      <= jtag_cmd_dout( STATE_START_END_OFFSET downto STATE_START_BEGIN_OFFSET );
        --jtag_state_end        <= jtag_cmd_dout( STATE_END_END_OFFSET downto STATE_END_BEGIN_OFFSET );
        --jtag_bit_count        <= jtag_cmd_dout( BITCOUNT_END_OFFSET downto BITCOUNT_BEGIN_OFFSET );
        --period                <= to_integer(unsigned(jtag_cmd_dout( PERIOD_END_OFFSET downto PERIOD_BEGIN_OFFSET)));
        --jtag_di               <= jtag_cmd_dout( PAYLOAD_END_OFFSET downto PAYLOAD_BEGIN_OFFSET);
        --jtag_write_back       <= jtag_cmd_dout( PAYLOAD_END_OFFSET+1 );
        jtag_shift_strobe     <= '1';
      when others =>
    end case;
  end process usb_to_jtag_out_logic;

  jtag_ctrl_mater_inst: JTAG_Ctrl_Master
    port map(
      CLK          => aclk,
      aresetn      => aresetn,
      --daisy_normal_n => daisy_normal_n,
      period       => period,
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
    clk_out   => clk_out
  );

  -- LED outputs
  led <= jtag_state_current;

end architecture beh;



