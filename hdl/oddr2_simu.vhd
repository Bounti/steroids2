library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.inception_pkg.all;
USE std.textio.all;
use ieee.std_logic_textio.all;

entity P_ODDR2 is
port (
    aclk       : in std_logic;
    aclkn      : out std_logic;
    clk_out    : out std_logic
);
end P_ODDR2;

architecture beh of P_ODDR2 is

begin

  oddr2_proc: process(aclk)
  begin
    if(aclk'event and aclk='1')then
      clk_out <= '0';
    elsif(aclk'event and aclk='0')then
      clk_out <= '1';
    end if;
  end process oddr2_proc;

end beh;

