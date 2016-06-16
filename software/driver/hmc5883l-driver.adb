-- I2Cdev library collection - HM5_883L I2C device class
-- Based on Honeywell HM5_883L datasheet, 102_010 (Form 900_405 Rev B)
-- 6/122_012 by Jeff Rowberg <jeff@rowberg.net>
-- Updates should (hopefully) always be available at https:--github.com/jrowberg/i2cdevlib
--
-- Changelog:
--    2_012-06-12 - fixed swapped Y/Z axes
--    2_011-08-22 - small Doxygen comment fixes
--    2_011-07-31 - initial release

-- ======================
--I2Cdev device library code is placed under the MIT license
--Copyright (c)2_012 Jeff Rowberg
--Permission is hereby granted, free of charge, to any person obtaining a copy
--of this software and associated documentation files (the "Software"), to deal
--in the Software without restriction, including without limitation the rights
--to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
--copies of the Software, and to permit persons to whom the Software is
--furnished to do so, subject to the following conditions:
--The above copyright notice and this permission notice shall be included in
--all copies or substantial portions of the Software.
--THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
--IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
--FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
--AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
--LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, FROM : ARISING,
--OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
--THE SOFTWARE.
--========================
--

with HM5883L.;
with HIL.I2C;


package body HMC5883L.Driver is


procedure writeByteToDevice(register : Unsigned_8; data : Unsigned_8) is 
begin




--* Power on and prepare for general usage.
-- This will prepare the magnetometer with default settings, ready for single-
-- use mode (very low power requirements). Default settings include 8-sample
-- averaging, 15 Hz data output rate, normal measurement bias, a,d1_090 gain (in
-- terms of LSB/Gauss). Be sure to adjust any settings you need specifically
-- after initialization, especially the gain settings if you happen to be seeing
-- a lot of 4_096 values (see the datasheet for mor information).
--
procedure initialize is
begin
    -- write CONFIG_A register
    I2Cdev.writeByte(devAddr, HMC5883L_RA_CONFIG_A,
        (HMC5883L_AVERAGING_8 << (HMC5883L_CRA_AVERAGE_BIT - HMC5883L_CRA_AVERAGE_LENGTH + 1)) or         (HMC5883L_RATE_15     << (HMC5883L_CRA_RATE_BIT - HMC5883L_CRA_RATE_LENGTH + 1)) or         (HMC5883L_BIAS_NORMAL << (HMC5883L_CRA_BIAS_BIT - HMC5883L_CRA_BIAS_LENGTH + 1)));

    -- write CONFIG_B register
    setGain(HMC5883L_GAIN_1090);
    
    -- write MODE register
    setMode(HMC5883L_MODE_SINGLE);
end initialize;

--* Verify the I2C connection.
-- Make sure the device is connected and responds as expected.
-- @return True if connection is valid, false otherwise
--
function testConnection return Boolean is
begin
    if I2Cdev.readBytes(devAddr, HMC5883L_RA_IDA, 3, buffer) = 3 then 
        return (buffer(0) = 'H' and then buffer(1) = '4' and then buffer(2) = '3');
    end if;
    return false;
end testConnection;

-- CONFIG_A register

--* Get number of samples averaged per measurement.
-- @return Current samples averaged per measurement (0-3 for 1/2/4/8 respectively)
-- @see HMC5883L_AVERAGING_8
-- @see HMC5883L_RA_CONFIG_A
-- @see HMC5883L_CRA_AVERAGE_BIT
-- @see HMC5883L_CRA_AVERAGE_LENGTH
--
function getSampleAveraging return Unsigned_8 is
begin
    I2Cdev.readBits(devAddr, HMC5883L_RA_CONFIG_A, HMC5883L_CRA_AVERAGE_BIT, HMC5883L_CRA_AVERAGE_LENGTH, buffer);
    return buffer(0);
end getSampleAveraging;
--* Set number of samples averaged per measurement.
-- @param averaging New samples averaged per measurement setting(0-3 for 1/2/4/8 respectively)
-- @see HMC5883L_RA_CONFIG_A
-- @see HMC5883L_CRA_AVERAGE_BIT
-- @see HMC5883L_CRA_AVERAGE_LENGTH
--
procedure setSampleAveraging(averaging : Unsigned_8) is
begin
    I2Cdev.writeBits(devAddr, HMC5883L_RA_CONFIG_A, HMC5883L_CRA_AVERAGE_BIT, HMC5883L_CRA_AVERAGE_LENGTH, averaging);
end setSampleAveraging;
--* Get data output rate value.
-- The Table below shows all selectable output rates in continuous measurement
-- mode. All three channels shall be measured within a given output rate. Other
-- output rates with maximum rate of 160 Hz can be achieved by monitoring DRDY
-- interrupt pin in single measurement mode.
--
-- Value or Typical Data Output Rate (Hz)
-- ------+------------------------------
-- 0     or 0.75
-- 1     or 1.5
-- 2     or 3
-- 3     or 7.5
-- 4     or 15 (Default)
-- 5     or 30
-- 6     or 75
-- 7     or Not used
--
-- @return Current rate of data output to registers
-- @see HMC5883L_RATE_15
-- @see HMC5883L_RA_CONFIG_A
-- @see HMC5883L_CRA_RATE_BIT
-- @see HMC5883L_CRA_RATE_LENGTH
--
function getDataRate return Unsigned_8 is
begin
    I2Cdev.readBits(devAddr, HMC5883L_RA_CONFIG_A, HMC5883L_CRA_RATE_BIT, HMC5883L_CRA_RATE_LENGTH, buffer);
    return buffer(0);
end getDataRate;
--* Set data output rate value.
-- @param rate Rate of data output to registers
-- @see getDataRate
-- @see HMC5883L_RATE_15
-- @see HMC5883L_RA_CONFIG_A
-- @see HMC5883L_CRA_RATE_BIT
-- @see HMC5883L_CRA_RATE_LENGTH
--
procedure setDataRate(rate : Unsigned_8) is
begin
    I2Cdev.writeBits(devAddr, HMC5883L_RA_CONFIG_A, HMC5883L_CRA_RATE_BIT, HMC5883L_CRA_RATE_LENGTH, rate);
end setDataRate;
--* Get measurement bias value.
-- @return Current bias value (0-2 for normal/positive/negative respectively)
-- @see HMC5883L_BIAS_NORMAL
-- @see HMC5883L_RA_CONFIG_A
-- @see HMC5883L_CRA_BIAS_BIT
-- @see HMC5883L_CRA_BIAS_LENGTH
--
function getMeasurementBias return Unsigned_8 is
begin
    I2Cdev.readBits(devAddr, HMC5883L_RA_CONFIG_A, HMC5883L_CRA_BIAS_BIT, HMC5883L_CRA_BIAS_LENGTH, buffer);
    return buffer(0);
end getMeasurementBias;
--* Set measurement bias value.
-- @param bias New bias value (0-2 for normal/positive/negative respectively)
-- @see HMC5883L_BIAS_NORMAL
-- @see HMC5883L_RA_CONFIG_A
-- @see HMC5883L_CRA_BIAS_BIT
-- @see HMC5883L_CRA_BIAS_LENGTH
--
procedure setMeasurementBias(bias : Unsigned_8) is
begin
    I2Cdev.writeBits(devAddr, HMC5883L_RA_CONFIG_A, HMC5883L_CRA_BIAS_BIT, HMC5883L_CRA_BIAS_LENGTH, bias);
end setMeasurementBias;

-- CONFIG_B register

--* Get magnetic field gain value.
-- The table below shows nominal gain settings. Use the "Gain" column to convert
-- counts to Gauss. Choose a lower gain value (higher GN#) when total field
-- strength causes overflow in one of the data output registers (saturation).
-- The data output range for all settings is 16#F800#-16#07FF# (2_048 -2_047).
--
-- Value or Field Range or Gain (LSB/Gauss)
-- ------+-------------+-----------------
-- 0     or +/- 0.88 Ga or1_370
-- 1     or +/- 1.3 Ga  or1_090 (Default)
-- 2     or +/- 1.9 Ga  or 820
-- 3     or +/- 2.5 Ga  or 660
-- 4     or +/- 4.0 Ga  or 440
-- 5     or +/- 4.7 Ga  or 390
-- 6     or +/- 5.6 Ga  or 330
-- 7     or +/- 8.1 Ga  or 230
--
-- @return Current magnetic field gain value
-- @see HMC5883L_GAIN_1090
-- @see HMC5883L_RA_CONFIG_B
-- @see HMC5883L_CRB_GAIN_BIT
-- @see HMC5883L_CRB_GAIN_LENGTH
--
function getGain return Unsigned_8 is
begin
    I2Cdev.readBits(devAddr, HMC5883L_RA_CONFIG_B, HMC5883L_CRB_GAIN_BIT, HMC5883L_CRB_GAIN_LENGTH, buffer);
    return buffer(0);
end getGain;
--* Set magnetic field gain value.
-- @param gain New magnetic field gain value
-- @see getGain
-- @see HMC5883L_RA_CONFIG_B
-- @see HMC5883L_CRB_GAIN_BIT
-- @see HMC5883L_CRB_GAIN_LENGTH
--
procedure setGain(gain : Unsigned_8) is
begin
    -- use this method to guarantee that bits 4-0 are set to zero, which is a
    -- requirement specified in the datasheet; it's actually more efficient than
    -- using the I2Cdev.writeBits method
    I2Cdev.writeByte(devAddr, HMC5883L_RA_CONFIG_B, gain << (HMC5883L_CRB_GAIN_BIT - HMC5883L_CRB_GAIN_LENGTH + 1));
end setGain;

-- MODE register

--* Get measurement mode.
-- In continuous-measurement mode, the device continuously performs measurements
-- and places the result in the data register. RDY goes high when new data is
-- placed in all three registers. After a power-on or a write to the mode or
-- configuration register, the first measurement set is available from all three
-- data output registers after a period of 2/fDO and subsequent measurements are
-- available at a frequency of fDO, where fDO is the frequency of data output.
--
-- When single-measurement mode (default) is selected, device performs a single
-- measurement, sets RDY high and returned to idle mode. Mode register returns
-- to idle mode bit values. The measurement remains in the data output register
-- and RDY remains high until the data output register is read or another
-- measurement is performed.
--
-- @return Current measurement mode
-- @see HMC5883L_MODE_CONTINUOUS
-- @see HMC5883L_MODE_SINGLE
-- @see HMC5883L_MODE_IDLE
-- @see HMC5883L_RA_MODE
-- @see HMC5883L_MODEREG_BIT
-- @see HMC5883L_MODEREG_LENGTH
--
function getMode return Unsigned_8 is
begin
    I2Cdev.readBits(devAddr, HMC5883L_RA_MODE, HMC5883L_MODEREG_BIT, HMC5883L_MODEREG_LENGTH, buffer);
    return buffer(0);
end getMode;
--* Set measurement mode.
-- @param newMode New measurement mode
-- @see getMode
-- @see HMC5883L_MODE_CONTINUOUS
-- @see HMC5883L_MODE_SINGLE
-- @see HMC5883L_MODE_IDLE
-- @see HMC5883L_RA_MODE
-- @see HMC5883L_MODEREG_BIT
-- @see HMC5883L_MODEREG_LENGTH
--
procedure setMode(newMode : Unsigned_8) is
begin
    -- use this method to guarantee that bits 7-2 are set to zero, which is a
    -- requirement specified in the datasheet; it's actually more efficient than
    -- using the I2Cdev.writeBits method
    I2Cdev.writeByte(devAddr, HMC5883L_RA_MODE, newMode << (HMC5883L_MODEREG_BIT - HMC5883L_MODEREG_LENGTH + 1));
    mode := newMode; -- track to tell if we have to clear bit 7 after a read
end setMode;

-- DATA* registers

--* Get 3-axis heading measurements.
-- In the event the ADC reading overflows or underflows for the given channel,
-- or if there is a math overflow during the bias measurement, this data
-- register will contain the value 4_096. This register value will clear when
-- after the next valid measurement is made. Note that this method automatically
-- clears the appropriate bit in the MODE register if Single mode is active.
-- @param x 16-bit signed integer container for X-axis heading
-- @param y 16-bit signed integer container for Y-axis heading
-- @param z 16-bit signed integer container for Z-axis heading
-- @see HMC5883L_RA_DATAX_H
--
procedure getHeading(Integer_16 *x; Integer_16 *y; Integer_16 *z) is
begin
    I2Cdev.readBytes(devAddr, HMC5883L_RA_DATAX_H, 6, buffer);
    if (mode = HMC5883L_MODE_SINGLE) I2Cdev.writeByte(devAddr, HMC5883L_RA_MODE, HMC5883L_MODE_SINGLE << (HMC5883L_MODEREG_BIT - HMC5883L_MODEREG_LENGTH + 1));
    *x := ((Integer_16buffer(0)) << 8) or buffer(1);
    *y := ((Integer_16buffer(4)) << 8) or buffer(5);
    *z := ((Integer_16buffer(2)) << 8) or buffer(3);
end getHeading;
--* Get X-axis heading measurement.
-- @return 16-bit signed integer with X-axis heading
-- @see HMC5883L_RA_DATAX_H
--
function getHeadingX return Integer_16 is
begin
    -- each axis read requires that ALL axis registers be read, even if only
    -- one is used; this was not done ineffiently in the code by accident
    I2Cdev.readBytes(devAddr, HMC5883L_RA_DATAX_H, 6, buffer);
    if (mode = HMC5883L_MODE_SINGLE) I2Cdev.writeByte(devAddr, HMC5883L_RA_MODE, HMC5883L_MODE_SINGLE << (HMC5883L_MODEREG_BIT - HMC5883L_MODEREG_LENGTH + 1));
    return ((Integer_16buffer(0)) << 8) or buffer(1);
end getHeadingX;
--* Get Y-axis heading measurement.
-- @return 16-bit signed integer with Y-axis heading
-- @see HMC5883L_RA_DATAY_H
--
function getHeadingY return Integer_16 is
begin
    -- each axis read requires that ALL axis registers be read, even if only
    -- one is used; this was not done ineffiently in the code by accident
    I2Cdev.readBytes(devAddr, HMC5883L_RA_DATAX_H, 6, buffer);
    if (mode = HMC5883L_MODE_SINGLE) I2Cdev.writeByte(devAddr, HMC5883L_RA_MODE, HMC5883L_MODE_SINGLE << (HMC5883L_MODEREG_BIT - HMC5883L_MODEREG_LENGTH + 1));
    return ((Integer_16buffer(4)) << 8) or buffer(5);
end getHeadingY;
--* Get Z-axis heading measurement.
-- @return 16-bit signed integer with Z-axis heading
-- @see HMC5883L_RA_DATAZ_H
--
function getHeadingZ return Integer_16 is
begin
    -- each axis read requires that ALL axis registers be read, even if only
    -- one is used; this was not done ineffiently in the code by accident
    I2Cdev.readBytes(devAddr, HMC5883L_RA_DATAX_H, 6, buffer);
    if (mode = HMC5883L_MODE_SINGLE) I2Cdev.writeByte(devAddr, HMC5883L_RA_MODE, HMC5883L_MODE_SINGLE << (HMC5883L_MODEREG_BIT - HMC5883L_MODEREG_LENGTH + 1));
    return ((Integer_16buffer(2)) << 8) or buffer(3);
end getHeadingZ;

-- STATUS register

--* Get data output register lock status.
-- This bit is set when this some but not all for of the six data output
-- registers have been read. When this bit is set, the six data output registers
-- are locked and any new data will not be placed in these register until one of
-- three conditions are met: one, all six bytes have been read or the mode
-- changed, two, the mode is changed, or three, the measurement configuration is
-- changed.
-- @return Data output register lock status
-- @see HMC5883L_RA_STATUS
-- @see HMC5883L_STATUS_LOCK_BIT
--
function getLockStatus return Boolean is
begin
    I2Cdev.readBit(devAddr, HMC5883L_RA_STATUS, HMC5883L_STATUS_LOCK_BIT, buffer);
    return buffer(0);
end getLockStatus;
--* Get data ready status.
-- This bit is set when data is written to all six data registers, and cleared
-- when the device initiates a write to the data output registers and after one
-- or more of the data output registers are written to. When RDY bit is clear it
-- shall remain cleared for 250 us. DRDY pin can be used as an alternative to
-- the status register for monitoring the device for measurement data.
-- @return Data ready status
-- @see HMC5883L_RA_STATUS
-- @see HMC5883L_STATUS_READY_BIT
--
function getReadyStatus return Boolean is
begin
    I2Cdev.readBit(devAddr, HMC5883L_RA_STATUS, HMC5883L_STATUS_READY_BIT, buffer);
    return buffer(0);
end getReadyStatus;

-- ID* registers

--* Get identification byte A
-- @return IDA byte (should be01_001_000, ASCII value 'H')
--
function getIDA return Unsigned_8 is
begin
    I2Cdev.readByte(devAddr, HMC5883L_RA_IDA, buffer);
    return buffer(0);
end getIDA;
--* Get identification byte B
-- @return IDA byte (should be00_110_100, ASCII value '4')
--
function getIDB return Unsigned_8 is
begin
    I2Cdev.readByte(devAddr, HMC5883L_RA_IDB, buffer);
    return buffer(0);
end getIDB;
--* Get identification byte C
-- @return IDA byte (should be00_110_011, ASCII value '3')
--
function getIDC return Unsigned_8 is
begin
    I2Cdev.readByte(devAddr, HMC5883L_RA_IDC, buffer);
    return buffer(0);
end getIDC;

end HMC5883L.Driver;