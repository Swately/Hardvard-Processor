library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

entity Interfaz is
    port (
        clk, reset : in std_logic;
        id_icon : in std_logic_vector (0 to 3);
        rojo  : out std_logic_vector (0 to 7);
        verde : out std_logic_vector (0 to 7);
        azul  : out std_logic_vector (0 to 7);
        fila  : out std_logic_vector (0 to 7) 
    );
end entity;

architecture rtl of Interfaz is
    
    signal linea : std_logic_vector (0 to 2) := "000";
    signal vacio : std_logic_vector (0 to 7) := "00000000";
                            --moneda
    signal r01_1 : std_logic_vector (0 to 7) := "00111100";
    signal g01_1 : std_logic_vector (0 to 7) := "00111100";
    signal r01_2 : std_logic_vector (0 to 7) := "01111110";
    signal g01_2 : std_logic_vector (0 to 7) := "01111110";
    signal r01_3 : std_logic_vector (0 to 7) := "11100111";
    signal g01_3 : std_logic_vector (0 to 7) := "11100111";
    signal r01_4 : std_logic_vector (0 to 7) := "11101111";
    signal g01_4 : std_logic_vector (0 to 7) := "11101111";
    signal r01_5 : std_logic_vector (0 to 7) := "11110111";
    signal g01_5 : std_logic_vector (0 to 7) := "11110111";
    --repide 3, 2 y 1
                            --sandia
    signal g02_1 : std_logic_vector (0 to 7) := "00111100";
    signal g02_2 : std_logic_vector (0 to 7) := "01000010";
    signal g02_3 : std_logic_vector (0 to 7) := "10000001";
    signal r02_2 : std_logic_vector (0 to 7) := "00111100";
    signal r02_3 : std_logic_vector (0 to 7) := "01111110";
    
    --repite 3, 3, 3, 2 y 1
                            --corazon
    signal r03_2 : std_logic_vector (0 to 7) := "01101100";
    signal b03_2 : std_logic_vector (0 to 7) := "01101100";
    signal r03_3 : std_logic_vector (0 to 7) := "11111110";
    signal b03_3 : std_logic_vector (0 to 7) := "11111110";
    --repite 3 y 3
    signal r03_6 : std_logic_vector (0 to 7) := "01111100";
    signal b03_6 : std_logic_vector (0 to 7) := "01111100";
    signal r03_7 : std_logic_vector (0 to 7) := "00111000";
    signal b03_7 : std_logic_vector (0 to 7) := "00111000";
    signal r03_8 : std_logic_vector (0 to 7) := "00010000";
    signal b03_8 : std_logic_vector (0 to 7) := "00010000";
                            --pokeball
    signal b04_1 : std_logic_vector (0 to 7) := "00111100";
    signal b04_2 : std_logic_vector (0 to 7) := "01000010";
    signal b04_3 : std_logic_vector (0 to 7) := "10000001";
    signal b04_4 : std_logic_vector (0 to 7) := "11011011";
    signal b04_5 : std_logic_vector (0 to 7) := "11111111";
    --repetir b5
    signal b04_7 : std_logic_vector (0 to 7) := "01111110";
    --repetir b1
    signal r04_2 : std_logic_vector (0 to 7) := "00111100";
    signal r04_3 : std_logic_vector (0 to 7) := "01111110";
    signal r04_4 : std_logic_vector (0 to 7) := "00100100";
    signal r04_5 : std_logic_vector (0 to 7) := "01011010";
    signal r04_6 : std_logic_vector (0 to 7) := "01100110";
    --repite r2
    --en g repite r5, r6 y r7
                        --campana
    signal r05_2 : std_logic_vector (0 to 7) := "00010000";
    signal g05_2 : std_logic_vector (0 to 7) := "00010000";
    signal r05_3 : std_logic_vector (0 to 7) := "00111000";
    signal g05_3 : std_logic_vector (0 to 7) := "00111000";
    signal r05_4 : std_logic_vector (0 to 7) := "01111100";
    signal g05_4 : std_logic_vector (0 to 7) := "01111100";
    --repite 4
    signal r05_6 : std_logic_vector (0 to 7) := "11111110";
    signal g05_6 : std_logic_vector (0 to 7) := "11111110";
    signal r05_7 : std_logic_vector (0 to 7) := "10010010";
    signal g05_7 : std_logic_vector (0 to 7) := "10010010";
    --repite 5
                        --espada
    signal b06_2 : std_logic_vector (0 to 7) := "01100000";
    signal b06_3 : std_logic_vector (0 to 7) := "01110000";
    signal b06_4 : std_logic_vector (0 to 7) := "00111010";
    signal b06_5 : std_logic_vector (0 to 7) := "00011010";
    signal b06_6 : std_logic_vector (0 to 7) := "00000100";
    --repite b5 y b5
    signal r06_4 : std_logic_vector (0 to 7) := "00000010";
    --en r repite r4, b6 y b5
                        --siete
    signal r07_2 : std_logic_vector (0 to 7) := "00111100";
    signal r07_3 : std_logic_vector (0 to 7) := "00000100";
    signal r07_4 : std_logic_vector (0 to 7) := "00001000";
    --repite 4
    signal r07_6 : std_logic_vector (0 to 7) := "00010000";
    --repite 6
                        --craneo
    signal r08_1 : std_logic_vector (0 to 7) := "01111110";
    signal r08_2 : std_logic_vector (0 to 7) := "11111111";
    --repite 2
    signal r08_4 : std_logic_vector (0 to 7) := "10011001";
    --repite 4
    signal r08_6 : std_logic_vector (0 to 7) := "11100111";
    --repite 2
    signal r08_8 : std_logic_vector (0 to 7) := "01011010";
    
                        --win
    signal g09_1 : std_logic_vector (0 to 7) := "11111111";
    --vacio
    signal g09_3 : std_logic_vector (0 to 7) := "00000010";
    signal g09_4 : std_logic_vector (0 to 7) := "00000100";
    signal g09_5 : std_logic_vector (0 to 7) := "00101000";
    signal g09_6 : std_logic_vector (0 to 7) := "00010000";
    --repite vacio y 1
                        --fallo
    signal r10_1 : std_logic_vector (0 to 7) := "11111111";
    signal r10_2 : std_logic_vector (0 to 7) := "01000100";
    signal r10_3 : std_logic_vector (0 to 7) := "00101000";
    signal r10_4 : std_logic_vector (0 to 7) := "00010000";
    --repite 3, 2, 1 y 1
                        --espera
    signal r11 : std_logic_vector (0 to 7) := "10000000";
begin

    process(clk)
    begin
        if rising_edge(clk) then
            case linea is
                when "000" =>
                    fila <= "10000000";
                    case id_icon is
                        when "0000" =>
                            rojo <= r01_1;
                            verde <= g01_1;
                            azul <= vacio;
                        when "0001" =>
                            rojo <= vacio;
                            verde <= g02_1;
                            azul <= vacio;
                        when "0010" =>
                            rojo <= vacio;
                            verde <= vacio;
                            azul <= vacio;   
                        when "0011" =>
                            rojo <= vacio;
                            verde <= vacio;
                            azul <= b04_1;
                        when "0100" =>
                            rojo <= vacio;
                            verde <= vacio;
                            azul <= vacio;
                        when "0101" =>
                            rojo <= vacio;
                            verde <= vacio;
                            azul <= vacio;
                        when "0110" =>
                            rojo <= vacio;
                            verde <= vacio;
                            azul <= vacio;
                        when "0111" =>
                            rojo <= r08_1;
                            verde <= vacio;
                            azul <= vacio;
                        when "1000" =>
                            rojo <= vacio;
                            verde <= g09_1;
                            azul <= vacio;
                        when "1001" =>
                            rojo <= r10_1;
                            verde <= vacio;
                            azul <= vacio;
                        when "1010" =>
                            rojo <= vacio;
                            verde <= vacio;
                            azul <= vacio;
                        when others =>
                            rojo <= vacio;
                            verde <= vacio;
                            azul <= vacio;
                    end case;
                    linea <= "001";
                when "001" =>
                    fila <= "01000000";
                    case id_icon is
                        when "0000" =>
                            rojo <= r01_2;
                            verde <= g01_2;
                            azul <= vacio;
                        when "0001" =>
                            rojo <= r02_2;
                            verde <= g02_2;
                            azul <= vacio;
                        when "0010" =>
                            rojo <= r03_2;
                            verde <= vacio;
                            azul <= b03_2;   
                        when "0011" =>
                            rojo <= r04_2;
                            verde <= vacio;
                            azul <= b04_2;
                        when "0100" =>
                            rojo <= r05_2;
                            verde <= g05_2;
                            azul <= vacio;
                        when "0101" =>
                            rojo <= vacio;
                            verde <= vacio;
                            azul <= b06_2;
                        when "0110" =>
                            rojo <= r07_2;
                            verde <= vacio;
                            azul <= vacio;
                        when "0111" =>
                            rojo <= r08_2;
                            verde <= vacio;
                            azul <= vacio;
                        when "1000" =>
                            rojo <= vacio;
                            verde <= vacio;
                            azul <= vacio;
                        when "1001" =>
                            rojo <= r10_2;
                            verde <= vacio;
                            azul <= vacio;
                        when "1010" =>
                            rojo <= r11;
                            verde <= r11;
                            azul <= vacio;
                        when others =>
                            rojo <= vacio;
                            verde <= vacio;
                            azul <= vacio;
                    end case;
                    linea <= "010";
                when "010" =>
                    fila <= "00100000";
                    case id_icon is
                        when "0000" =>
                            rojo <= r01_3;
                            verde <= g01_3;
                            azul <= vacio;
                        when "0001" =>
                            rojo <= r02_3;
                            verde <= g02_3;
                            azul <= vacio;
                        when "0010" =>
                            rojo <= r03_3;
                            verde <= vacio;
                            azul <= b03_3;   
                        when "0011" =>
                            rojo <= r04_3;
                            verde <= vacio;
                            azul <= b04_3;
                        when "0100" =>
                            rojo <= r05_3;
                            verde <= g05_3;
                            azul <= vacio;
                        when "0101" =>
                            rojo <= vacio;
                            verde <= vacio;
                            azul <= b06_3;
                        when "0110" =>
                            rojo <= r07_3;
                            verde <= vacio;
                            azul <= vacio;
                        when "0111" =>
                            rojo <= r08_2;
                            verde <= vacio;
                            azul <= vacio;
                        when "1000" =>
                            rojo <= vacio;
                            verde <= g09_3;
                            azul <= vacio;
                        when "1001" =>
                            rojo <= r10_3;
                            verde <= vacio;
                            azul <= vacio;
                        when "1010" =>
                            rojo <= vacio;
                            verde <= vacio;
                            azul <= vacio;
                        when others =>
                            rojo <= vacio;
                            verde <= vacio;
                            azul <= vacio;
                    end case;
                    linea <= "011";
                when "011" =>
                    fila <= "00010000";
                    case id_icon is
                        when "0000" =>
                            rojo <= r01_4;
                            verde <= g01_4;
                            azul <= vacio;
                        when "0001" =>
                            rojo <= r02_3;
                            verde <= g02_3;
                            azul <= vacio;
                        when "0010" =>
                            rojo <= r03_3;
                            verde <= vacio;
                            azul <= b03_3;   
                        when "0011" =>
                            rojo <= r04_4;
                            verde <= vacio;
                            azul <= b04_4;
                        when "0100" =>
                            rojo <= r05_4;
                            verde <= g05_4;
                            azul <= vacio;
                        when "0101" =>
                            rojo <= r06_4;
                            verde <= vacio;
                            azul <= b06_4;
                        when "0110" =>
                            rojo <= r07_4;
                            verde <= vacio;
                            azul <= vacio;
                        when "0111" =>
                            rojo <= r08_4;
                            verde <= vacio;
                            azul <= vacio;
                        when "1000" =>
                            rojo <= vacio;
                            verde <= g09_4;
                            azul <= vacio;
                        when "1001" =>
                            rojo <= r10_4;
                            verde <= vacio;
                            azul <= vacio;
                        when "1100" =>
                            rojo <= r11;
                            verde <= r11;
                            azul <= vacio;
                        when others =>
                            rojo <= vacio;
                            verde <= vacio;
                            azul <= vacio;
                    end case;
                    linea <= "100";
                when "100" =>
                    fila <= "00001000";
                    case id_icon is
                        when "0000" =>
                            rojo <= r01_5;
                            verde <= g01_5;
                            azul <= vacio;
                        when "0001" =>
                            rojo <= r02_3;
                            verde <= g02_3;
                            azul <= vacio;
                        when "0010" =>
                            rojo <= r03_3;
                            verde <= vacio;
                            azul <= b03_3;   
                        when "0011" =>
                            rojo <= r04_5;
                            verde <= r04_5;
                            azul <= b04_5;
                        when "0100" =>
                            rojo <= r05_4;
                            verde <= g05_4;
                            azul <= vacio;
                        when "0101" =>
                            rojo <= r06_4;
                            verde <= vacio;
                            azul <= b06_5;
                        when "0110" =>
                            rojo <= r07_4;
                            verde <= vacio;
                            azul <= vacio;
                        when "0111" =>
                            rojo <= r08_4;
                            verde <= vacio;
                            azul <= vacio;
                        when "1000" =>
                            rojo <= vacio;
                            verde <= g09_5;
                            azul <= vacio;
                        when "1001" =>
                            rojo <= r10_3;
                            verde <= vacio;
                            azul <= vacio;
                        when "1010" =>
                            rojo <= vacio;
                            verde <= vacio;
                            azul <= vacio;
                        when others =>
                            rojo <= vacio;
                            verde <= vacio;
                            azul <= vacio;
                    end case;
                    linea <= "101";
                when "101" =>
                    fila <= "00000100";
                    case id_icon is
                        when "0000" =>
                            rojo <= r01_3;
                            verde <= g01_3;
                            azul <= vacio;
                        when "0001" =>
                            rojo <= r02_3;
                            verde <= g02_3;
                            azul <= vacio;
                        when "0010" =>
                            rojo <= r03_6;
                            verde <= vacio;
                            azul <= b03_6;   
                        when "0011" =>
                            rojo <= r04_6;
                            verde <= r04_6;
                            azul <= b04_5;
                        when "0100" =>
                            rojo <= r05_6;
                            verde <= g05_6;
                            azul <= vacio;
                        when "0101" =>
                            rojo <= b06_6;
                            verde <= vacio;
                            azul <= b06_6;
                        when "0110" =>
                            rojo <= r07_6;
                            verde <= vacio;
                            azul <= vacio;
                        when "0111" =>
                            rojo <= r08_6;
                            verde <= vacio;
                            azul <= vacio;
                        when "1000" =>
                            rojo <= vacio;
                            verde <= g09_6;
                            azul <= vacio;
                        when "1001" =>
                            rojo <= r10_2;
                            verde <= vacio;
                            azul <= vacio;
                        when "1010" =>
                            rojo <= r11;
                            verde <= r11;
                            azul <= vacio;
                        when others =>
                            rojo <= vacio;
                            verde <= vacio;
                            azul <= vacio;
                    end case;
                    linea <= "110";
                when "110" =>
                    fila <= "00000010";
                    case id_icon is
                        when "0000" =>
                            rojo <= r01_2;
                            verde <= g01_2;
                            azul <= vacio;
                        when "0001" =>
                            rojo <= r02_2;
                            verde <= g02_2;
                            azul <= vacio;
                        when "0010" =>
                            rojo <= r03_7;
                            verde <= vacio;
                            azul <= b03_7;   
                        when "0011" =>
                            rojo <= r04_2;
                            verde <= r04_2;
                            azul <= b04_7;
                        when "0100" =>
                            rojo <= r05_7;
                            verde <= g05_7;
                            azul <= vacio;
                        when "0101" =>
                            rojo <= b06_5;
                            verde <= vacio;
                            azul <= b06_5;
                        when "0110" =>
                            rojo <= r07_6;
                            verde <= vacio;
                            azul <= vacio;
                        when "0111" =>
                            rojo <= r08_2;
                            verde <= vacio;
                            azul <= vacio;
                        when "1000" =>
                            rojo <= vacio;
                            verde <= vacio;
                            azul <= vacio;
                        when "1001" =>
                            rojo <= r10_1;
                            verde <= vacio;
                            azul <= vacio;
                        when "1010" =>
                            rojo <= vacio;
                            verde <= vacio;
                            azul <= vacio;
                        when others =>
                            rojo <= vacio;
                            verde <= vacio;
                            azul <= vacio;
                    end case;
                    linea <= "111";
                when "111" =>
                    fila <= "00000001";
                    case id_icon is
                        when "0000" =>
                            rojo <= r01_1;
                            verde <= g01_1;
                            azul <= vacio;
                        when "0001" =>
                            rojo <= vacio;
                            verde <= g02_1;
                            azul <= vacio;
                        when "0010" =>
                            rojo <= r03_8;
                            verde <= vacio;
                            azul <= b03_8;   
                        when "0011" =>
                            rojo <= vacio;
                            verde <= vacio;
                            azul <= b04_1;
                        when "0100" =>
                            rojo <= r05_4;
                            verde <= g05_4;
                            azul <= vacio;
                        when "0101" =>
                            rojo <= b06_5;
                            verde <= vacio;
                            azul <= b06_5;
                        when "0110" =>
                            rojo <= vacio;
                            verde <= vacio;
                            azul <= vacio;
                        when "0111" =>
                            rojo <= r08_8;
                            verde <= vacio;
                            azul <= vacio;
                        when "1000" =>
                            rojo <= vacio;
                            verde <= g09_1;
                            azul <= vacio;
                        when "1001" =>
                            rojo <= r10_1;
                            verde <= vacio;
                            azul <= vacio;
                        when "1010" =>
                            rojo <= vacio;
                            verde <= vacio;
                            azul <= vacio;
                        when others =>
                            rojo <= vacio;
                            verde <= vacio;
                            azul <= vacio;
                    end case;
                    linea <= "000";
                when others =>
                    null;
            end case;
        end if;
    end process;    

end architecture;
