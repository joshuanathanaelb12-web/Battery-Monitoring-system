REAL-TIME BATTERY MONITORING SYSTEM - BASYS 3 ARTIX-7
======================================================

Contents
--------
1. battery_monitor.v       Top-level Verilog source
2. battery_monitor.xdc     Basys 3 pin constraints
3. README.txt              Setup, calibration and safety notes

IMPORTANT: This source requires an XADC Wizard IP instance named
"xadc_wiz_0". The IP is not a Verilog source file and must be generated
inside your Vivado project.

VIVADO XADC WIZARD SETUP
------------------------
Create an XADC Wizard IP named: xadc_wiz_0

Configure:
- Interface: DRP
- DCLK input: 100 MHz board clock (CLK100MHZ)
- Sequencer mode: Continuous Sequencer
- Enable auxiliary channels: VAUX6, VAUX7 and VAUX14
- Enable EOC, DRDY, BUSY, CHANNEL_OUT and DRP data/address signals
- VP/VN: unused
- Generate output products.

Check the generated IP's port names in its instantiation template.
If your Vivado version generates different port names, update the
instance in battery_monitor.v to match the generated template.

CHANNEL MAPPING
---------------
VAUX6  (channel ID 0x16): LM358 voltage sensor
VAUX7  (channel ID 0x17): TMP36 temperature sensor
VAUX14 (channel ID 0x1E): ACS712 current sensor

Basys 3 JXADC pins:
- XA1_P J3, XA1_N K3
- XA2_P L3, XA2_N M3
- XA3_P M2, XA3_N M1

SENSOR SCALING ASSUMPTIONS
--------------------------
Voltage:
- Condition the voltage sensor so 0-12 V maps to 0-1.0 V at XADC.
- Conversion assumes this exact 12:1 scaling.

ACS712 5A:
- Assumes 4:1 attenuation between ACS712 output and XADC.
- Assumes sensor zero-current output is near 2.5 V.
- Assumes nominal sensitivity is 185 mV/A at the sensor output.
- Initial effective XADC sensitivity is approximately 46.25 mV/A.
- Initial ACS_ZERO_RAW is 2559 and ACS_COUNTS_PER_A is 189.
- CALIBRATE ACS_ZERO_RAW with zero current and adjust sensitivity
  using a trusted ammeter. Sensor/module tolerances matter.

TMP36:
- Assumes a 2:1 divider between TMP36 output and XADC.
- TMP36 formula: Vout = 0.500 V + 0.010 V/degree C.
- The code compensates for the 2:1 divider.
- Do not connect the TMP36 output directly if it can exceed the
  XADC input range.

DISPLAY
-------
The display cycles approximately every 2 seconds:
- U12.0 = 12.0 volts
- A0.50 = 0.50 amperes
- C035  = 35 degrees Celsius

The readings above are examples only. Actual values depend on sensors,
conditioning circuits, calibration and hardware operation.

BUILD STEPS
-----------
1. Create a Vivado RTL project for the Basys 3 board.
2. Add battery_monitor.v as the top-level source.
3. Generate and add XADC Wizard IP named xadc_wiz_0.
4. Add battery_monitor.xdc as the constraints file.
5. Run Synthesis, Implementation and Generate Bitstream.
6. Program the Basys 3 board through Hardware Manager.
7. Verify sensor readings with a multimeter, ammeter and thermometer.

ELECTRICAL SAFETY
-----------------
- Basys 3 XADC auxiliary inputs must remain within the permitted
  analog input range (nominally 0 to 1.0 V for this configuration).
- Never connect 12 V directly to an FPGA pin.
- Never connect the raw 5 V ACS712 output directly to XADC.
- Use signal conditioning for ACS712 and TMP36 and verify the
  maximum output voltage before connecting the FPGA.
- Use a common reference ground as required by the XADC wiring.
- Check the board schematic and XADC user guide for analog input
  differential and common-mode requirements.
- Use a fuse and suitable wiring for the battery/lamp current.
- Test the analog front end before attaching the FPGA.

FUNCTIONAL LIMITATION
---------------------
This design acquires and displays voltage, current and temperature.
It does not disconnect the load or provide hardware protection.
Add separate protection circuitry and verified control logic if
automatic cutoff is required.

The source is a starting implementation. Simulate it, check the
generated XADC IP interface, and validate/calibrate it on hardware
before relying on measurements.
