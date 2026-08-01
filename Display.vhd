library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Display -- multiplexed 4-digit 7-segment driver.
--
-- One digit is lit at a time; sweeping them faster than the eye can follow
-- makes all four appear on together. Segments are ACTIVE HIGH and the digit
-- select is one-hot ACTIVE HIGH, the convention validated on this board.
--
-- IT NOW TAKES BCD, NOT BINARY, AND THAT IS THE WHOLE POINT.
--
-- The previous version took a 13-bit binary value and converted it with
-- `mod 10`, `/10`, `/100` and `/1000` -- four combinational dividers on a
-- 13-bit operand. Measured: **2,184 cells, seven times the LCD controller and
-- the second largest block in the entire design**, spent on arithmetic.
--
-- The processor already knows how to divide: `__div` is a software routine
-- built from ADD, SUB, SHL, SHR and SLTU, and `print_dec3` in the game already
-- uses it to turn a number into decimal digits. So the conversion moves to
-- software, exactly as multiplication and division did, and this block goes
-- back to being what a display driver is: a sweep counter, a multiplexer and a
-- segment table. (The figure once quoted here for hardware MUL/DIV came from
-- the open-source estimator and was about 8x too large -- see
-- syn/VENDOR_VS_ESTIMATE.md. The reason for moving arithmetic into software is
-- the architecture, not the saving.)
--
-- Input is four BCD nibbles, most significant first:
--
--     digits(15 downto 12)  leftmost digit
--     digits(11 downto  8)
--     digits( 7 downto  4)
--     digits( 3 downto  0)  rightmost digit
--
-- A nibble of 15 is blank, so leading-zero suppression costs the software
-- nothing but a comparison. 10..14 are the hex glyphs A..E, used by the
-- bring-up debug readout.

entity Display is
	generic (
		-- Input clock; the sweep rate is derived from it rather than assumed.
		CLK_HZ : natural := 2_080_000;
		-- Digit step. ~360-400 Hz was the operator's measured sweet spot on
		-- this hardware; faster looked wrong.
		STEP_HZ : natural := 400
	);
	port(
		clk: in std_logic;
		reset: in std_logic := '0';
		digits: in std_logic_vector(15 downto 0);
		dmode: in std_logic := '1';
		DISPLAY_SELECTOR: out std_logic_vector(3 downto 0) := "1000";
		DISPLAY: out std_logic_vector(6 downto 0) := (others => '0')
	);
end Display;

architecture A_Display of Display is

	constant DIVIDE : natural := CLK_HZ / STEP_HZ;

	TYPE DIG_ARRAY IS ARRAY (NATURAL RANGE <>) OF STD_LOGIC_VECTOR(6 DOWNTO 0);
	-- Bit order is {g,f,e,d,c,b,a}: DISPLAY(0) is segment A. Sixteen entries,
	-- so no nibble value can index out of range.
	--
	-- 10..14 were blank and are now the hexadecimal glyphs A..E. Blanking them
	-- threw away the only readout this board has for a value that is not
	-- decimal, and the first time the processor misbehaved on silicon that was
	-- exactly what was needed.
	--
	-- 15 IS STILL BLANK, AND MUST STAY THAT WAY. sw/slots.s and sw/jitter.s both
	-- declare `BLANK = 15`, and jitter.s writes 0xFFFF to mean "no samples yet".
	-- Turning 15 into an F would have broken both programs silently -- they
	-- would still run and still write the same value, and the display would
	-- simply say something else. That is the cost of a display code being a
	-- software contract: it has to be changed as one.
	--
	-- F therefore has no glyph. Nothing needs one; the debug word in
	-- Top_Level_Unit is the only consumer of the hex range, and a blank digit
	-- there reads as "all four handshake signals asserted".
	--
	-- b and d are lower case because upper case B and D are indistinguishable
	-- from 8 and 0 on seven segments.
	CONSTANT ADIG : DIG_ARRAY(0 to 15) := (
		"0111111",   -- 0
		"0000110",   -- 1
		"1011011",   -- 2
		"1001111",   -- 3
		"1100110",   -- 4
		"1101101",   -- 5
		"1111101",   -- 6
		"0000111",   -- 7
		"1111111",   -- 8
		"1100111",   -- 9
		"1110111",   -- A
		"1111100",   -- b
		"0111001",   -- C
		"1011110",   -- d
		"1111001",   -- E
		"0000000"    -- 15: BLANK. A software contract -- see above.
	);

	signal sel     : std_logic_vector(3 downto 0) := "1000";
	signal counter : unsigned(31 downto 0) := (others => '0');
	signal tick    : std_logic := '0';
	signal nibble  : std_logic_vector(3 downto 0);
	signal pattern : std_logic_vector(6 downto 0);

begin

	-- Sweep prescaler.
	process(clk, reset)
	begin
		if reset = '1' then
			counter <= (others => '0');
			tick <= '0';
		elsif rising_edge(clk) then
			if counter = DIVIDE - 1 then
				counter <= (others => '0');
				tick <= '1';
			else
				counter <= counter + 1;
				tick <= '0';
			end if;
		end if;
	end process;

	-- Which digit is showing. One-hot, rotating right: 1000 -> 0100 -> 0010
	-- -> 0001 -> 1000, written as an explicit concatenation rather than a
	-- library rotate, because GHDL's synthesiser rejects a dynamic ROR on a
	-- bit_vector and the operator form is not portable anyway.
	process(clk, reset)
	begin
		if reset = '1' then
			sel <= "1000";
		elsif rising_edge(clk) then
			if tick = '1' then
				sel <= sel(0) & sel(3 downto 1);
			end if;
		end if;
	end process;

	-- Pick the nibble for the digit currently enabled. Selecting between four
	-- wires: no arithmetic.
	with sel select nibble <=
		digits(15 downto 12) when "1000",
		digits(11 downto  8) when "0100",
		digits( 7 downto  4) when "0010",
		digits( 3 downto  0) when "0001",
		"1111"               when others;

	pattern <= ADIG(to_integer(unsigned(nibble)));

	DISPLAY          <= pattern when dmode = '1' else not pattern;
	DISPLAY_SELECTOR <= sel;

end A_Display;

-- Made with my soul - Swately <3
