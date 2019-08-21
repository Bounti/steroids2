library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.inception_pkg.all;

USE std.textio.all;
use ieee.std_logic_textio.all;

entity ring_buffer is
generic (
  RAM_WIDTH : natural := 64;
  RAM_DEPTH : natural := 2
);
port (
    aclk    : in std_logic;
    aresetn : in std_logic;
 
    -- Entry port
    wr_en   : in std_logic;
    wr_data : in std_logic_vector(RAM_WIDTH - 1 downto 0);
 
    -- Read port
    dec     : in std_logic;
    rd_data : out std_logic_vector(RAM_WIDTH - 1 downto 0);
 
    -- Flags
    empty   : out std_logic;
    full    : out std_logic
 
    -- The number of elements in the FIFO
   -- counter : out integer range RAM_DEPTH - 1 downto 0
  );
end ring_buffer;

architecture beh of ring_buffer is

  type ram_type is array (RAM_DEPTH - 1 downto 0) of
    std_logic_vector(wr_data'range);
  signal ram : ram_type;

  signal empty_i : std_logic;
  signal full_i : std_logic;
  signal counter : integer range RAM_DEPTH - 1 downto 0;

begin

  empty   <= empty_i;
  full    <= full_i;
  --counter <= counter_i;
 
  empty_i <= '1' when counter = 0 else '0';
  full_i  <= '1' when counter >= RAM_DEPTH - 1 else '0';
  rd_data <= ram(counter-1) when ( counter >0 ) else std_logic_vector(to_unsigned(0, 64));
  
  rw: process(aclk)
  begin
    if(aclk'event and aclk='1') then
      if( aresetn = '0' ) then
       counter <= 0; 
      elsif( wr_en = '1' and full_i = '0' and counter <= RAM_DEPTH ) then
        ram(counter) <= wr_data;
        counter      <= counter + 1; 
      elsif( dec = '1' and empty_i = '0' and counter >= 0  ) then
        counter      <= counter - 1;
      end if;
    end if;
  end process rw;

end beh;
