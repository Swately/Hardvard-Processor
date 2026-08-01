library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- LCD_Controller
--
-- HD44780 character-LCD driver, 8-bit parallel interface, write only.
--
-- Why this is hardware and not a subroutine: the HD44780 power-on sequence is
-- specified in milliseconds (15 ms, then 4.1 ms, then 100 us) and every write
-- needs an E pulse of at least 450 ns followed by a 37 us execution wait.
-- PHarvard retires an instruction every 20.3 clock cycles (measured), so a
-- software driver would have to spin thousands of instructions per character
-- and the timing would silently change with the CPU clock. The peripheral owns
-- the timing; the CPU just writes bytes.
--
-- RW is tied LOW: the controller never reads the busy flag, it waits by the
-- datasheet timings instead. That costs a little speed and saves the bus
-- turnaround plus a level-shifter hazard on a 5 V display.
--
-- Interface: assert wr_en for one clock with wr_rs/wr_data valid. The write is
-- accepted only when busy = '0'. `ready` rises once the power-on
-- initialisation has finished and stays high.
--
--   wr_rs = '0' -> the byte is a COMMAND (clear, set address, ...)
--   wr_rs = '1' -> the byte is DATA (a character, or a CGRAM row)

entity LCD_Controller is
    generic (
        -- Clock feeding this controller. All timing below is derived from it,
        -- so changing the system clock cannot silently break the display.
        CLK_HZ : natural := 2_080_000
    );
    port (
        clk     : in  std_logic;
        reset   : in  std_logic;

        -- command interface toward the CPU / a hard-coded writer
        wr_en   : in  std_logic;
        wr_rs   : in  std_logic;
        wr_data : in  std_logic_vector(7 downto 0);
        busy    : out std_logic;
        ready   : out std_logic;

        -- HD44780 pins
        lcd_rs  : out std_logic;
        lcd_rw  : out std_logic;
        lcd_e   : out std_logic;
        lcd_d   : out std_logic_vector(7 downto 0)
    );
end LCD_Controller;

architecture A_LCD_Controller of LCD_Controller is

    -- Cycle arithmetic in kHz keeps the products inside a 32-bit integer:
    -- 15000 us * 2080 kHz = 31,200,000, whereas nanoseconds times hertz would
    -- overflow.
    constant CLK_KHZ : natural := CLK_HZ / 1000;

    function us_cycles(us : natural) return natural is
        variable c : natural;
    begin
        c := (us * CLK_KHZ + 999) / 1000;   -- round up, never short
        if c < 1 then
            return 1;
        end if;
        return c;
    end function;

    -- E high for 1 us covers the 450 ns minimum at any clock this is used with.
    constant E_HIGH_CYCLES : natural := us_cycles(1);
    constant SETUP_CYCLES  : natural := us_cycles(1);   -- >= 140 ns address setup
    constant POWER_CYCLES  : natural := us_cycles(15_000);

    type init_step_t is record
        data    : std_logic_vector(7 downto 0);
        wait_us : natural;
    end record;
    type init_rom_t is array (natural range <>) of init_step_t;

    -- Datasheet power-on sequence for the 8-bit interface. Every one of these
    -- is a command (RS = 0).
    constant INIT_ROM : init_rom_t := (
        (X"30", 4_100),   -- function set, 8-bit          (wait > 4.1 ms)
        (X"30",   100),   -- function set, 8-bit          (wait > 100 us)
        (X"30",   100),   -- function set, 8-bit
        (X"38",    40),   -- function set: 8-bit, 2 lines, 5x8 font
        (X"08",    40),   -- display off
        (X"01", 1_600),   -- clear display                (takes 1.52 ms)
        (X"06",    40),   -- entry mode: increment, no display shift
        (X"0C",    40)    -- display on, cursor off, blink off
    );

    type state_t is (st_power, st_init_next, st_setup, st_ehigh, st_elow,
                     st_wait, st_idle);
    signal state : state_t := st_power;

    signal init_index : natural range 0 to INIT_ROM'length := 0;
    signal in_init    : std_logic := '1';

    signal counter    : natural range 0 to POWER_CYCLES := 0;
    signal wait_target: natural range 0 to POWER_CYCLES := 0;

    signal cur_rs   : std_logic := '0';
    signal cur_data : std_logic_vector(7 downto 0) := (others => '0');

    signal internal_e     : std_logic := '0';
    signal internal_ready : std_logic := '0';

begin

    -- Write only: the busy flag is never read back, so RW is parked low.
    lcd_rw <= '0';
    lcd_rs <= cur_rs;
    lcd_d  <= cur_data;
    lcd_e  <= internal_e;

    busy  <= '0' when (state = st_idle and in_init = '0') else '1';
    ready <= internal_ready;

    process(clk, reset)
    begin
        if reset = '1' then
            state          <= st_power;
            init_index     <= 0;
            in_init        <= '1';
            counter        <= 0;
            wait_target    <= POWER_CYCLES;
            cur_rs         <= '0';
            cur_data       <= (others => '0');
            internal_e     <= '0';
            internal_ready <= '0';

        elsif rising_edge(clk) then

            case state is

                -- The display needs its own power-on time before it will accept
                -- anything at all. Skipping this is the classic reason an
                -- HD44780 comes up showing a row of black blocks.
                when st_power =>
                    if counter >= POWER_CYCLES - 1 then
                        counter    <= 0;
                        init_index <= 0;
                        state      <= st_init_next;
                    else
                        counter <= counter + 1;
                    end if;

                when st_init_next =>
                    if init_index = INIT_ROM'length then
                        in_init        <= '0';
                        internal_ready <= '1';
                        state          <= st_idle;
                    else
                        cur_rs      <= '0';
                        cur_data    <= INIT_ROM(init_index).data;
                        wait_target <= us_cycles(INIT_ROM(init_index).wait_us);
                        counter     <= 0;
                        state       <= st_setup;
                    end if;

                when st_idle =>
                    internal_e <= '0';
                    if wr_en = '1' then
                        cur_rs   <= wr_rs;
                        cur_data <= wr_data;
                        -- Clear (0x01) and Home (0x02) are the slow commands.
                        if wr_rs = '0' and
                           (wr_data = X"01" or wr_data = X"02") then
                            wait_target <= us_cycles(1_600);
                        else
                            wait_target <= us_cycles(40);
                        end if;
                        counter <= 0;
                        state   <= st_setup;
                    end if;

                -- RS and the data bus settle before E rises.
                when st_setup =>
                    internal_e <= '0';
                    if counter >= SETUP_CYCLES - 1 then
                        counter <= 0;
                        state   <= st_ehigh;
                    else
                        counter <= counter + 1;
                    end if;

                when st_ehigh =>
                    internal_e <= '1';
                    if counter >= E_HIGH_CYCLES - 1 then
                        counter <= 0;
                        state   <= st_elow;
                    else
                        counter <= counter + 1;
                    end if;

                -- The display latches on the FALLING edge of E.
                when st_elow =>
                    internal_e <= '0';
                    counter    <= 0;
                    state      <= st_wait;

                when st_wait =>
                    if counter >= wait_target - 1 then
                        counter <= 0;
                        if in_init = '1' then
                            init_index <= init_index + 1;
                            state      <= st_init_next;
                        else
                            state <= st_idle;
                        end if;
                    else
                        counter <= counter + 1;
                    end if;

            end case;
        end if;
    end process;

end A_LCD_Controller;

-- Made with my soul - Swately <3
