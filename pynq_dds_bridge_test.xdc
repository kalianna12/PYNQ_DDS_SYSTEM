## PYNQDDS bridge test: UART + SPI slave from PYNQADC + verified AD9767 DDS output

set_property PACKAGE_PIN H16 [get_ports clk_125m]
set_property IOSTANDARD LVCMOS33 [get_ports clk_125m]
create_clock -period 8.000 -name clk_125m [get_ports clk_125m]

## Reset button BTN0
set_property PACKAGE_PIN D19 [get_ports rst_btn]
set_property IOSTANDARD LVCMOS33 [get_ports rst_btn]

## UART via PmodB P1/P2, same as previously verified DDS test
set_property PACKAGE_PIN W14 [get_ports uart_tx]
set_property IOSTANDARD LVCMOS33 [get_ports uart_tx]

set_property PACKAGE_PIN Y14 [get_ports uart_rx]
set_property IOSTANDARD LVCMOS33 [get_ports uart_rx]
set_property PULLUP true [get_ports uart_rx]

## LEDs
set_property PACKAGE_PIN R14 [get_ports led0]
set_property IOSTANDARD LVCMOS33 [get_ports led0]

set_property PACKAGE_PIN P14 [get_ports led1]
set_property IOSTANDARD LVCMOS33 [get_ports led1]

set_property PACKAGE_PIN N16 [get_ports led2]
set_property IOSTANDARD LVCMOS33 [get_ports led2]

set_property PACKAGE_PIN M14 [get_ports led3]
set_property IOSTANDARD LVCMOS33 [get_ports led3]

## SPI slave from PYNQADC using PmodB P7-P10
## PYNQDDS side directions: MOSI/SCLK/CS are inputs, MISO is output
set_property PACKAGE_PIN V16 [get_ports adc_spi_mosi]
set_property IOSTANDARD LVCMOS33 [get_ports adc_spi_mosi]

set_property PACKAGE_PIN W16 [get_ports adc_spi_miso]
set_property IOSTANDARD LVCMOS33 [get_ports adc_spi_miso]

set_property PACKAGE_PIN V12 [get_ports adc_spi_sclk]
set_property IOSTANDARD LVCMOS33 [get_ports adc_spi_sclk]

set_property PACKAGE_PIN W13 [get_ports adc_spi_cs_n]
set_property IOSTANDARD LVCMOS33 [get_ports adc_spi_cs_n]
set_property PULLUP true [get_ports adc_spi_cs_n]

## Verified AD9767 DAC P1 / CH1 mapping from the current DDS project
set_property PACKAGE_PIN W18 [get_ports {dac_data[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {dac_data[0]}]

set_property PACKAGE_PIN W19 [get_ports {dac_data[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {dac_data[1]}]

set_property PACKAGE_PIN Y18 [get_ports {dac_data[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {dac_data[2]}]

set_property PACKAGE_PIN V6 [get_ports {dac_data[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {dac_data[3]}]

set_property PACKAGE_PIN Y6 [get_ports {dac_data[4]}]
set_property IOSTANDARD LVCMOS33 [get_ports {dac_data[4]}]

set_property PACKAGE_PIN U7 [get_ports {dac_data[5]}]
set_property IOSTANDARD LVCMOS33 [get_ports {dac_data[5]}]

set_property PACKAGE_PIN C20 [get_ports {dac_data[6]}]
set_property IOSTANDARD LVCMOS33 [get_ports {dac_data[6]}]

set_property PACKAGE_PIN V7 [get_ports {dac_data[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {dac_data[7]}]

set_property PACKAGE_PIN U8 [get_ports {dac_data[8]}]
set_property IOSTANDARD LVCMOS33 [get_ports {dac_data[8]}]

set_property PACKAGE_PIN W6 [get_ports {dac_data[9]}]
set_property IOSTANDARD LVCMOS33 [get_ports {dac_data[9]}]

set_property PACKAGE_PIN Y16 [get_ports {dac_data[10]}]
set_property IOSTANDARD LVCMOS33 [get_ports {dac_data[10]}]

set_property PACKAGE_PIN V8 [get_ports {dac_data[11]}]
set_property IOSTANDARD LVCMOS33 [get_ports {dac_data[11]}]

set_property PACKAGE_PIN V10 [get_ports {dac_data[12]}]
set_property IOSTANDARD LVCMOS33 [get_ports {dac_data[12]}]

set_property PACKAGE_PIN W9 [get_ports {dac_data[13]}]
set_property IOSTANDARD LVCMOS33 [get_ports {dac_data[13]}]

set_property PACKAGE_PIN W8 [get_ports dac_clk]
set_property IOSTANDARD LVCMOS33 [get_ports dac_clk]

set_property PACKAGE_PIN Y8 [get_ports dac_wrt]
set_property IOSTANDARD LVCMOS33 [get_ports dac_wrt]
