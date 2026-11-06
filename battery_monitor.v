// ============================================================
// Real-Time Battery Monitoring System
// Board: Digilent Basys 3 (Artix-7)
// HDL: Verilog
// Required Vivado IP: xadc_wiz_0 (XADC Wizard, DRP interface)
// ============================================================

module battery_monitor #(
    // Calibrate these values using your actual sensor circuit.
    // ACS712-5A sensitivity is typically 185 mV/A at the sensor.
    // With a 4:1 divider, effective sensitivity is about 46.25 mV/A.
    // At 1.0 V XADC full scale, this is about 189.5 ADC counts/A.
    parameter integer ACS_ZERO_RAW       = 2559,
    parameter integer ACS_COUNTS_PER_A   = 189,

    // 100 MHz clock: 200,000,000 cycles = 2 seconds
    parameter integer MODE_TICK_COUNT    = 200000000,

    // 100 MHz clock: 100,000 cycles = 1 ms per digit
    parameter integer SCAN_TICK_COUNT    = 100000
)(
    input  wire CLK100MHZ,
    input  wire btnC,

    // Basys 3 JXADC auxiliary inputs
    input  wire vauxp6,
    input  wire vauxn6,
    input  wire vauxp14,
    input  wire vauxn14,
    input  wire vauxp7,
    input  wire vauxn7,

    // Basys 3 four-digit common-anode display
    output reg  [6:0] seg,
    output reg        dp,
    output reg  [3:0] an
);

    // --------------------------------------------------------
    // XADC Wizard DRP interface
    // --------------------------------------------------------
    wire [15:0] adc_data;
    wire [4:0]  channel_out;
    wire        eoc_out;
    wire        drdy_out;
    wire        busy_out;

    reg  [6:0]  daddr;
    reg         den;
    reg  [15:0] di;
    reg         dwe;

    // Address associated with the DRP read request.
    reg [6:0] requested_address;

    // XADC channel IDs:
    // VAUX6  = 0x16
    // VAUX7  = 0x17
    // VAUX14 = 0x1E
    localparam [6:0] ADDR_VAUX6  = 7'h16;
    localparam [6:0] ADDR_VAUX7  = 7'h17;
    localparam [6:0] ADDR_VAUX14 = 7'h1E;

    reg [11:0] voltage_raw;
    reg [11:0] current_raw;
    reg [11:0] temperature_raw;

    // Display quantities:
    // voltage_tenths = voltage in 0.1 V units (e.g. 120 = 12.0 V)
    // current_centi  = current in 0.01 A units (e.g. 50 = 0.50 A)
    // temperature_C  = integer degrees Celsius
    reg [15:0] voltage_tenths;
    reg [15:0] current_centi;
    reg signed [15:0] temperature_C;

    xadc_wiz_0 xadc_inst (
        .dclk_in(CLK100MHZ),
        .reset_in(btnC),

        .vauxp6(vauxp6),
        .vauxn6(vauxn6),
        .vauxp14(vauxp14),
        .vauxn14(vauxn14),
        .vauxp7(vauxp7),
        .vauxn7(vauxn7),

        .vp_in(1'b0),
        .vn_in(1'b0),

        .daddr_in(daddr),
        .den_in(den),
        .di_in(di),
        .dwe_in(dwe),

        .do_out(adc_data),
        .channel_out(channel_out),
        .eoc_out(eoc_out),
        .drdy_out(drdy_out),
        .busy_out(busy_out)
    );

    // --------------------------------------------------------
    // XADC acquisition and sensor conversion
    // --------------------------------------------------------
    // XADC output data is left-justified; use bits [15:4].
    // The Wizard must be configured for continuous sequencing
    // with VAUX6, VAUX7 and VAUX14 enabled.
    //
    // Voltage circuit assumption: 12 V -> 1.0 V at XADC.
    // ACS712 assumption: 4:1 attenuator, zero-current output
    // near 2.5 V at sensor, yielding ~0.625 V at XADC.
    // TMP36 assumption: 2:1 attenuator before XADC.
    // --------------------------------------------------------

    always @(posedge CLK100MHZ or posedge btnC) begin
        if (btnC) begin
            daddr             <= 7'd0;
            den               <= 1'b0;
            di                <= 16'd0;
            dwe               <= 1'b0;
            requested_address <= 7'd0;

            voltage_raw       <= 12'd0;
            current_raw       <= 12'd0;
            temperature_raw   <= 12'd0;

            voltage_tenths    <= 16'd0;
            current_centi     <= 16'd0;
            temperature_C     <= 16'sd0;
        end else begin
            // DEN is a one-clock request pulse.
            den <= 1'b0;

            // EOC identifies the channel whose conversion has
            // completed. Request its data through the DRP port.
            if (eoc_out && !busy_out) begin
                daddr             <= {2'b00, channel_out};
                requested_address <= {2'b00, channel_out};
                den               <= 1'b1;
            end

            // DRDY indicates that the DRP read data is available.
            if (drdy_out) begin
                case (requested_address)
                    ADDR_VAUX6: begin
                        voltage_raw <= adc_data[15:4];

                        // 0..4095 represents 0..1.0 V at XADC.
                        // Sensor divider maps 0..12 V to 0..1 V.
                        // Result is tenths of a volt.
                        voltage_tenths <=
                            (adc_data[15:4] * 32'd120) / 32'd4095;
                    end

                    ADDR_VAUX14: begin
                        current_raw <= adc_data[15:4];

                        // Result is hundredths of an ampere.
                        // Signed difference permits readings below
                        // the calibrated zero-current offset.
                        if (adc_data[15:4] >= ACS_ZERO_RAW) begin
                            current_centi <=
                                ((adc_data[15:4] - ACS_ZERO_RAW) * 32'd100)
                                / ACS_COUNTS_PER_A;
                        end else begin
                            current_centi <= 16'd0;
                        end
                    end

                    ADDR_VAUX7: begin
                        temperature_raw <= adc_data[15:4];

                        // TMP36: Vout = 0.500 V + 0.010 V/°C.
                        // External 2:1 divider means sensor voltage
                        // is twice the voltage measured at XADC.
                        // Integer Celsius approximation.
                        temperature_C <=
                            $signed(
                                (((adc_data[15:4] * 32'd2000) / 32'd4095)
                                  - 32'd500) / 32'd10
                            );
                    end

                    default: begin
                        // Ignore other XADC channels.
                    end
                endcase
            end
        end
    end

    // --------------------------------------------------------
    // Select which parameter is shown
    // --------------------------------------------------------
    // Mode 0: U12.0 (voltage)
    // Mode 1: A0.50 (current)
    // Mode 2: C035  (temperature)
    // --------------------------------------------------------
    reg [1:0] display_mode;
    reg [31:0] mode_counter;

    always @(posedge CLK100MHZ or posedge btnC) begin
        if (btnC) begin
            mode_counter <= 32'd0;
            display_mode <= 2'd0;
        end else begin
            if (mode_counter >= MODE_TICK_COUNT - 1) begin
                mode_counter <= 32'd0;
                if (display_mode == 2'd2)
                    display_mode <= 2'd0;
                else
                    display_mode <= display_mode + 1'b1;
            end else begin
                mode_counter <= mode_counter + 1'b1;
            end
        end
    end

    reg [15:0] display_value;
    reg [3:0]  display_symbol;

    always @* begin
        display_value  = 16'd0;
        display_symbol = 4'd10; // U

        case (display_mode)
            2'd0: begin
                display_value  = voltage_tenths;
                display_symbol = 4'd10; // U
            end

            2'd1: begin
                display_value  = current_centi;
                display_symbol = 4'd11; // A
            end

            2'd2: begin
                if (temperature_C < 0)
                    display_value = 16'd0;
                else
                    display_value = temperature_C;
                display_symbol = 4'd12; // C
            end

            default: begin
                display_value  = 16'd0;
                display_symbol = 4'd10;
            end
        endcase
    end

    // --------------------------------------------------------
    // Seven-segment scan counter
    // --------------------------------------------------------
    reg [31:0] scan_counter;
    reg [1:0]  digit_select;

    always @(posedge CLK100MHZ or posedge btnC) begin
        if (btnC) begin
            scan_counter <= 32'd0;
            digit_select <= 2'd0;
        end else begin
            if (scan_counter >= SCAN_TICK_COUNT - 1) begin
                scan_counter <= 32'd0;
                digit_select <= digit_select + 1'b1;
            end else begin
                scan_counter <= scan_counter + 1'b1;
            end
        end
    end

    // --------------------------------------------------------
    // Decimal digit extraction and display decoding
    // --------------------------------------------------------
    reg [3:0] digit_value;
    reg [3:0] hundreds;
    reg [3:0] tens;
    reg [3:0] units;

    always @* begin
        hundreds = (display_value / 16'd100) % 16'd10;
        tens     = (display_value / 16'd10)  % 16'd10;
        units    = display_value % 16'd10;

        digit_value = 4'd0;
        seg = 7'b1111111; // all segments off (active low)
        an  = 4'b1111;    // all digits off (active low)
        dp  = 1'b1;       // decimal point off (active low)

        case (digit_select)
            // Rightmost digit: units
            2'b00: begin
                digit_value = units;
                an = 4'b1110;
            end

            // Second digit from right: tens
            2'b01: begin
                digit_value = tens;
                an = 4'b1101;

                // U12.0: decimal point after the 2
                if (display_mode == 2'd0)
                    dp = 1'b0;
            end

            // Third digit from right: hundreds
            2'b10: begin
                digit_value = hundreds;
                an = 4'b1011;

                // A0.50: decimal point after the first 0
                if (display_mode == 2'd1)
                    dp = 1'b0;
            end

            // Leftmost digit: parameter symbol
            2'b11: begin
                digit_value = display_symbol;
                an = 4'b0111;
            end
        endcase

        // Basys 3 common-anode display; segment outputs active low.
        // Bit order: {a,b,c,d,e,f,g}
        case (digit_value)
            4'd0:  seg = 7'b1000000;
            4'd1:  seg = 7'b1111001;
            4'd2:  seg = 7'b0100100;
            4'd3:  seg = 7'b0110000;
            4'd4:  seg = 7'b0011001;
            4'd5:  seg = 7'b0010010;
            4'd6:  seg = 7'b0000010;
            4'd7:  seg = 7'b1111000;
            4'd8:  seg = 7'b0000000;
            4'd9:  seg = 7'b0010000;
            4'd10: seg = 7'b1000001; // U approximation
            4'd11: seg = 7'b0001000; // A
            4'd12: seg = 7'b1000110; // C
            default: seg = 7'b1111111;
        endcase
    end

endmodule
