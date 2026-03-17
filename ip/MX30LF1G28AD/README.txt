/*
 * Security Level: Macronix Proprietary
 * COPYRIGHT (c) 2020 MACRONIX INTERNATIONAL CO., LTD
 * MX30-series verilog behavioral model
 *
 * This README file introduces verilog behavioral model of MX30-series.
 *
 * Filename   : README.txt
 * Issued Date: January 15, 2020
 *
 * Any questions or suggestions, please send emails to:
 *
 *     flash_model@mxic.com.tw
 */

 * Notice: All source files are saved as UNIX text format.

This README file introduces MXIC MX30-series verilog behavioral
model. It consists of several sections as follows:

1. Overview
2. Files
3. Usage

1. Overview
---------------------------------
The MX30-series verilog behavioral model is able to assist you to integrate
MX30-series flash product at early simulation stage. There are helpful tips
and notes in this README file. Please read before applying this behavioral
model.

2. Files
---------------------------------
The following files will be available after extracting the zipped file
(or other compression format):

  MX30XXXX\
    |- README.txt
    |- MX30XXXX.v


The naming rule of MX30-series verilog behavioral model is as follows:

  MX30XXXX.v:
      ---- -
       |   |--> v. Verilog source code.
       |
       |------> Flash's part name. Ex: MX30LF1G08AA.


  Flash part name description:

  BRAND TYPE VOLTAGE CLASSIFICATION DENSITY OPTION_CODE MODE GENERATION PACKAGE_TYPE OPERATING_TEMPERATURE RESERVE
  ----- ---- ------- -------------- ------- ----------- ---- ---------- ------------ --------------------- -------
    MX   30     L          F          1G        08        A      A      -    T                  I             X

                  BRAND: MX
                   TYPE: 30 - NAND Flash
                VOLATGE: L - 2.7V to 3.6V
         CLASSIFICATION: F - SLC + Large Block
                DENSITY: Mega-bits (Mb) or Giga-bit (Gb)
            OPTION_CODE: 08 - x8 and normal option
                   MODE: A - Die#:1, CE#:1, R/B#:1, Reserve:0
             GENERATION: A
           PACKAGE_TYPE: T - 48TSOP
                         XE - 0.8mm Ball Pitch, 0.4mm Ball Size (Reserved option)
  OPERATING_TEMPERATURE: C - Commercial 0~70C
                         I - Industrial -40~85C
                RESERVE: None


3. Usage
---------------------------------
The MX30-series behavioral model can be applied directly at the simulation
stage. Please connect correct wires to top module of this model according to
flash datasheet. This is not a synthesizable verilog code but for functional
simulation only. Please be careful with the following notes:

a. A behavioral model can load initial flash data from a file by parameter
   definition. You can change Init_File parameter with initial data's file
   name. Default file name is "none" and initial flash data is "FF".

   parameter  Init_File = "xxx";

   where xxx: initial flash data file name, default is "none".

b. Note that the behavioral model need to wait for power setup time, Tvcs.
   After Tvcs time, chip can be fully accessible.

c. The functions which used high voltage (Vhv) are not included in the
   behavioral model.

d. If define KGD product, the behavioral model will support good ID read in CFI
   read.

e. More than one value (min. typ. max. value) is defined for some AC parameters
   in the datasheet. But only one of them is selected in the behavioral model,
   e.g. program and erase cycle time is the typical value. For detailed
   information of the parameters, please refer to the datasheet and feel free
   to contact Macronix.

