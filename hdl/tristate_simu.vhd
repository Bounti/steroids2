library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.inception_pkg.all;
USE std.textio.all;
use ieee.std_logic_textio.all;

entity tristate is
port (
    fdata_in : out std_logic_vector(31 downto 0);
    fdata    : inout std_logic_vector(31 downto 0);
    fdata_out_d : in std_logic_vector(31 downto 0);
    tristate_en_n : in std_logic
  );
end tristate;

architecture GEN of tristate is

begin

  -- tristate buffer simulation
  -- tristate_sim_gen: generate
    fdata_in <= fdata;
    fdata <= (others=>'Z') when tristate_en_n='1' else fdata_out_d;
  -- end generate tristate_sim_gen;

end GEN;
