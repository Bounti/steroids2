library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.inception_pkg.all;
USE std.textio.all;
use ieee.std_logic_textio.all;

library UNISIM;
use UNISIM.vcomponents.all;

entity tristate is
port (
    fdata_in : out std_logic_vector(31 downto 0);
    fdata    : inout std_logic_vector(31 downto 0);
    fdata_out_d : in std_logic_vector(31 downto 0);
    tristate_en_n : in std_logic
  );
end tristate;

architecture beh of tristate is

begin

  -- tristate buffer synthesis on Xilinx Zedboard
  --tristate_syn_gen: generate
  tristate_gen_loop: for i in 0 to 31 generate
    tristate_buf_i : IOBUF
      port map (
        O     => fdata_in(i),
        IO    => fdata(i),
        I     => fdata_out_d(i),
        T     => tristate_en_n
      );
  end generate tristate_gen_loop;
  --end generate;

end beh;

