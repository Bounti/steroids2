--
-- Copyright (C) Telecom ParisTech
--
-- This file must be used under the terms of the CeCILL. This source
-- file is licensed as described in the file COPYING, which you should
-- have received as part of this distribution. The terms are also
-- available at:
-- http://www.cecill.info/licences/Licence_CeCILL_V1.1-US.txt
--

-- See the README.md file for a detailed description of SAB4Z

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

USE std.textio.all;
use ieee.std_logic_textio.all;

entity inception_tb is
  procedure rand_int( variable seed1, seed2 : inout positive; min, max : in integer; result : out integer) is
    variable rand      : real;
    variable val_range : real;
  begin
    assert (max >= min) report "Rand_int: Range Error" severity Failure;

    uniform(seed1, seed2, rand);
    val_range := real(Max - Min + 1);
    result := integer( trunc(rand * val_range )) + min;
  end procedure;
end entity inception_tb;



architecture beh of inception_tb is

  component inception is
  Generic (
    PERIOD_RANGE    : natural := 63;
    BIT_COUNT_SIZE  : natural := 6;
    MAX_IO_REG_SIZE : natural := 64
  );
  Port (
    aclk:       in std_logic;  -- Clock
    aresetn:    in std_logic;  -- Synchronous, active low, reset

    led:            out std_logic_vector(7 downto 0); -- LEDs

    irq_in: in std_logic;
    irq_ack: out std_logic;
    ----------------------
    -- jtag ctrl master --
    ----------------------
   -- period          : in  natural range 1 to 31;
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
    slwrirq_rdy	   : in std_logic;
    slwr_rdy	   : in std_logic;
    slrd_rdy	   : in std_logic

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

    signal aclk:        std_logic;  -- Clock
    signal aresetn:     std_logic;  -- Synchronous, active low, reset

    signal led:             std_logic_vector(7 downto 0); -- LEDs

    signal irq_in, irq_ack:    std_logic;
    ----------------------
    -- jtag ctrl master --
    ----------------------
    signal TDO		    :   STD_LOGIC;
    signal TCK		    :   STD_LOGIC;
    signal TMS		    :   STD_LOGIC;
    signal TDI		    :   STD_LOGIC;
    signal TRST            :   STD_LOGIC;

    -----------------------
    -- slave fifo master --
    -----------------------
    signal clk_out	   :  std_logic;                               ---output clk 100 Mhz and 180 phase shift
    signal fdata          :  std_logic_vector(31 downto 0);
    signal sladdr         :  std_logic_vector(1 downto 0);
    signal sloe	   :  std_logic;                               ---output output enable select
    signal slop	   :  std_logic;                               ---output write select

    signal slwrirq_rdy	   :  std_logic;
    signal slwr_rdy	   :  std_logic;
    signal slrd_rdy	   :  std_logic;

    type fx3_state_t is (reset,idle,read,write);
    signal fx3_state: fx3_state_t;
    signal slop_d,sloe_d: std_logic;

    signal snd_get,snd_put,snd_empty,snd_full : std_logic;
    signal rcv_get,rcv_put_00,rcv_put_01,rcv_empty,rcv_full_00,rcv_full_01 : std_logic;
    signal snd_din,snd_dout,rcv_din,rcv_dout  : std_logic_vector(31 downto 0);
 begin

-- period <= 3; -- small value for simulation, for real code chose 15 so that jtag freq ~3MHz
 dut: inception
  port map(
    aclk => aclk,
    aresetn => aresetn,

    led => led,

    irq_in => irq_in,
    irq_ack => irq_ack,
    ----------------------
    -- jtag ctrl master --
    ----------------------
   -- period        => period,
    TDO		  => TDO,
    TCK		  => TCK,
    TMS		  => TMS,
    TDI		  => TDI,
    TRST   => TRST,

    -----------------------
    -- slave fifo master --
    -----------------------
    clk_out	=> clk_out,
    fdata   => fdata,
    sladdr  => sladdr,
    sloe	   => sloe,
    slop	   => slop,
    slwrirq_rdy       => slwrirq_rdy,
    slwr_rdy       => slwr_rdy,
    slrd_rdy       => slrd_rdy

  );

 slwrirq_rdy <= '0';

 aresetn <= '0', '1' after 15 ns;
 clk_proc: process
 begin
   aclk <= '1';
   wait for 5 ns;
   aclk <= '0';
   wait for 5 ns;
 end process;

 irq_in <= '0';
-- irq_gen_proc: process
-- begin
--   irq_loop: for i in 0 to 2 loop
--     irq_in <= '0';
--     wait for 457*10 ns;
--     irq_in <= '1';
--     wait until irq_ack = '1';
--   end loop irq_loop;
--   wait;
-- end process;

-- o_jtag_do_proc: process(TCK)
--   file output_file: text open write_mode is "./io/jtag_do.csv";
--   variable row: line;
--   variable cond2: std_logic;
--   variable cond1: std_logic;
--   begin
--     cond1 := '1' when work.inception_tb.dut.write_back_logic_state=WAIT_SEQ_COMPLETION else '0';  
--     cond2 := '1' when work.inception_tb.dut.write_back_logic_state=WRITE_BACK_PART2 else '0';  
--     if(TCK'event and TCK='1') then
--       write(row, time'image(work.inception_tb.dut.jtag_do));
--       writeline(output_file, row);
--     end if;
--   end process;

 o_csv_proc: process(TCK)
   file output_file: text open write_mode is "./io/data.csv";
   variable row: line;
   begin
     if(TCK'event and TCK='1') then
       write(row, time'image(now));
       write(row, string'(","));
       write(row, TDI, right, 1);
       write(row, string'(","));
       write(row, TMS, right, 1);
       write(row, string'(","));
       write(row, TCK, right, 1);
       write(row, string'(","));
       write(row, TDO, right, 1);
       writeline(output_file, row);
     end if;
   end process;

 o_proc: process(TCK)

    file output_fp: text open write_mode is "./io/output.txt";
    variable output_line: line;
    variable output_data: std_logic_vector(1 downto 0);
  begin

    if(TCK'event and TCK='1')then
      output_data := TMS&TDI;
      write(output_line,output_data);
      writeline(output_fp,output_line);
    end if;

  end process;

  jtag_slave_stub_proc: process(TCK)
    variable seed1, seed2 : positive := 1587437;
    variable input_int    : integer;
    variable loop_back_data: std_logic;
    variable round: std_logic := '0';
  begin
    rand_int(seed1, seed2,  0, 1, input_int);

    --TDO <= std_logic( to_unsigned( input_int, 1));

    if(TCK'event and TCK='1')then
      loop_back_data := TDI;
    elsif(TCK'event and TCK='0')then
      if( input_int = 1) then
        round := '0';
      else
        round := '1';
      end if;
      TDO <= round;
      --TDO <= loop_back_data;
    end if;

  end process;

  ----------------------------
  -- simulate the fx3 gpif2 --
  ----------------------------
  input_flop_proc: process(clk_out)
  begin
    if(clk_out'event and clk_out='1')then
      if(aresetn='0')then
        slop_d <= '0';
	sloe_d <= '0';
      else
        slop_d <= slop;
	sloe_d <= sloe;
      end if;
    end if;
  end process input_flop_proc;

  data_proc: process(aclk)
  begin
    if(aclk'event and aclk='1')then
      if(aresetn='0')then
        snd_get <= '0';
      elsif(slop='1' and sloe='1')then
        snd_get <= '1';
      else
        snd_get <= '0';
      end if;
    end if;
  end process data_proc;

  fdata <= snd_dout when sloe='1' and sladdr="11" else (others=>'Z');

  rcv_din <= fdata;
  rcv_put_00 <= '1' when (slop='1' and sloe='0' and sladdr="00") else '0';
  rcv_put_01 <= '1' when (slop='1' and sloe='0' and sladdr="01") else '0';

  slrd_rdy <= not snd_empty;
  slwr_rdy <= not rcv_full_00 when sladdr="00" else not rcv_full_01;

  fx3_proc: process(clk_out)
  begin
    if(clk_out'event and clk_out='1')then
      if(aresetn='0')then
        fx3_state <= reset;
      else
        case fx3_state is
	  when reset =>
	    fx3_state <= idle;
	  when idle =>
	    if(slop_d='1')then
	      if(sloe_d='1')then
	        fx3_state <= read;
	      else
	        fx3_state <= write;
	      end if;
	    end if;
	  when read =>
	    if(slop_d='0' or sloe_d='0')then
	      fx3_state <= idle;
	    end if;
	  when write =>
	    if(slop_d='0' and sloe_d='0')then
	      fx3_state <= idle;
	    end if;
	end case;
      end if;
    end if;
  end process fx3_proc;


  --------------------------------------------------------
  -- local fifo to store commands reveived from the host --
  --------------------------------------------------------
  snd_fifo_inst_11 : fifo_ram
    generic map(
      width => 32,
      addr_size => 4
    )
    port map(
      aclk => aclk,
      aresetn => aresetn,
      empty => snd_empty,
      full => snd_full,
      put => snd_put,
      get => snd_get,
      din => snd_din,
      dout => snd_dout
    );

  -------------------------------------------------------------
  -- local fifo to store data received from the fpga --
  -------------------------------------------------------------
  rcv_fifo_inst_00: fifo_ram
    generic map(
      width => 32,
      addr_size => 4
    )
    port map(
      aclk     => aclk,
      aresetn  => aresetn,
      empty    => rcv_empty,
      full     => rcv_full_00,
      put      => rcv_put_00,
      get      => rcv_get,
      din      => rcv_din,
      dout     => rcv_dout
    );

  -------------------------------------------------------------
  -- local fifo to store irq received from the fpga --
  -------------------------------------------------------------
  rcv_fifo_inst_01: fifo_ram
    generic map(
      width => 32,
      addr_size => 4
    )
    port map(
      aclk     => aclk,
      aresetn  => aresetn,
      empty    => rcv_empty,
      full     => rcv_full_01,
      put      => rcv_put_01,
      get      => rcv_get,
      din      => rcv_din,
      dout     => rcv_dout
    );

  --------------------------------------------------
  -- simulate host by taking commands from a file --
  --------------------------------------------------
  stub_input_proc: process
      file input_fp: text open read_mode is "./io/input.txt";
      variable input_line : line;
      variable input_data : std_logic_vector(31 downto 0);
    begin
        snd_gen_loop: while(endfile(input_fp) = false) loop
          snd_put <= '0';
          wait for 15 ns;
          if(snd_full='1')then
            wait until snd_full='0';
	          wait for 5 ns;
          end if;
          readline(input_fp,input_line);
          hread(input_line,input_data);
          snd_put <= '1';
          snd_din <= input_data;
          wait for 10 ns;
        end loop snd_gen_loop;
        snd_put <='0';
        wait;
    end process;

end architecture beh;


