// *==============================================================================================
// *
// *   MX30LF1G28AD.v - 1G-BIT CMOS Flash Memory
// *
// *           COPYRIGHT 2020 Macronix International Co., Ltd.
// *
// * Security Level: Macronix Proprietary
// *----------------------------------------------------------------------------------------------
// * Environment  : Cadence NC-Verilog
// * Reference Doc: MX30LF1G28AD REV.1.1,JAN.02,2020
// * Creation Date: @(#)$Date: 2020/01/13 07:25:04 $
// * Version      : @(#)$Revision: 1.5 $
// * Description  : There is only one module in this file
// *                module MX30LF1G28AD -> behavior model for the 1G-Bit flash
// *----------------------------------------------------------------------------------------------
// * Note 1:model can load initial flash data from file when parameter Init_File = "xxx" was defined; 
// *        xxx: initial flash data file name;default value xxx = "none", initial flash data is "FF".
// * Note 2:power setup time is Tvcs = 5_000_000 ns, so after power up, chip can be enable.
// * Note 3:more than one values (min. typ. max. value) are defined for some AC parameters in the
// *        datasheet, but only one of them is selected in the behavior model. For the detailed
// *        information of the parameters, please refer to datasheet and contact with Macronix.
// * Note 4:If you have any question and suggestion, please send your mail to following email address :
// *                                    flash_model@mxic.com.tw
// *----------------------------------------------------------------------------------------------

// *==============================================================================================
// * timescale define
// *==============================================================================================
`timescale 1ns / 100ps

`define         VOTP_Protect    1'b0  // 1'b0: OTP Array unprotect during power-on, 1'b1: protect
`define         VERE_status     8'h01 // ERE status bit value
`define         VCRC1           8'h00 // Integrity CRC, set at test
`define         VCRC2           8'h00 // Integrity CRC, set at test

module MX30LF1G28AD      (       CE_B,
                                RE_B,
                                WE_B,
                                CLE,
                                ALE,
                                WP_B,
                                RYBY_B,
                                PT,
                                IO      );

parameter       Init_File       = "none";
parameter       IO_MSB          = 7;
parameter       A_MSB           = ( IO_MSB == 7 ) ? 27 : ( 27 - 1 );
parameter       CA_MSB          = ( IO_MSB == 7 ) ? 11 : ( 11 - 1 );
parameter       CA_SPA          = ( IO_MSB == 7 ) ? 6 : ( 6 - 1 );
parameter       MSB_PA_IN_BLOCK = 5; // Highest page address within one block

// *==============================================================================================
// * Declaration of ports (input, output, inout)
// *==============================================================================================
input   CE_B;           // Chip enable, low active
input   RE_B;           // Output enable, low active
input   WE_B;           // Write enable, low active
input   WP_B;           // Protect enable, low active
input   CLE;            // Command latch enable, high active
input   ALE;            // Address latch enable, high active
inout   [IO_MSB:0] IO;  // Bidirectional Data bus
output  RYBY_B;         // Ready/Busy Status, high for Ready, low for Busy
input   PT;             // Block protection enable, high active

    /*----------------------------------------------------------------------*/
    /* Define ID Parameter                                                  */
    /*----------------------------------------------------------------------*/
parameter       Maker_Code      = 8'hc2;
parameter       Device_Code     = 8'hf1;
parameter       id1_2           = 8'h80;
parameter       id1_3           = 8'h91;
parameter       id1_4           = 8'h03;
parameter       id1_5           = 8'h03;
parameter       id2_0           = 8'h4f;
parameter       id2_1           = 8'h4e;
parameter       id2_2           = 8'h46;
parameter       id2_3           = 8'h49;

    /*----------------------------------------------------------------------*/
    /* Density state parameter                                              */
    /*----------------------------------------------------------------------*/
parameter       Top_Add         = (1<<(A_MSB+1))-1;
parameter       OTP_Top_Add     = (1<<(CA_MSB+6))-1;
parameter       OTP_Low_Add     = 1<<(CA_MSB+2);
parameter       PARA_Top_Add    = (1<<CA_MSB) + (1<<CA_SPA+1)-1;
parameter       FEAT_Top_Add    = (1<<CA_MSB) + (1<<(CA_SPA+1))-1;
parameter       UNID_Top_Add    = (1<<CA_MSB) + (1<<(CA_SPA+1))-1;
parameter       Top_Cache       = (1<<CA_MSB) + (1<<(CA_SPA+1))-1;
parameter       ALL_Page_NUM    = 1<<(A_MSB-CA_MSB); // Page number in whole chip
parameter       Page_NUM        = 1<<(MSB_PA_IN_BLOCK+1); // Page number in one block
parameter       NOP_MSB         = 1;
parameter       NOP             = 4;    // Number of partial program cycles in same page
parameter       OTP_NOP_MSB     = 2;
parameter       OTP_NOP         = 8;    // Number of partial program cycles in same page (OTP)

    /*----------------------------------------------------------------------*/
    /* AC Characters Parameter                                              */
    /*----------------------------------------------------------------------*/
parameter       
        Trea            = 16,     // REB access time
        Tcea            = 25,     // CEB access time
        Toh             = 15,      // Data-out hold time
        Tcoh            = 15,     // CEB high to Data-out hold time
        Trloh           = 5,    // REB low to data hold time (EDO)
        Trhz            = 60,     // REB high to output high impedance
        Tchz            = 50,     // CEB high to output high impedance
        Tr              = 25_000,       // Data transfer from array to buffer
        Tr_ecc          = 45_000,   // Data transfer from array to buffer with ECC enable
        Tdr             = 25_000,      // Data transfer from array to buffer of Two Plane
        Tdr_ecc         = 65_000,  // Data transfer from array to buffer of Two Plane with ECC enable
        Twb             = 100,      // WEB high to busy
        Trst_r          = 5_000,   // Reset time for read
        Trst_p          = 10_000,   // Reset time for program
        Trst_e          = 500_000,   // Reset time for erase
        Tvcs            = 5_000_000,     // Vcc setup time
        Tcbsy_normal    = 5_000,    // Dummy busy time for cache program
        Tcbsy_rand      = 30_000,    // Dummy busy time for cache program (Randomizer enabled)
        Trcbsy          = 4_500,   // Dummy busy time for cache read
        Trcbsy_ecc      = 3_000,// Dummy busy time for cache read with ECC enable
        Tdrcbsy_ecc     = 3_000,// Dummy busy time for cache read with ECC enable of Two Plane
        Tprog_normal    = 320_000,    // Page program time
        Tprog_rand      = 360_000,    // Page program time (Randomizer enabled)
        Tprog_ecc       = 270_000,// Page program time with ECC enable
        Tprog_ere       = 750_000,// Page program time for ERE area
        Tdprog_ecc      = 290_000,// Two Plane program time with ECC enable
        Tfeat           = 1_000,    // Busy time for get/set feature
        Tobsy           = 30_000,    // Busy time for OTP program at OTP protection mode
        Tobsy_ecc       = 50_000,// Busy time for OTP program at OTP protection mode with ECC enable
        Tpbsy           = 3_000,    // Busy time for program/erase at protected blocks
        Terase          = 4_000_000;   // Block erase time

specify
        specparam
        Tcls    = 10,
        Tclh    = 5,
        Tcs     = 15,
        Tch     = 5,
        Twp     = 10,
        Tals    = 10,
        Talh    = 5,
        Tds     = 7,
        Tdh     = 5,
        Twc     = 20,
        Twh     = 7,
        Tadl    = 70,
        Tww     = 100,
        Trr     = 20,
        Trp     = 10,
        Trc     = 20,
        Treh    = 7, 
        Tir     = 0,
        Trhw    = 60,
        Twhr    = 60,
        Tclr    = 10,
        Tar     = 10;
endspecify

    /*----------------------------------------------------------------------*/
    /* Internal State Machine State                                         */
    /*----------------------------------------------------------------------*/
parameter       INIT_STAT       = 6'h0;
parameter       READ_STAT1      = 6'h1;
parameter       RAND_STAT1      = 6'h2;
parameter       CARD_STAT1      = 6'h3;
parameter       RANDCARD_STAT1  = 6'h4;
parameter       PGM_STAT1       = 6'h5;
parameter       RANDIN_STAT1    = 6'h6;
parameter       ERS_STAT1       = 6'h7;
parameter       DPRD_STAT1      = 6'h8;

    /*----------------------------------------------------------------------*/
    /* Define Command Parameter                                             */
    /*----------------------------------------------------------------------*/
parameter       READ_CMD1       = 8'h00;
parameter       READ_CMD2       = 8'h30;
parameter       RAND_CMD1       = 8'h05;
parameter       RAND_CMD2       = 8'he0;
parameter       CARD_CMD1       = 8'h31;
parameter       CARD_CMD2       = 8'h3f;
parameter       PGM_CMD1        = 8'h80;
parameter       PGM_CMD2        = 8'h10;
parameter       CAPGM_CMD2      = 8'h15;
parameter       RANDIN_CMD1     = 8'h85;
parameter       BKERS_CMD1      = 8'h60;
parameter       BKERS_CMD2      = 8'hd0;
parameter       RDID_CMD        = 8'h90;
parameter       STAT_CMD        = 8'h70;
parameter       RST_CMD         = 8'hff;
parameter       PRRD_CMD        = 8'hec;
parameter       UNID_CMD        = 8'hed;
parameter       SETFT_CMD       = 8'hef;
parameter       RDFT_CMD        = 8'hee;
parameter       PRTRD_CMD       = 8'h7a;

    /*----------------------------------------------------------------------*/
    /* Declaration of internal-register                                     */
    /*----------------------------------------------------------------------*/
reg [IO_MSB:0]  ARRAY[0:Top_Add];       // Flash Array
reg [IO_MSB:0]  OTP_ARRAY[OTP_Low_Add:OTP_Top_Add];// OTP Array
reg [7:0]       PARA_ARRAY[0:PARA_Top_Add];// Parameter page Array
reg [7:0]       UNID_ARRAY[0:UNID_Top_Add];// UNID Array (in byte)
reg [7:0]       UNID_REG; // UNID Register
reg [7:0]       FEAT_ARRAY1[0:FEAT_Top_Add];// Feature Array (in byte)
reg [7:0]       FEAT_ARRAY2[0:FEAT_Top_Add];// Feature Array (in byte)
reg [7:0]       FEAT_ARRAY3[0:FEAT_Top_Add];// Feature Array (in byte)
reg [7:0]       FEAT_ARRAY4[0:FEAT_Top_Add];// Feature Array (in byte)
reg [7:0]       id1[0:5];
reg [7:0]       id2[0:3];
reg [7:0]       id_buffer1[0:5];
reg [7:0]       id_buffer2[0:3];
reg [IO_MSB:0]  Cache0[0:Top_Cache];    // Cache Buffer
reg [IO_MSB:0]  PBuff0[0:Top_Cache];    // Cache Buffer
reg [IO_MSB:0]  Cache1[0:Top_Cache];    // Cache Buffer
reg [IO_MSB:0]  PBuff1[0:Top_Cache];    // Cache Buffer
reg [7:0]       PBuff_TMP;
reg [7:0]       last_cycle_addr;
reg [IO_MSB:0]  Q_Reg;                  // Register to drive Q port
reg [A_MSB:0]   Latch_A;                // latched Address
reg [A_MSB:0]   Latch_A_OUT;            // read Address
reg [A_MSB:0]   Latch_A_4TMP;           // latched Address
reg [A_MSB:0]   Latch_A_CAOP;           // latched Address for cache operation
reg [A_MSB:0]   Latch_A_st;             // first page Address
reg [A_MSB:0]   Latch_A_st_4TMP;        // first page Address
reg [A_MSB:0]   Latch_A_st_CAOP;        // first page Address for cache operation
reg [A_MSB:0]   Latch_A_nd;             // second page Address
reg [A_MSB:0]   Latch_A_nd_4TMP;        // second page Address
reg [A_MSB:0]   Latch_A_nd_CAOP;        // second page Address for cache operation
reg [A_MSB:0]   ADD_Prot_Low;           // protect lower boundary address
reg [A_MSB:0]   ADD_Prot_Upper;         // protect upper boundary address
reg [7:0]       FEAT_ARRAY_DUM1;
reg [7:0]       FEAT_ARRAY_DUM2;
reg [7:0]       FEAT_ARRAY_DUM3;
reg [7:0]       FEAT_ARRAY_DUM4;
reg [7:0]       FEAT_ARRAY_TMP;
reg             RANDEN_TMP;
reg             RANDOPT_TMP;
reg [NOP_MSB+1:0] PGM_Count[0:ALL_Page_NUM-1];
reg [OTP_NOP_MSB+1:0] OTP_PGM_Count[0:ALL_Page_NUM-1];
reg [5:0]       STATE;
reg Power_Up;
reg last_addr_flag;
reg Page_EN;
reg RD_Mode;
reg READ_Mode;
reg CARD_Mode;
reg CARD_Mode_End;
reg RANDCARD_Mode;
reg RANDCARD_Mode_End;
reg capgm_op;
reg capgm_op_mode;
reg pgm_busy;
reg ers_busy;
reg sr7, sr6, sr5, sr4, sr3, sr2, sr1, sr0;
reg sr0_0, sr1_0, sr1_0_pre, sr0_1, sr1_1_pre, sr1_1;
reg sr5_flag;
reg rdid_flag;
reg status_flag;
reg enhance_status_flag;
reg parameter_flag;
reg unid_flag;
reg read_feature_flag;
reg set_feature_flag;
reg read_ere_flag;
reg Feature_EN;
reg feature_busy;
reg OTP_Protect; // non-volatile bit
reg [7:0] ERE_status;
reg [7:0] ERE_status_dum;
reg DPRD_Mode;
reg DPRD_Mode_4TMP;
reg DPRD_addr_chk;
reg plane_flag;
reg CMD_11h_flag;
reg DPPGM_Mode;
reg DPPGM_Mode_4TMP;
reg DPPGM_addr_chk;
reg DPERS_Mode;
reg DPERS_Mode_4TMP;
reg DPERS_addr_chk;
reg unprotect_low_flag;
reg unprotect_upper_flag;
reg protect_all_flag; // power on cycle set
reg solid_protect; // power on cycle reset
reg protect_status_flag;
reg Invert_Bit; //protect invert bit
reg [31:0] PBL_status;
reg [31:0] PBL_status_dum;
reg OUT_EN;
reg OUTZ_EN;
reg protect_en;

integer pa_count;
integer j;
integer ADR_CYC;
integer DATA_CYC;
integer block_count;

event internal_read;
event internal_read_DP;
event another_read;
event random_cache_read;
event last_read;
event load_pb2cache;
event parameter_read;
event unid_read;
event set_feature;
event read_feature;
event read_id;
event read_ere;
event page_pgm;
event rand_pgm;
event cache_pgm;
event dp_pgm;
event capgm_op_event;
event block_ers;
event dp_ers;
event Read_Q;
event OUT_Q;
event OUT_EN_event;
event reset_event;


wire CE_B_IN;
wire CE_B_IN2;
wire RE_B_IN;
wire WP_B_IN;
wire WP_B_IN2;
wire card_op;
wire [7:0] Array_Mode;
wire [7:0] ERE_Mode;
wire ECC_Enable;
wire [7:0] PBL_Mode;
wire PBL_Invert;
wire PBL_Enb;
wire Normal_Mode;
wire Spare_Mode;
wire [7:0] BP_Feature;
wire [2:0] BP_Bit;
wire BP_Invert;
wire BP_Complement;
wire BP_Solid;
wire [7:0] Randomizer_Feature;
wire [31:0] Tcbsy;
wire [31:0] Tprog;

assign #Tcea CE_B_IN = CE_B;
assign #Tchz CE_B_IN2= CE_B;
assign #(Toh, 0) RE_B_IN = RE_B;
assign WP_B_IN2 = WP_B;
assign WP_B_IN = (protect_en===1) ? WP_B_IN2 : WP_B;
assign #(0, 0) IO[IO_MSB:0]  = OUT_EN&&!CE_B_IN&&!RE_B_IN ? Q_Reg[IO_MSB:0] : OUTZ_EN&&!CE_B_IN2 ? ((IO_MSB==7)?8'hx:16'hx) : ((IO_MSB==7)?8'hz:16'hz);
assign #(0, 0) RYBY_B        = sr6 ? 1'bz : 1'b0;

assign card_op = CARD_Mode || RANDCARD_Mode;
assign Array_Mode = FEAT_ARRAY1[8'h90];
assign ERE_Mode = 8'h00;
assign ECC_Enable = 1'b0;
assign PBL_Mode = 8'h00;
assign PBL_Enb = 1'b1;
assign PBL_Invert = PBL_status[30];
assign Normal_Mode = !(Array_Mode[0] || ERE_Mode[0] || PBL_Mode[0]);
assign Spare_Mode = ERE_Mode[0] || PBL_Mode[0];
assign BP_Feature = FEAT_ARRAY1[8'ha0];
assign BP_Bit = BP_Feature[5:3];
assign BP_Invert = BP_Feature[2];
assign BP_Complement = BP_Feature[1];
assign BP_Solid = BP_Feature[0];
assign Randomizer_Feature = FEAT_ARRAY1[8'hb0];
assign Tcbsy = Randomizer_Feature[1] ? Tcbsy_rand : Tcbsy_normal;
assign Tprog = Randomizer_Feature[1] ? Tprog_rand : Tprog_normal;

    /*----------------------------------------------------------------------*/
    /* Power-on State                                                       */
    /*----------------------------------------------------------------------*/
initial fork: power_on
        begin
                Power_Up = 1'b0;
                #Tvcs;
                Power_Up = 1'b1;
// load page0 to cache
                for ( pa_count = 0; pa_count <= Top_Cache; pa_count = pa_count + 1) begin
                    PBuff0[pa_count] = ARRAY[pa_count];
                end
                for ( pa_count = 0; pa_count <= Top_Cache; pa_count = pa_count + 1) begin
                    Cache0[pa_count] = PBuff0[pa_count];
                end
                Page_EN = 1'b1;
                disable power_on;
        end
        begin
                wait ( PT===1'b1 );
                protect_en = (PT===1'b1) ? 1'b1 : 1'b0;
        end
join

    /*----------------------------------------------------------------------*/
    /* Power-on initial model registers                                     */
    /*----------------------------------------------------------------------*/
initial begin
        for ( j = 0;j < ALL_Page_NUM; j = j + 1 ) begin
                PGM_Count[j] = 0;
                OTP_PGM_Count[j] = 0;
        end
        OTP_Protect             = `VOTP_Protect;
        ERE_status              = `VERE_status;
        protect_all_flag        = 1'b1;
        solid_protect           = 1'b0;
        Invert_Bit              = 1'b0;
        ADD_Prot_Low            = 0;
        ADD_Prot_Upper          = 0;
        PBL_status              = 32'hffff_ffff;
        tk_reset;
end

    /*----------------------------------------------------------------------*/
    /* preload memory                                                       */
    /*----------------------------------------------------------------------*/
initial begin: init_memory
        for ( j = 0; j <= Top_Add; j = j + 1 ) begin
                ARRAY[j] = ~0;
        end
        if ( Init_File != "none" ) begin
// load ARRAY data from file by byte mode for X08 product, byte word mode for X16 product
                $readmemh( Init_File, ARRAY );
        end

        for ( j = OTP_Low_Add; j <= OTP_Top_Add; j = j + 1 ) begin
                OTP_ARRAY[j] = ~0;
        end

        id1[0] = Maker_Code;
        id1[1] = Device_Code;
        id1[2] = id1_2;
        id1[3] = id1_3;
        id1[4] = id1_4;
        id1[5] = id1_5;
        id2[0] = id2_0;
        id2[1] = id2_1;
        id2[2] = id2_2;
        id2[3] = id2_3;

//      define PARA_ARRAY data
	PARA_ARRAY[0] = 8'h4f;
	PARA_ARRAY[1] = 8'h4e;
	PARA_ARRAY[2] = 8'h46;
	PARA_ARRAY[3] = 8'h49;
	PARA_ARRAY[4] = 8'h02;
	PARA_ARRAY[5] = 8'h00;
	PARA_ARRAY[6] = 8'h10;
	PARA_ARRAY[7] = 8'h00;
	PARA_ARRAY[8] = 8'h37;
	PARA_ARRAY[9] = 8'h00;
	PARA_ARRAY[10] = 8'h00;
	PARA_ARRAY[11] = 8'h00;
	PARA_ARRAY[12] = 8'h00;
	PARA_ARRAY[13] = 8'h00;
	PARA_ARRAY[14] = 8'h00;
	PARA_ARRAY[15] = 8'h00;
	PARA_ARRAY[16] = 8'h00;
	PARA_ARRAY[17] = 8'h00;
	PARA_ARRAY[18] = 8'h00;
	PARA_ARRAY[19] = 8'h00;
	PARA_ARRAY[20] = 8'h00;
	PARA_ARRAY[21] = 8'h00;
	PARA_ARRAY[22] = 8'h00;
	PARA_ARRAY[23] = 8'h00;
	PARA_ARRAY[24] = 8'h00;
	PARA_ARRAY[25] = 8'h00;
	PARA_ARRAY[26] = 8'h00;
	PARA_ARRAY[27] = 8'h00;
	PARA_ARRAY[28] = 8'h00;
	PARA_ARRAY[29] = 8'h00;
	PARA_ARRAY[30] = 8'h00;
	PARA_ARRAY[31] = 8'h00;
	PARA_ARRAY[32] = 8'h4d;
	PARA_ARRAY[33] = 8'h41;
	PARA_ARRAY[34] = 8'h43;
	PARA_ARRAY[35] = 8'h52;
	PARA_ARRAY[36] = 8'h4f;
	PARA_ARRAY[37] = 8'h4e;
	PARA_ARRAY[38] = 8'h49;
	PARA_ARRAY[39] = 8'h58;
	PARA_ARRAY[40] = 8'h20;
	PARA_ARRAY[41] = 8'h20;
	PARA_ARRAY[42] = 8'h20;
	PARA_ARRAY[43] = 8'h20;
	PARA_ARRAY[44] = 8'h4d;
	PARA_ARRAY[45] = 8'h58;
	PARA_ARRAY[46] = 8'h33;
	PARA_ARRAY[47] = 8'h30;
	PARA_ARRAY[48] = 8'h4c;
	PARA_ARRAY[49] = 8'h46;
	PARA_ARRAY[50] = 8'h31;
	PARA_ARRAY[51] = 8'h47;
	PARA_ARRAY[52] = 8'h32;
	PARA_ARRAY[53] = 8'h38;
	PARA_ARRAY[54] = 8'h41;
	PARA_ARRAY[55] = 8'h44;
	PARA_ARRAY[56] = 8'h20;
	PARA_ARRAY[57] = 8'h20;
	PARA_ARRAY[58] = 8'h20;
	PARA_ARRAY[59] = 8'h20;
	PARA_ARRAY[60] = 8'h20;
	PARA_ARRAY[61] = 8'h20;
	PARA_ARRAY[62] = 8'h20;
	PARA_ARRAY[63] = 8'h20;
	PARA_ARRAY[64] = 8'hc2;
	PARA_ARRAY[65] = 8'h00;
	PARA_ARRAY[66] = 8'h00;
	PARA_ARRAY[67] = 8'h00;
	PARA_ARRAY[68] = 8'h00;
	PARA_ARRAY[69] = 8'h00;
	PARA_ARRAY[70] = 8'h00;
	PARA_ARRAY[71] = 8'h00;
	PARA_ARRAY[72] = 8'h00;
	PARA_ARRAY[73] = 8'h00;
	PARA_ARRAY[74] = 8'h00;
	PARA_ARRAY[75] = 8'h00;
	PARA_ARRAY[76] = 8'h00;
	PARA_ARRAY[77] = 8'h00;
	PARA_ARRAY[78] = 8'h00;
	PARA_ARRAY[79] = 8'h00;
	PARA_ARRAY[80] = 8'h00;
	PARA_ARRAY[81] = 8'h08;
	PARA_ARRAY[82] = 8'h00;
	PARA_ARRAY[83] = 8'h00;
	PARA_ARRAY[84] = 8'h80;
	PARA_ARRAY[85] = 8'h00;
	PARA_ARRAY[86] = 8'h00;
	PARA_ARRAY[87] = 8'h02;
	PARA_ARRAY[88] = 8'h00;
	PARA_ARRAY[89] = 8'h00;
	PARA_ARRAY[90] = 8'h20;
	PARA_ARRAY[91] = 8'h00;
	PARA_ARRAY[92] = 8'h40;
	PARA_ARRAY[93] = 8'h00;
	PARA_ARRAY[94] = 8'h00;
	PARA_ARRAY[95] = 8'h00;
	PARA_ARRAY[96] = 8'h00;
	PARA_ARRAY[97] = 8'h04;
	PARA_ARRAY[98] = 8'h00;
	PARA_ARRAY[99] = 8'h00;
	PARA_ARRAY[100] = 8'h01;
	PARA_ARRAY[101] = 8'h22;
	PARA_ARRAY[102] = 8'h01;
	PARA_ARRAY[103] = 8'h14;
	PARA_ARRAY[104] = 8'h00;
	PARA_ARRAY[105] = 8'h06;
	PARA_ARRAY[106] = 8'h04;
	PARA_ARRAY[107] = 8'h08;
	PARA_ARRAY[108] = 8'h00;
	PARA_ARRAY[109] = 8'h00;
	PARA_ARRAY[110] = 8'h04;
	PARA_ARRAY[111] = 8'h00;
	PARA_ARRAY[112] = 8'h08;
	PARA_ARRAY[113] = 8'h00;
	PARA_ARRAY[114] = 8'h00;
	PARA_ARRAY[115] = 8'h00;
	PARA_ARRAY[116] = 8'h00;
	PARA_ARRAY[117] = 8'h00;
	PARA_ARRAY[118] = 8'h00;
	PARA_ARRAY[119] = 8'h00;
	PARA_ARRAY[120] = 8'h00;
	PARA_ARRAY[121] = 8'h00;
	PARA_ARRAY[122] = 8'h00;
	PARA_ARRAY[123] = 8'h00;
	PARA_ARRAY[124] = 8'h00;
	PARA_ARRAY[125] = 8'h00;
	PARA_ARRAY[126] = 8'h00;
	PARA_ARRAY[127] = 8'h00;
	PARA_ARRAY[128] = 8'h0a;
	PARA_ARRAY[129] = 8'h3f;
	PARA_ARRAY[130] = 8'h00;
	PARA_ARRAY[131] = 8'h3f;
	PARA_ARRAY[132] = 8'h00;
	PARA_ARRAY[133] = 8'hbc;
	PARA_ARRAY[134] = 8'h02;
	PARA_ARRAY[135] = 8'h70;
	PARA_ARRAY[136] = 8'h17;
	PARA_ARRAY[137] = 8'h19;
	PARA_ARRAY[138] = 8'h00;
	PARA_ARRAY[139] = 8'h3c;
	PARA_ARRAY[140] = 8'h00;
	PARA_ARRAY[141] = 8'h00;
	PARA_ARRAY[142] = 8'h00;
	PARA_ARRAY[143] = 8'h00;
	PARA_ARRAY[144] = 8'h00;
	PARA_ARRAY[145] = 8'h00;
	PARA_ARRAY[146] = 8'h00;
	PARA_ARRAY[147] = 8'h00;
	PARA_ARRAY[148] = 8'h00;
	PARA_ARRAY[149] = 8'h00;
	PARA_ARRAY[150] = 8'h00;
	PARA_ARRAY[151] = 8'h00;
	PARA_ARRAY[152] = 8'h00;
	PARA_ARRAY[153] = 8'h00;
	PARA_ARRAY[154] = 8'h00;
	PARA_ARRAY[155] = 8'h00;
	PARA_ARRAY[156] = 8'h00;
	PARA_ARRAY[157] = 8'h00;
	PARA_ARRAY[158] = 8'h00;
	PARA_ARRAY[159] = 8'h00;
	PARA_ARRAY[160] = 8'h00;
	PARA_ARRAY[161] = 8'h00;
	PARA_ARRAY[162] = 8'h00;
	PARA_ARRAY[163] = 8'h00;
	PARA_ARRAY[164] = 8'h00;
	PARA_ARRAY[165] = 8'h00;
	PARA_ARRAY[166] = 8'h00;
	PARA_ARRAY[167] = 8'h03;
	PARA_ARRAY[168] = 8'h00;
	PARA_ARRAY[169] = 8'h05;
	PARA_ARRAY[170] = 8'h00;
	PARA_ARRAY[171] = 8'h00;
	PARA_ARRAY[172] = 8'h00;
	PARA_ARRAY[173] = 8'h00;
	PARA_ARRAY[174] = 8'h00;
	PARA_ARRAY[175] = 8'h00;
	PARA_ARRAY[176] = 8'h00;
	PARA_ARRAY[177] = 8'h00;
	PARA_ARRAY[178] = 8'h00;
	PARA_ARRAY[179] = 8'h00;
	PARA_ARRAY[180] = 8'h00;
	PARA_ARRAY[181] = 8'h00;
	PARA_ARRAY[182] = 8'h00;
	PARA_ARRAY[183] = 8'h00;
	PARA_ARRAY[184] = 8'h00;
	PARA_ARRAY[185] = 8'h00;
	PARA_ARRAY[186] = 8'h00;
	PARA_ARRAY[187] = 8'h00;
	PARA_ARRAY[188] = 8'h00;
	PARA_ARRAY[189] = 8'h00;
	PARA_ARRAY[190] = 8'h00;
	PARA_ARRAY[191] = 8'h00;
	PARA_ARRAY[192] = 8'h00;
	PARA_ARRAY[193] = 8'h00;
	PARA_ARRAY[194] = 8'h00;
	PARA_ARRAY[195] = 8'h00;
	PARA_ARRAY[196] = 8'h00;
	PARA_ARRAY[197] = 8'h00;
	PARA_ARRAY[198] = 8'h00;
	PARA_ARRAY[199] = 8'h00;
	PARA_ARRAY[200] = 8'h00;
	PARA_ARRAY[201] = 8'h00;
	PARA_ARRAY[202] = 8'h00;
	PARA_ARRAY[203] = 8'h00;
	PARA_ARRAY[204] = 8'h00;
	PARA_ARRAY[205] = 8'h00;
	PARA_ARRAY[206] = 8'h00;
	PARA_ARRAY[207] = 8'h00;
	PARA_ARRAY[208] = 8'h00;
	PARA_ARRAY[209] = 8'h00;
	PARA_ARRAY[210] = 8'h00;
	PARA_ARRAY[211] = 8'h00;
	PARA_ARRAY[212] = 8'h00;
	PARA_ARRAY[213] = 8'h00;
	PARA_ARRAY[214] = 8'h00;
	PARA_ARRAY[215] = 8'h00;
	PARA_ARRAY[216] = 8'h00;
	PARA_ARRAY[217] = 8'h00;
	PARA_ARRAY[218] = 8'h00;
	PARA_ARRAY[219] = 8'h00;
	PARA_ARRAY[220] = 8'h00;
	PARA_ARRAY[221] = 8'h00;
	PARA_ARRAY[222] = 8'h00;
	PARA_ARRAY[223] = 8'h00;
	PARA_ARRAY[224] = 8'h00;
	PARA_ARRAY[225] = 8'h00;
	PARA_ARRAY[226] = 8'h00;
	PARA_ARRAY[227] = 8'h00;
	PARA_ARRAY[228] = 8'h00;
	PARA_ARRAY[229] = 8'h00;
	PARA_ARRAY[230] = 8'h00;
	PARA_ARRAY[231] = 8'h00;
	PARA_ARRAY[232] = 8'h00;
	PARA_ARRAY[233] = 8'h00;
	PARA_ARRAY[234] = 8'h00;
	PARA_ARRAY[235] = 8'h00;
	PARA_ARRAY[236] = 8'h00;
	PARA_ARRAY[237] = 8'h00;
	PARA_ARRAY[238] = 8'h00;
	PARA_ARRAY[239] = 8'h00;
	PARA_ARRAY[240] = 8'h00;
	PARA_ARRAY[241] = 8'h00;
	PARA_ARRAY[242] = 8'h00;
	PARA_ARRAY[243] = 8'h00;
	PARA_ARRAY[244] = 8'h00;
	PARA_ARRAY[245] = 8'h00;
	PARA_ARRAY[246] = 8'h00;
	PARA_ARRAY[247] = 8'h00;
	PARA_ARRAY[248] = 8'h00;
	PARA_ARRAY[249] = 8'h00;
	PARA_ARRAY[250] = 8'h00;
	PARA_ARRAY[251] = 8'h00;
	PARA_ARRAY[252] = 8'h00;
	PARA_ARRAY[253] = 8'h00;
	PARA_ARRAY[254] = `VCRC1;
	PARA_ARRAY[255] = `VCRC2;
        for ( j = 0; j <= 255; j = j + 1 ) begin
                PARA_ARRAY[j+256] = PARA_ARRAY[j];
                PARA_ARRAY[j+512] = PARA_ARRAY[j];
                PARA_ARRAY[j+768] = PARA_ARRAY[j];
                PARA_ARRAY[j+1024] = PARA_ARRAY[j];
                PARA_ARRAY[j+1280] = PARA_ARRAY[j];
                PARA_ARRAY[j+1536] = PARA_ARRAY[j];
                PARA_ARRAY[j+1792] = PARA_ARRAY[j];
        end

        UNID_REG = ~0;
        for ( j = 0; j <= UNID_Top_Add; j = j + 1 ) begin
                UNID_ARRAY[j] = ~0;
        end
        for ( j = 0; j <= 9'h1ff; j = j + 1 ) begin
                if ( j%16 == 0 ) begin
                        UNID_REG = ~UNID_REG;
                end
                UNID_ARRAY[j] = UNID_REG;

        end

        for ( j = 0; j <= FEAT_Top_Add; j = j + 1 ) begin
                FEAT_ARRAY1[j] = 8'h00;
                FEAT_ARRAY2[j] = 8'h00;
                FEAT_ARRAY3[j] = 8'h00;
                FEAT_ARRAY4[j] = 8'h00;
        end
        FEAT_ARRAY1[8'ha0] = 8'h38;

end

    /*----------------------------------------------------------------------*/
    /* Specify the timing                                                   */
    /*----------------------------------------------------------------------*/
wire RYBY_RE_W;
assign RYBY_RE_W = !status_flag && !enhance_status_flag && !rdid_flag && !read_ere_flag && !protect_status_flag;
specify
        $setuphold ( posedge WE_B, CLE, Tcls, Tclh );
        $setuphold ( posedge WE_B, ALE, Tals, Talh );
        $setuphold ( posedge WE_B, CE_B, Tcs, Tch );
        $width ( negedge WE_B, Twp );                    
        $setuphold ( posedge WE_B, IO, Tds, Tdh );
        $period( negedge WE_B, Twc ); 
        $width ( posedge WE_B, Twh );                    
        $setup ( WP_B, posedge WE_B, Tww );
        $setup ( posedge RYBY_B, negedge RE_B &&& RYBY_RE_W, Trr );
        $width ( negedge RE_B, Trp );                    
        $period( negedge RE_B, Trc ); 
        $width ( posedge RE_B, Treh );                    
        $setup ( IO, negedge RE_B, Tir );
        $setup ( posedge RE_B, negedge WE_B, Trhw );
        $setup ( posedge WE_B, negedge RE_B, Twhr );
        $setup ( negedge CLE, negedge RE_B, Tclr );
        $setup ( negedge ALE, negedge RE_B, Tar );
endspecify

reg Tadl_chk;
integer Tadl_begin;
integer Tadl_delta;

initial begin
        Tadl_chk  = 1'b0;
        Tadl_begin= 0;
        Tadl_delta= 0;
end

always @ ( posedge WE_B ) begin
        if ( !ALE && !CLE ) begin
                Tadl_delta = $time - Tadl_begin;
                if (Tadl_delta < Tadl && $time > 0) begin
                        $display($time,"Warning: WE_B not meet spec Tadl=%dns, now it's %dns\n",Tadl,Tadl_delta);
                end
        end
        if ( ALE ) begin
                Tadl_chk  = 1'b1;
                Tadl_begin= $time;
        end
        else begin
                Tadl_chk  = 1'b0;
        end
end

// *==============================================================================================
// * FSM state transition
// *==============================================================================================
always @ ( posedge WE_B or posedge CE_B ) begin
        if ( Power_Up ) begin

                if ( CE_B ) begin
                        -> OUT_EN_event;
                end
                else if ( WE_B ) begin
                        if ( !ALE && !CLE ) begin
                                if ( set_feature_flag == 1'b1 ) begin
                                        if ( DATA_CYC == 0 ) begin
                                                FEAT_ARRAY_DUM1 = IO[7:0];
                                                DATA_CYC = 1;
                                        end
                                        else if ( DATA_CYC == 1 ) begin
                                                FEAT_ARRAY_DUM2 = IO[7:0];
                                                DATA_CYC = 2;
                                        end
                                        else if ( DATA_CYC == 2 ) begin
                                                FEAT_ARRAY_DUM3 = IO[7:0];
                                                DATA_CYC = 3;
                                        end
                                        else if ( DATA_CYC == 3 ) begin
                                                FEAT_ARRAY_DUM4 = IO[7:0];
                                                DATA_CYC = 4;
                                        end
                                end
                                else if ( ERE_Mode[0] == 1'b1 ) begin
                                        if ( DATA_CYC == 0 ) begin
                                                ERE_status_dum[0] = ( IO[7:0] == 8'hff ) ? 1'b1 : 1'b0;
                                                DATA_CYC = 1;
                                        end
                                        else if ( DATA_CYC == 1 ) begin
                                                ERE_status_dum[1] = ( IO[7:0] == 8'hff ) ? 1'b1 : 1'b0;
                                                DATA_CYC = 2;
                                        end
                                        else if ( DATA_CYC == 2 ) begin
                                                ERE_status_dum[2] = ( IO[7:0] == 8'hff ) ? 1'b1 : 1'b0;
                                                DATA_CYC = 3;
                                        end
                                        else if ( DATA_CYC == 3 ) begin
                                                ERE_status_dum[3] = ( IO[7:0] == 8'hff ) ? 1'b1 : 1'b0;
                                                DATA_CYC = 4;
                                        end
                                        else if ( DATA_CYC == 4 ) begin
                                                ERE_status_dum[4] = ( IO[7:0] == 8'hff ) ? 1'b1 : 1'b0;
                                                DATA_CYC = 5;
                                        end
                                        else if ( DATA_CYC == 5 ) begin
                                                ERE_status_dum[5] = ( IO[7:0] == 8'hff ) ? 1'b1 : 1'b0;
                                                DATA_CYC = 6;
                                        end
                                        else if ( DATA_CYC == 6 ) begin
                                                ERE_status_dum[6] = ( IO[7:0] == 8'hff ) ? 1'b1 : 1'b0;
                                                DATA_CYC = 7;
                                        end
                                        else if ( DATA_CYC == 7 ) begin
                                                ERE_status_dum[7] = ( IO[7:0] == 8'hff ) ? 1'b1 : 1'b0;
                                                DATA_CYC = 0;
                                        end
                                end
                                else if ( PBL_Mode[0] == 1'b1 ) begin
                                        PBL_status_dum[DATA_CYC] = ( IO[7:0] == 8'hff ) ? 1'b1 : 1'b0;
                                        DATA_CYC = DATA_CYC + 1;
                                        if ( DATA_CYC == 32 ) begin
                                                DATA_CYC = 0;
                                        end
                                end
                                else if ( STATE == PGM_STAT1 ) begin
                                        if ( Latch_A[CA_MSB:0] <= Top_Cache ) begin
                                                if ( Latch_A[CA_MSB+7] == 1'b1 ) begin
                                                        plane_flag = 1'b1;
                                                        Cache1[Latch_A[CA_MSB:0]] = IO[IO_MSB:0];
                                                end
                                                else begin
                                                        plane_flag = 1'b0;
                                                        Cache0[Latch_A[CA_MSB:0]] = IO[IO_MSB:0];
                                                end
                                                Latch_A[CA_MSB:0] = Latch_A[CA_MSB:0] + 1;
                                        end
                                        last_addr_flag = (Latch_A[CA_MSB:0] > Top_Cache) ? 1'b1 : 1'b0;
                                        DATA_CYC = DATA_CYC + 1;
                                end
                        end
                        if ( ALE ) begin
                                DATA_CYC = 0;
                                if ( ADR_CYC == 0 || ADR_CYC == 4 ) begin
                                        Latch_A[CA_MSB:0] = 0;
                                        Latch_A[7:0] = IO[7:0];
                                        ADR_CYC = 1;
                                end
                                else if ( ADR_CYC == 1 ) begin
                                        Latch_A[CA_MSB:8] = IO[CA_MSB-8:0];
                                        ADR_CYC = 2;
                                        last_addr_flag = (Latch_A[CA_MSB:0] > Top_Cache) ? 1'b1 : 1'b0;
                                end
                                else if ( ADR_CYC == 2 ) begin
                                        Latch_A[CA_MSB+8:CA_MSB+1] = IO[7:0];
                                        ADR_CYC = 3;
                                end
                                else if ( ADR_CYC == 3 ) begin
                                        Latch_A[A_MSB:CA_MSB+9] = IO[A_MSB-CA_MSB-9:0];
                                        last_cycle_addr = IO[7:0];
                                        ADR_CYC = 4;
                                end
                                if ( (DPRD_addr_chk == 1'b1 || DPPGM_addr_chk == 1'b1 || DPERS_addr_chk == 1'b1)
                                     && ADR_CYC == 4 && !enhance_status_flag ) begin
                                        if ( Latch_A[CA_MSB+7] == Latch_A_st[CA_MSB+7] ) begin
                                                DPRD_Mode = 1'b0;
                                                CMD_11h_flag = 1'b0;
                                                DPPGM_Mode= 1'b0;
                                                DPERS_Mode= 1'b0;
                                        end
                                        else if ( (Latch_A[CA_MSB+6:0] != Latch_A_st[CA_MSB+6:0]) && DPRD_addr_chk == 1'b1 ) begin
                                                Latch_A_st[CA_MSB+6:0] = Latch_A[CA_MSB+6:0];
                                        end
                                        else if ( (Latch_A[CA_MSB+6:CA_MSB+1] != Latch_A_st[CA_MSB+6:CA_MSB+1]) && DPPGM_addr_chk == 1'b1 ) begin
                                                Latch_A_st[CA_MSB+6:CA_MSB+1] = Latch_A[CA_MSB+6:CA_MSB+1];
                                        end
                                        DPRD_addr_chk = 1'b0;
                                        DPPGM_addr_chk = 1'b0;
                                        DPERS_addr_chk = 1'b0;
                                        Latch_A_nd = Latch_A;
                                end

                                if ( unprotect_low_flag == 1'b1 && ADR_CYC == 4 ) begin
                                        ADD_Prot_Low[A_MSB:CA_MSB+7] = Latch_A[A_MSB:CA_MSB+7];
                                        ADD_Prot_Low[CA_MSB+6:0] = 0;
                                        unprotect_low_flag = 1'b0;
                                end
                                if ( unprotect_upper_flag == 1'b1 && ADR_CYC == 4 ) begin
                                        ADD_Prot_Upper[A_MSB:CA_MSB+7] = Latch_A[A_MSB:CA_MSB+7];
                                        ADD_Prot_Upper[CA_MSB+6:0] = 0;
                                        Invert_Bit = Latch_A[CA_MSB+1];
                                        unprotect_upper_flag = 1'b0;
                                end
                        end
                        if ( CLE ) begin
                                Page_EN = 1'b0;
                                if ( enhance_status_flag ) ADR_CYC = 0;
                                Feature_EN = 1'b0;
                                rdid_flag = 1'b0;
                                status_flag = 1'b0;
                                enhance_status_flag = 1'b0;
                                read_ere_flag = 1'b0;
                                protect_status_flag = 1'b0;

                                if ( IO[7:0] == RST_CMD ) begin
                                        ->reset_event;
                                end

                                case ( STATE )
                                        INIT_STAT: begin
                                                if ( IO[7:0] == READ_CMD1 && ADR_CYC != 4 && sr6 ) begin
                                                        if ( CARD_Mode == 1'b1 && CARD_Mode_End == 1'b0 ) begin
                                                                Page_EN = 1'b1;
                                                                RD_Mode = 1'b1;
                                                                READ_Mode = 1'b1;
                                                                STATE = CARD_STAT1;
                                                        end
                                                        else if ( RANDCARD_Mode == 1'b1 && RANDCARD_Mode_End == 1'b0 ) begin
                                                                Page_EN = 1'b1;
                                                                RD_Mode = 1'b1;
                                                                READ_Mode = 1'b1;
                                                                STATE = RANDCARD_STAT1;
                                                        end
                                                        else begin
                                                                if ( parameter_flag == 1'b1 || unid_flag == 1'b1 ) begin
                                                                        Page_EN = 1'b1;
                                                                end
                                                                else if ( read_feature_flag == 1'b1 ) begin
                                                                        Feature_EN = 1'b1;
                                                                end
                                                                STATE = INIT_STAT;
                                                        end
                                                        if ( RD_Mode == 1'b1 ) begin
                                                                Page_EN = 1'b1;
                                                                READ_Mode = !(parameter_flag || unid_flag);
                                                        end
                                                        if ( CARD_Mode == 1'b0 && RANDCARD_Mode == 1'b0 ) begin
                                                                DPRD_Mode = 1'b0;
                                                        end
                                                        Page_EN = 1'b1;
                                                        parameter_flag = 1'b0;
                                                        unid_flag = 1'b0;
                                                        read_feature_flag = 1'b0;
                                                end
                                                else if ( IO[7:0] == READ_CMD2 && card_op == 1'b0 && !capgm_op && sr6 && !Spare_Mode ) begin
                                                        STATE = INIT_STAT;
                                                        RD_Mode = 1'b1;
                                                        READ_Mode = 1'b1;
                                                        -> internal_read;
                                                        $display("[%0t] MXIC: internal_read triggered, Latch_A=%h Page_EN=%b sr6=%b", 
         $time, Latch_A, Page_EN, sr6);
                                                end
                                                else if ( IO[7:0] == CARD_CMD1 && ADR_CYC != 0 && READ_Mode == 1'b1 && sr6 && Normal_Mode ) begin
                                                        STATE = RANDCARD_STAT1;
                                                        RANDCARD_Mode = 1'b1;
                                                        RANDCARD_Mode_End = 1'b0;
                                                        -> random_cache_read;
                                                end
                                                else if ( IO[7:0] == CARD_CMD1 && ADR_CYC == 0 && READ_Mode == 1'b1 && sr6 && Normal_Mode ) begin
                                                        parameter_flag = 1'b0;
                                                        unid_flag = 1'b0;
                                                        read_feature_flag = 1'b0;
                                                        STATE = CARD_STAT1;
                                                        CARD_Mode = 1'b1;
                                                        CARD_Mode_End = 1'b0;
                                                        -> another_read;
                                                end
                                                else if ( IO[7:0] == CARD_CMD2 && ADR_CYC != 0 && READ_Mode == 1'b1 && sr6 && Normal_Mode ) begin
                                                        STATE = INIT_STAT;
                                                        RANDCARD_Mode = 1'b1;
                                                        RANDCARD_Mode_End = 1'b1;
                                                        -> random_cache_read;
                                                end
                                                else if ( IO[7:0] == CARD_CMD2 && ADR_CYC == 0 && READ_Mode == 1'b1 && sr6 && Normal_Mode ) begin
                                                        parameter_flag = 1'b0;
                                                        unid_flag = 1'b0;
                                                        read_feature_flag = 1'b0;
                                                        STATE = INIT_STAT;
                                                        if ( RANDCARD_Mode == 1'b1 ) begin
                                                                RANDCARD_Mode = 1'b1;
                                                                RANDCARD_Mode_End = 1'b1;
                                                                -> random_cache_read;
                                                        end
                                                        else begin
                                                                CARD_Mode = 1'b1;
                                                                CARD_Mode_End = 1'b1;
                                                                -> another_read;
                                                        end
                                                end
                                                else if ( IO[7:0] == RAND_CMD1 && sr6 ) begin
                                                        STATE = RAND_STAT1;
                                                end
                                                else if ( IO[7:0] == PGM_CMD1 && sr6 && !card_op && WP_B_IN ) begin
                                                        DPRD_Mode = 1'b0;
                                                        parameter_flag = 1'b0;
                                                        unid_flag = 1'b0;
                                                        read_feature_flag = 1'b0;
                                                        RD_Mode = 1'b0;
                                                        READ_Mode = 1'b0;
                                                        if ( CMD_11h_flag == 1'b0 ) begin
                                                                for ( pa_count = 0; pa_count <= Top_Cache; pa_count = pa_count + 1) begin
                                                                        Cache0[pa_count] = ~0;
                                                                        Cache1[pa_count] = ~0;
                                                                end
                                                        end
                                                        STATE = PGM_STAT1;
                                                end
                                                else if ( IO[7:0] == BKERS_CMD1 && sr6 && (sr5||DPERS_Mode) && !card_op && WP_B_IN && Normal_Mode ) begin
                                                        DPRD_Mode = 1'b0;
                                                        parameter_flag = 1'b0;
                                                        unid_flag = 1'b0;
                                                        read_feature_flag = 1'b0;
                                                        RD_Mode = 1'b0;
                                                        READ_Mode = 1'b0;
                                                        STATE = ERS_STAT1;
                                                end
                                                else if ( IO[7:0] == RDID_CMD && sr6 && sr5 && !card_op ) begin
                                                        DPRD_Mode = 1'b0;
                                                        parameter_flag = 1'b0;
                                                        unid_flag = 1'b0;
                                                        read_feature_flag = 1'b0;
                                                        RD_Mode = 1'b0;
                                                        READ_Mode = 1'b0;
                                                        rdid_flag = 1'b1;
                                                        -> read_id;
                                                end
                                                else if ( IO[7:0] == STAT_CMD ) begin
                                                        READ_Mode = 1'b0;
                                                        status_flag = 1'b1;
                                                end
                                                else if ( IO[7:0] == PRRD_CMD && sr6 && sr5 && !card_op ) begin
                                                        DPRD_Mode = 1'b0;
                                                        parameter_flag = 1'b0;
                                                        unid_flag = 1'b0;
                                                        read_feature_flag = 1'b0;
                                                        READ_Mode = 1'b0;
                                                        RD_Mode = 1'b1;
                                                        parameter_flag = 1'b1;
                                                        -> parameter_read;
                                                end
                                                else if ( IO[7:0] == UNID_CMD && sr6 && sr5 && !card_op ) begin
                                                        DPRD_Mode = 1'b0;
                                                        parameter_flag = 1'b0;
                                                        unid_flag = 1'b0;
                                                        read_feature_flag = 1'b0;
                                                        READ_Mode = 1'b0;
                                                        RD_Mode = 1'b1;
                                                        unid_flag = 1'b1;
                                                        -> unid_read;
                                                end
                                                else if ( IO[7:0] == SETFT_CMD && sr6 && sr5 && !card_op ) begin
                                                        DPRD_Mode = 1'b0;
                                                        parameter_flag = 1'b0;
                                                        unid_flag = 1'b0;
                                                        read_feature_flag = 1'b0;
                                                        RD_Mode = 1'b0;
                                                        READ_Mode = 1'b0;
                                                        set_feature_flag = 1'b1;
                                                        -> set_feature;
                                                        STATE = INIT_STAT;
                                                end
                                                else if ( IO[7:0] == RDFT_CMD && sr6 && sr5 && !card_op ) begin
                                                        DPRD_Mode = 1'b0;
                                                        parameter_flag = 1'b0;
                                                        unid_flag = 1'b0;
                                                        read_feature_flag = 1'b0;
                                                        RD_Mode = 1'b0;
                                                        READ_Mode = 1'b0;
                                                        read_feature_flag = 1'b1;
                                                        -> read_feature;
                                                        STATE = INIT_STAT;
                                                end
                                                else if ( IO[7:0] == PRTRD_CMD ) begin
                                                        DPRD_Mode = 1'b0;
                                                        parameter_flag = 1'b0;
                                                        unid_flag = 1'b0;
                                                        read_feature_flag = 1'b0;
                                                        RD_Mode = 1'b0;
                                                        READ_Mode = 1'b0;
                                                        protect_status_flag = 1'b1;
                                                        STATE = INIT_STAT;
                                                end
                                                else if ( sr6 ) begin
                                                        DPRD_Mode = 1'b0;
                                                        RD_Mode = 1'b0;
                                                end
                                        end
                                        RAND_STAT1: begin
                                                if ( CARD_Mode == 1 ) begin
                                                        STATE = CARD_STAT1;
                                                end
                                                else if ( RANDCARD_Mode == 1 ) begin
                                                        STATE = RANDCARD_STAT1;
                                                end
                                                else begin
                                                        STATE = INIT_STAT;
                                                end

                                                if ( IO[7:0] == RAND_CMD2 ) begin
                                                        Page_EN = 1'b1;
                                                end
                                        end
                                        CARD_STAT1: begin
                                                if ( IO[7:0] == RAND_CMD1 ) begin
                                                        STATE = RAND_STAT1;
                                                end
                                                else if ( IO[7:0] == CARD_CMD1 ) begin
                                                        STATE = CARD_STAT1;
                                                        CARD_Mode = 1'b1;
                                                        CARD_Mode_End = 1'b0;
                                                        -> another_read;
                                                end
                                                else if ( IO[7:0] == CARD_CMD2 ) begin
                                                        STATE = INIT_STAT;
                                                        CARD_Mode = 1'b1;
                                                        CARD_Mode_End = 1'b1;
                                                        -> another_read;
                                                end
                                                else if ( IO[7:0] == STAT_CMD ) begin
                                                        RD_Mode = 1'b0;
                                                        READ_Mode = 1'b0;
                                                        status_flag = 1'b1;
                                                        STATE = INIT_STAT;
                                                end
                                                else begin
                                                        STATE = CARD_STAT1;
                                                end
                                        end
                                        RANDCARD_STAT1: begin
                                                if ( IO[7:0] == RAND_CMD1 ) begin
                                                        STATE = RAND_STAT1;
                                                end
                                                else if ( IO[7:0] == READ_CMD1 ) begin
                                                        STATE = INIT_STAT;
                                                end
                                                else if ( IO[7:0] == CARD_CMD2 ) begin
                                                        STATE = INIT_STAT;
                                                        RANDCARD_Mode = 1'b1;
                                                        RANDCARD_Mode_End = 1'b1;
                                                        -> random_cache_read;
                                                end
                                                else if ( IO[7:0] == STAT_CMD ) begin
                                                        RD_Mode = 1'b0;
                                                        READ_Mode = 1'b0;
                                                        status_flag = 1'b1;
                                                        STATE = INIT_STAT;
                                                end
                                                else begin
                                                        STATE = RANDCARD_STAT1;
                                                end
                                        end
                                        DPRD_STAT1: begin
                                                if ( CARD_Mode == 1 ) begin
                                                        STATE = CARD_STAT1;
                                                end
                                                else if ( RANDCARD_Mode == 1 ) begin
                                                        STATE = RANDCARD_STAT1;
                                                end
                                                else begin
                                                        STATE = INIT_STAT;
                                                end

                                                if ( IO[7:0] == RAND_CMD2 ) begin
                                                        Page_EN = 1'b1;
                                                        Latch_A_OUT = Latch_A;
                                                end
                                        end
                                        PGM_STAT1: begin
                                                if ( IO[7:0] == PGM_CMD2 ) begin
                                                        DPPGM_addr_chk = 1'b0;
                                                        STATE = INIT_STAT;
                                                        if ( Randomizer_Feature[0] == 1'b1 ) begin   // ENPGM = 1
                                                                if ( Latch_A[A_MSB:0] == 1 && Cache0[0] == 8'h00 ) begin
                                                                //              |                          |
                                                                //  Address = 0, Data number = 1      Data = 8'h00
                                                                        -> rand_pgm;
                                                                        
                                                                end
                                                                else begin
                                                                        $display ( $time, "Warning: Address should be 4-byte 00h-00h-00h-00h, Data should be 1-byte 00h when issue Program RANDEN and RANDOPT Confirm operation !!!!!\n" );
                                                                end
                                                        end
                                                        else begin
                                                                if ( capgm_op ) begin
                                                                        -> cache_pgm;
                                                                end
                                                                else begin
                                                                        -> page_pgm;
                                                                end
                                                                $display("[%0t] MXIC_CACHE: Cache0[0]=%h Cache0[1]=%h Cache0[2]=%h", 
                                                                         $time, Cache0[0], Cache0[1], Cache0[2]);
                                                                -> capgm_op_event;
                                                        end
                                                end
                                                else if ( IO[7:0] == CAPGM_CMD2 && Normal_Mode ) begin
                                                        DPPGM_addr_chk = 1'b0;
                                                        STATE = INIT_STAT;
                                                        if ( capgm_op == 1'b0 ) begin
                                                                if ( DPPGM_Mode == 1'b1 ) begin
                                                                        Latch_A_st_CAOP = Latch_A_st;
                                                                        Latch_A_nd_CAOP = Latch_A_nd;
                                                                end
                                                                else begin
                                                                        Latch_A_CAOP = Latch_A;
                                                                end
                                                                capgm_op = 1'b1;
                                                                capgm_op_mode = 1'b1;
                                                                -> page_pgm;
                                                        end
                                                        else begin
                                                                -> cache_pgm;
                                                        end
                                                end
                                                else if ( IO[7:0] == RANDIN_CMD1 ) begin
                                                        STATE = PGM_STAT1;
                                                end
                                                else begin
                                                        DPPGM_addr_chk = 1'b0;
                                                        DPPGM_Mode = 1'b0;
                                                        CMD_11h_flag = 1'b0;
                                                        STATE = INIT_STAT;
                                                end
                                        end
                                        ERS_STAT1: begin
                                                if ( IO[7:0] == BKERS_CMD2 ) begin
                                                        DPERS_addr_chk = 1'b0;
                                                        STATE =  INIT_STAT;
                                                        -> block_ers;
                                                end
                                                else begin
                                                        DPERS_addr_chk = 1'b0;
                                                        DPERS_Mode = 1'b0;
                                                        STATE = INIT_STAT;
                                                end
                                        end

        
                                        default: begin
                                                STATE = INIT_STAT;
                                        end
                                endcase

                                ADR_CYC = 0;
                                if ( enhance_status_flag || STATE == ERS_STAT1 || unprotect_low_flag || unprotect_upper_flag || protect_status_flag ) begin
                                        ADR_CYC = 2;
                                end

                        end

                end

        end
end

    /*----------------------------------------------------------------------*/
    /* Output (Read) Data if control signals do not disable                 */
    /*----------------------------------------------------------------------*/
always @ ( posedge RE_B ) begin: offoutput
        if ( Power_Up ) begin
                #Toh;
                if ( OUT_EN == 1'b1 && RE_B ) begin
                        OUTZ_EN = 1;
                end
                #0.1;
                if ( OUT_EN == 1'b1 && RE_B ) begin
                        OUT_EN = 0;
                        OUTZ_EN = 1;
                end
        end
end

always @ ( negedge RE_B ) begin
        if ( Power_Up ) begin
                #Trloh;
                if ( OUT_EN == 1'b1 ) begin
                        OUT_EN = 0;
                        OUTZ_EN = 1;
                end
        end
end

always @ ( posedge RE_B ) begin:Trhz_process
        if ( Power_Up ) begin
                #Trhz OUTZ_EN = 0;
        end
end

always @ ( OUT_EN_event ) begin
        #Tcoh;
        if ( CE_B ) begin
                OUT_EN = 0;
        end
end

always @ (negedge WE_B ) begin
        OUT_EN = 0;
        disable read_mode;
end


// *==============================================================================================
// * Module blocks Declaration
// *==============================================================================================

    /*----------------------------------------------------------------------*/
    /*  Read related blocks                                                 */
    /*----------------------------------------------------------------------*/
always @ ( internal_read ) begin: load_pagebuffer1
        DPRD_Mode_4TMP = DPRD_Mode;
        #Twb;

        if ( CARD_Mode == 1'b1 || RANDCARD_Mode == 1'b1 ) begin
                if ( DPRD_Mode_4TMP == 1'b1 ) begin
                        Latch_A_OUT = Latch_A_st_4TMP;
                        Latch_A[CA_MSB:0] = 0;
                        Latch_A_st_4TMP[A_MSB:CA_MSB+1] = Latch_A_st_CAOP[A_MSB:CA_MSB+1];
                        Latch_A_st_4TMP[CA_MSB:0] = 0;
                        Latch_A_nd_4TMP[A_MSB:CA_MSB+1] = Latch_A_nd_CAOP[A_MSB:CA_MSB+1];
                        Latch_A_nd_4TMP[CA_MSB:0] = 0;
                end
                else begin
                        Latch_A_OUT = Latch_A_4TMP;
                        Latch_A[CA_MSB:0] = 0;
                        Latch_A_4TMP[A_MSB:CA_MSB+1] = Latch_A_CAOP[A_MSB:CA_MSB+1];
                        Latch_A_4TMP[CA_MSB:0] = 0;
                end
        end
        else begin
                if ( DPRD_Mode_4TMP == 1'b1 ) begin
                        Latch_A_st_4TMP[A_MSB:CA_MSB+1] = Latch_A_st[A_MSB:CA_MSB+1];
                        Latch_A_st_4TMP[CA_MSB:0] = 0;
                        Latch_A_nd_4TMP[A_MSB:CA_MSB+1] = Latch_A_nd[A_MSB:CA_MSB+1];
                        Latch_A_nd_4TMP[CA_MSB:0] = 0;
                        Latch_A_OUT = Latch_A_st_4TMP;
                        Latch_A_st_CAOP[A_MSB:CA_MSB+1] = Latch_A_st_4TMP[A_MSB:CA_MSB+1];
                        Latch_A_nd_CAOP[A_MSB:CA_MSB+1] = Latch_A_nd_4TMP[A_MSB:CA_MSB+1];
                end
                else begin
                        Latch_A_4TMP[A_MSB:CA_MSB+1] = Latch_A[A_MSB:CA_MSB+1];
                        Latch_A_4TMP[CA_MSB:0] = 0;
                        Latch_A_OUT = Latch_A_4TMP;
                        Latch_A_CAOP[A_MSB:CA_MSB+1] = Latch_A_4TMP[A_MSB:CA_MSB+1];
                end
        end

        sr5 = 1'b0;
        sr6 = 1'b0;
        sr5_flag = 1'b0;
        Page_EN = 1'b0;
        if ( ECC_Enable == 1'b1 ) begin
                if ( DPRD_Mode_4TMP == 1'b1 )
                        #(Tdrcbsy_ecc-Twb);
                else
                        #(Trcbsy_ecc-Twb);
        end
        else begin
                #(Trcbsy-Twb);
        end
        if ( CARD_Mode == 1'b1 || RANDCARD_Mode == 1'b1 ) begin
                sr6 = 1'b1;
                -> load_pb2cache;
                Page_EN = 1'b1;
        end
        if ( ECC_Enable == 1'b1 ) begin
                if ( DPRD_Mode_4TMP == 1'b1 )
                        #(Tdr_ecc-Tdrcbsy_ecc);
                else
                        #(Tr_ecc-Trcbsy_ecc);
        end
        else begin
                if ( DPRD_Mode_4TMP == 1'b1 )
                        #(Tdr-Trcbsy);
                else
                        #(Tr-Trcbsy);
        end
        if ( Array_Mode[0] == 1'b0 ) begin
                if ( DPRD_Mode_4TMP == 1'b1 ) begin
                        if ( block_protect(Latch_A_st_4TMP) == 1'b0 && block_protect(Latch_A_nd_4TMP) == 1'b0 && WP_B_IN ) begin
                                sr7 = 1'b1;
                        end
                        else begin
                                sr7 = 1'b0;
                        end
                        if ( Latch_A_st_4TMP[CA_MSB+7] == 1'b1 ) begin
                                plane_flag = 1'b1;
                                for ( pa_count = 0; pa_count <= Top_Cache; pa_count = pa_count + 1) begin
                                        PBuff1[pa_count] = ARRAY[Latch_A_st_4TMP[A_MSB:0] + pa_count];
                                end
                        end
                        else begin
                                plane_flag = 1'b0;
                                for ( pa_count = 0; pa_count <= Top_Cache; pa_count = pa_count + 1) begin
                                        PBuff0[pa_count] = ARRAY[Latch_A_st_4TMP[A_MSB:0] + pa_count];
                                end
                        end
                        if ( Latch_A_nd_4TMP[CA_MSB+7] == 1'b1 ) begin
                                plane_flag = 1'b1;
                                for ( pa_count = 0; pa_count <= Top_Cache; pa_count = pa_count + 1) begin
                                        PBuff1[pa_count] = ARRAY[Latch_A_nd_4TMP[A_MSB:0] + pa_count];
                                end
                        end
                        else begin
                                plane_flag = 1'b0;
                                for ( pa_count = 0; pa_count <= Top_Cache; pa_count = pa_count + 1) begin
                                        PBuff0[pa_count] = ARRAY[Latch_A_nd_4TMP[A_MSB:0] + pa_count];
                                end
                        end
                end
                else begin
                        if ( block_protect(Latch_A_4TMP) == 1'b0 && WP_B_IN ) begin
                                sr7 = 1'b1;
                        end
                        else begin
                                sr7 = 1'b0;
                        end
                        if ( Latch_A_4TMP[CA_MSB+7] == 1'b1 ) begin
                                plane_flag = 1'b1;
                                for ( pa_count = 0; pa_count <= Top_Cache; pa_count = pa_count + 1) begin
                                        PBuff1[pa_count] = ARRAY[Latch_A_4TMP[A_MSB:0] + pa_count];
                                end
                        end
                        else begin
                                plane_flag = 1'b0;
                                for ( pa_count = 0; pa_count <= Top_Cache; pa_count = pa_count + 1) begin
                                        PBuff0[pa_count] = ARRAY[Latch_A_4TMP[A_MSB:0] + pa_count];
                                end
                        end
                end
        end
        else begin
                if ( DPRD_Mode_4TMP == 1'b1 ) begin
                        $display ( $time, "Warning: Two Plane Read command invalid in OTP Mode\n" );
                end
                else if ( Array_Mode[1] == 1'b0 ) begin
                        if ( OTP_Protect == 1'b0 ) begin
                                sr7 = 1'b1;
                        end
                        else begin
                                sr7 = 1'b0;
                        end
                        if ( Latch_A_4TMP[A_MSB:CA_MSB+1] >= 24'h000002 && Latch_A_4TMP[A_MSB:CA_MSB+1] <= 24'h00001f ) begin
                                if ( Latch_A_4TMP[CA_MSB+7] == 1'b1 ) begin
                                        plane_flag = 1'b1;
                                        for ( pa_count = 0; pa_count <= Top_Cache; pa_count = pa_count + 1) begin
                                                PBuff1[pa_count] = OTP_ARRAY[Latch_A_4TMP[A_MSB:0] + pa_count];
                                        end
                                end
                                else begin
                                        plane_flag = 1'b0;
                                        for ( pa_count = 0; pa_count <= Top_Cache; pa_count = pa_count + 1) begin
                                                PBuff0[pa_count] = OTP_ARRAY[Latch_A_4TMP[A_MSB:0] + pa_count];
                                        end
                                end
                        end
                        else begin
                                $display ( $time, "Warning: The address of OTP is located on 02h-1Fh page address\n" );
                        end
                end
        end
        if ( CARD_Mode == 1'b0 && RANDCARD_Mode == 1'b0 ) begin
                sr6 = 1'b1;
                -> load_pb2cache;
                Page_EN = 1'b1;
                $display("[%0t] MXIC: Page_EN set, Cache0[0]=%h Cache0[1]=%h", 
         $time, Cache0[0], Cache0[1]);
        end
        sr5 = 1'b1;
        sr5_flag = 1'b1;
end

always @ ( another_read ) begin: load_pagebuffer2
        sr6 <= #Twb 1'b0;
        if ( CARD_Mode == 1'b1 && CARD_Mode_End == 1'b0 ) begin
                if ( DPRD_Mode == 1'b1 ) begin
                        Latch_A_st_CAOP[A_MSB:CA_MSB+1] = Latch_A_st_CAOP[A_MSB:CA_MSB+1] + 1;
                        Latch_A_nd_CAOP[A_MSB:CA_MSB+1] = Latch_A_nd_CAOP[A_MSB:CA_MSB+1] + 1;
                end
                else begin
                        Latch_A_CAOP[A_MSB:CA_MSB+1] = Latch_A_CAOP[A_MSB:CA_MSB+1] + 1;
                end
        end
        if ( sr5 == 1'b0 ) begin
                wait ( sr5 );
                sr5 = 1'b0;
        end
        if ( CARD_Mode_End == 1'b1 ) begin
                CARD_Mode = 1'b0;
                READ_Mode = 1'b0;
        end
        if ( CARD_Mode == 1'b1 ) begin
                -> internal_read;
        end
        else begin
                -> last_read;
        end
end

always @ ( last_read ) begin: load_pagebuffer3
        DPRD_Mode_4TMP = DPRD_Mode;
        #Twb;
        sr5 = 1'b0;
        sr6 = 1'b0;
        sr5_flag = 1'b0;
        Page_EN = 1'b0;
        if ( ECC_Enable == 1'b1 ) begin
                if ( DPRD_Mode_4TMP == 1'b1 )
                        #(Tdrcbsy_ecc-Twb);
                else
                        #(Trcbsy_ecc-Twb);
        end
        else begin
                #(Trcbsy-Twb);
        end
        Latch_A_OUT = Latch_A_4TMP;
        Latch_A[CA_MSB:0] = 0;
        sr5 = 1'b1;
        sr6 = 1'b1;
        sr5_flag = 1'b1;
        -> load_pb2cache;
        Page_EN = 1'b1;
        if ( DPRD_Mode_4TMP == 1'b1 ) begin
                Latch_A_OUT = Latch_A_st_4TMP;
                Latch_A[CA_MSB:0] = 0;
        end
end

always @ ( random_cache_read ) begin: load_pagebuffer4
        sr6 <= #Twb 1'b0;
        if ( RANDCARD_Mode == 1'b1 && RANDCARD_Mode_End == 1'b0 ) begin
                if ( DPRD_Mode == 1'b1 ) begin
                        Latch_A_st_CAOP[A_MSB:CA_MSB+1] = Latch_A_st[A_MSB:CA_MSB+1];
                        Latch_A_nd_CAOP[A_MSB:CA_MSB+1] = Latch_A_nd[A_MSB:CA_MSB+1];
                end
                else begin
                        Latch_A_CAOP[A_MSB:CA_MSB+1] = Latch_A[A_MSB:CA_MSB+1];
                end
        end     
        if ( sr5 == 1'b0 ) begin
                wait ( sr5 );
                sr5 = 1'b0;
        end
        if ( RANDCARD_Mode_End == 1'b1 ) begin
                RANDCARD_Mode = 1'b0;
                READ_Mode = 1'b0;
        end
        if ( RANDCARD_Mode == 1'b1 ) begin
                -> internal_read;
        end
        else begin
                -> last_read;
        end
end

always @ ( load_pb2cache ) begin: load_cache
        if ( DPRD_Mode_4TMP == 1'b1 ) begin
                for ( pa_count = 0; pa_count <= Top_Cache; pa_count = pa_count + 1) begin
                        Cache1[pa_count] = PBuff1[pa_count];
                end
                for ( pa_count = 0; pa_count <= Top_Cache; pa_count = pa_count + 1) begin
                        Cache0[pa_count] = PBuff0[pa_count];
                end
        end
        else begin
                if ( Latch_A_OUT[CA_MSB+7] == 1'b1 ) begin
                        plane_flag = 1'b1;
                        for ( pa_count = 0; pa_count <= Top_Cache; pa_count = pa_count + 1) begin
                                Cache1[pa_count] = PBuff1[pa_count];
                        end
                end
                else begin
                        plane_flag = 1'b0;
                        for ( pa_count = 0; pa_count <= Top_Cache; pa_count = pa_count + 1) begin
                                Cache0[pa_count] = PBuff0[pa_count];
                        end
                end
        end
end

always @ ( parameter_read ) begin: load_pagebuffer5
        wait ( ADR_CYC == 1 );
        #Twb;
        sr5 = 1'b0;
        sr6 = 1'b0;
        sr5_flag = 1'b0;
        Page_EN = 1'b0;
        if ( ECC_Enable == 1'b1 ) begin
                #(Tr_ecc-Twb);
        end
        else begin
                #(Tr-Twb);
        end
        if ( Latch_A[7:0] == 8'h00 ) begin
                Latch_A_4TMP = 0;
                if ( Latch_A_4TMP[CA_MSB+7] == 1'b1 ) begin
                        plane_flag = 1'b1;
                        for ( pa_count = 0; pa_count <= Top_Cache; pa_count = pa_count + 1) begin
                                PBuff1[pa_count] = (IO_MSB==7) ? PARA_ARRAY[pa_count] : {8'hff,PARA_ARRAY[pa_count]};
                        end
                end
                else begin
                        plane_flag = 1'b0;
                        for ( pa_count = 0; pa_count <= Top_Cache; pa_count = pa_count + 1) begin
                                PBuff0[pa_count] = (IO_MSB==7) ? PARA_ARRAY[pa_count] : {8'hff,PARA_ARRAY[pa_count]};
                        end
                end
        end
        else begin
                $display ( $time, "Warning: Address should be 00h when issue parameter page read\n" );
        end
        sr6 = 1'b1;
        Page_EN = 1'b1;
        sr5 = 1'b1;
        sr5_flag = 1'b1;
        Latch_A_OUT = Latch_A_4TMP;
        -> load_pb2cache;
end

always @ ( unid_read ) begin: load_pagebuffer6
        wait ( ADR_CYC == 1 );
        #Twb;
        sr5 = 1'b0;
        sr6 = 1'b0;
        sr5_flag = 1'b0;
        Page_EN = 1'b0;
        if ( ECC_Enable == 1'b1 ) begin
                #(Tr_ecc-Twb);
        end
        else begin
                #(Tr-Twb);
        end
        if ( Latch_A[7:0] == 8'h00 ) begin
                Latch_A_4TMP = 0;
                if ( Latch_A_4TMP[CA_MSB+7] == 1'b1 ) begin
                        plane_flag = 1'b1;
                        for ( pa_count = 0; pa_count <= Top_Cache; pa_count = pa_count + 1) begin
                                PBuff1[pa_count] = (IO_MSB==7) ? UNID_ARRAY[pa_count%(UNID_Top_Add+1)] : {8'hff,UNID_ARRAY[pa_count%(UNID_Top_Add+1)]};
                        end
                end
                else begin
                        plane_flag = 1'b0;
                        for ( pa_count = 0; pa_count <= Top_Cache; pa_count = pa_count + 1) begin
                                PBuff0[pa_count] = (IO_MSB==7) ? UNID_ARRAY[pa_count%(UNID_Top_Add+1)] : {8'hff,UNID_ARRAY[pa_count%(UNID_Top_Add+1)]};
                        end
                end
        end
        else begin
                $display ( $time, "Warning: Address should be 00h when issue unique id read\n" );
        end
        sr6 = 1'b1;
        Page_EN = 1'b1;
        sr5 = 1'b1;
        sr5_flag = 1'b1;
        Latch_A_OUT = Latch_A_4TMP;
        -> load_pb2cache;
end

always @ ( read_id ) begin: read_id_p
        for ( j = 0; j <= 5; j = j + 1) begin
                id_buffer1[j] = 8'hx;
        end
        for ( j = 0; j <= 3; j = j + 1) begin
                id_buffer2[j] = 8'hx;
        end
        wait ( ADR_CYC == 1 );
        for ( j = 0; j <= 5; j = j + 1) begin
                id_buffer1[j] = id1[j];
        end
        for ( j = 0; j <= 3; j = j + 1) begin
                id_buffer2[j] = id2[j];
        end
end

always @ ( read_feature ) begin: load_pagebuffer7
        FEAT_ARRAY_DUM1 = 8'hx;
        FEAT_ARRAY_DUM2 = 8'hx;
        FEAT_ARRAY_DUM3 = 8'hx;
        FEAT_ARRAY_DUM4 = 8'hx;
        wait ( ADR_CYC == 1 );
        #Twb;
        Feature_EN = 1'b0;
        sr5 = 1'b0;
        sr6 = 1'b0;
        sr5_flag = 1'b0;
        #Tfeat;
        FEAT_ARRAY_DUM1 = FEAT_ARRAY1[Latch_A[7:0]];
        FEAT_ARRAY_DUM2 = FEAT_ARRAY2[Latch_A[7:0]];
        FEAT_ARRAY_DUM3 = FEAT_ARRAY3[Latch_A[7:0]];
        FEAT_ARRAY_DUM4 = FEAT_ARRAY4[Latch_A[7:0]];
        sr6 = 1'b1;
        sr5 = 1'b1;
        sr5_flag = 1'b1;
        Feature_EN = 1'b1;
end

always @ ( read_ere ) begin: read_ere_p
        ERE_status_dum = 8'hx;
        wait ( ADR_CYC == 3 );
        ERE_status_dum = ERE_status;
end

always @ ( negedge RE_B ) begin
        if ( Power_Up && !CE_B ) begin
                -> Read_Q;
        end
end

always @ ( negedge CE_B ) begin
        if ( Power_Up && status_flag && !RE_B ) begin
                -> Read_Q;
        end
end

    
always @ ( Read_Q ) begin:read_mode
        disable Trhz_process;
        #Trea;
        -> OUT_Q;
end

always @ ( OUT_Q ) begin
        OUT_EN = 1'b1;
        Q_Reg = 16'hz;
        if ( status_flag == 1'b1 ) begin
                Q_Reg[7:0] = {(sr7&&WP_B_IN),sr6,sr5,sr4,sr3,sr2,sr1,sr0};
        end
        else if ( enhance_status_flag == 1'b1 ) begin
                if ( Latch_A[CA_MSB+7] == 1'b1 ) begin
                        Q_Reg[7:0] = {(sr7&&WP_B_IN),sr6,sr5,sr4,sr3,sr2,sr1_1,sr0_1};
                end
                else begin
                        Q_Reg[7:0] = {(sr7&&WP_B_IN),sr6,sr5,sr4,sr3,sr2,sr1_0,sr0_0};
                end
        end
        else if ( rdid_flag == 1'b1 ) begin
                if ( Latch_A[7:0] == 8'h00 ) begin
                        {id_buffer1[5], id_buffer1[4], id_buffer1[3], id_buffer1[2], id_buffer1[1], id_buffer1[0], Q_Reg[7:0]} = 
                                {id_buffer1[0], id_buffer1[5], id_buffer1[4], id_buffer1[3], id_buffer1[2], id_buffer1[1], id_buffer1[0]};
                        
                end
                else if ( Latch_A[7:0] == 8'h20 ) begin
                        {id_buffer2[3], id_buffer2[2], id_buffer2[1], id_buffer2[0], Q_Reg[7:0]} = 
                                {id_buffer2[0], id_buffer2[3], id_buffer2[2], id_buffer2[1], id_buffer2[0]};
                        
                end
                else begin
                        $display ( $time, "Warning: Address should be 00h or 20h when ID read\n" );
                end
        end
        else if ( Feature_EN == 1'b1 ) begin
                {FEAT_ARRAY_DUM4, FEAT_ARRAY_DUM3, FEAT_ARRAY_DUM2, FEAT_ARRAY_DUM1, Q_Reg[7:0]} =
                        {FEAT_ARRAY_DUM1, FEAT_ARRAY_DUM4, FEAT_ARRAY_DUM3, FEAT_ARRAY_DUM2, FEAT_ARRAY_DUM1};
        end
        else if ( read_ere_flag == 1'b1 ) begin
                Q_Reg[7:0] = ERE_status_dum;
        end
        else if ( protect_status_flag == 1'b1 ) begin
                Q_Reg[0] = BP_Solid;
                Q_Reg[1] = ~BP_Solid;
                Q_Reg[2] = ~block_protect(Latch_A);
        end
        else if ( Page_EN == 1'b1 ) begin
                Latch_A_OUT = {Latch_A_OUT[A_MSB:CA_MSB+1], Latch_A[CA_MSB:0]};
                if ( Latch_A[CA_MSB:0] <= Top_Cache ) begin
                        if ( Latch_A_OUT[CA_MSB+7] == 1'b1 ) begin
                                plane_flag = 1'b1;
                                Q_Reg = Cache1[Latch_A[CA_MSB:0]];
                        end
                        else begin
                                plane_flag = 1'b0;
                                Q_Reg = Cache0[Latch_A[CA_MSB:0]];
                        end
                        Latch_A[CA_MSB:0] = Latch_A[CA_MSB:0] + 1;
                end
                else begin
                        Q_Reg = 16'hz;
                end
                last_addr_flag = (Latch_A[CA_MSB:0] > Top_Cache) ? 1'b1 : 1'b0;
        end
end

    /*----------------------------------------------------------------------*/
    /*  Program RANDEN and RANDOPT                                          */
    /*----------------------------------------------------------------------*/
always @ ( rand_pgm ) begin: rand_pgm_p
        #Twb;
        Latch_A_4TMP[A_MSB:CA_MSB+1] = Latch_A[A_MSB:CA_MSB+1];
        Latch_A_4TMP[CA_MSB:0] = 0;
        sr0_0 = 1'b0;
        sr0 = sr0_0;
        sr1_0 = sr1_0_pre;
        sr1_1 = sr1_1_pre;
        sr1 = sr1_0 || sr1_1;
        sr5 = 1'b0;
        sr6 = 1'b0;
        sr5_flag = 1'b0;
        pgm_busy = 1'b1;
        if ( ECC_Enable == 1'b1 ) begin
                #Tprog_ecc;
        end
        else begin
                #Tprog;
        end
        FEAT_ARRAY1[8'hb0] = FEAT_ARRAY1[8'hb0] | { 5'b0, RANDOPT_TMP, RANDEN_TMP, 1'b0 };
        sr1_0_pre = 1'b0;
        sr5 = 1'b1;
        sr6 = 1'b1;
        sr5_flag = 1'b1;
        pgm_busy = 1'b0;
end

    /*----------------------------------------------------------------------*/
    /*  Program related blocks                                              */
    /*----------------------------------------------------------------------*/
always @ ( page_pgm ) begin: page_pgm_p
        DPPGM_Mode_4TMP = DPPGM_Mode;
        #Twb;
        if ( capgm_op_mode == 1'b1 ) begin
                if ( DPPGM_Mode_4TMP == 1'b1 ) begin
                        Latch_A_st_4TMP[A_MSB:CA_MSB+1] = Latch_A_st_CAOP[A_MSB:CA_MSB+1];
                        Latch_A_st_4TMP[CA_MSB:0] = 0;
                        Latch_A_4TMP[A_MSB:CA_MSB+1] = Latch_A_nd_CAOP[A_MSB:CA_MSB+1];
                        Latch_A_4TMP[CA_MSB:0] = 0;
                end
                else begin
                        Latch_A_4TMP[A_MSB:CA_MSB+1] = Latch_A_CAOP[A_MSB:CA_MSB+1];
                        Latch_A_4TMP[CA_MSB:0] = 0;
                end
        end
        else begin
                if ( DPPGM_Mode_4TMP == 1'b1 ) begin
                        Latch_A_st_4TMP[A_MSB:CA_MSB+1] = Latch_A_st[A_MSB:CA_MSB+1];
                        Latch_A_st_4TMP[CA_MSB:0] = 0;
                        Latch_A_4TMP[A_MSB:CA_MSB+1] = Latch_A_nd[A_MSB:CA_MSB+1];
                        Latch_A_4TMP[CA_MSB:0] = 0;
                end
                else begin
                        Latch_A_4TMP[A_MSB:CA_MSB+1] = Latch_A[A_MSB:CA_MSB+1];
                        Latch_A_4TMP[CA_MSB:0] = 0;
                end
        end
        capgm_op_mode = 1'b0;
        if ( DPPGM_Mode_4TMP == 1'b1 ) begin
                sr0_0 = 1'b0;
                sr1_0 = sr1_0_pre;
                sr0_1 = 1'b0;
                sr1_1 = sr1_1_pre;
                sr0 = sr0_0 || sr0_1;
                sr1 = sr1_0 || sr1_1;
        end
        else begin
                if ( Latch_A_4TMP[CA_MSB+7] == 1'b1 ) begin
                        sr0_1 = 1'b0;
                        sr0 = sr0_1;
                end
                else begin
                        sr0_0 = 1'b0;
                        sr0 = sr0_0;
                end
                sr1_0 = sr1_0_pre;
                sr1_1 = sr1_1_pre;
                sr1 = sr1_0 || sr1_1;
        end
        sr5 = 1'b0;
        sr6 = 1'b0;
        sr5_flag = 1'b0;
        pgm_busy = 1'b1;
        if ( capgm_op == 1'b1 ) begin   
                #(Tcbsy);
        end
        if ( DPPGM_Mode_4TMP == 1'b1 ) begin
                for ( pa_count = 0; pa_count <= Top_Cache; pa_count = pa_count + 1) begin
                        PBuff0[pa_count] = Cache0[pa_count];
                        PBuff1[pa_count] = Cache1[pa_count];
                end
        end
        else begin
                if ( Latch_A_4TMP[CA_MSB+7] == 1'b1 ) begin
                        plane_flag = 1'b1;
                        for ( pa_count = 0; pa_count <= Top_Cache; pa_count = pa_count + 1) begin
                                PBuff1[pa_count] = Cache1[pa_count];
                        end
                end
                else begin
                        plane_flag = 1'b0;
                        for ( pa_count = 0; pa_count <= Top_Cache; pa_count = pa_count + 1) begin
                                PBuff0[pa_count] = Cache0[pa_count];
                                
                        end
                end
                $display("[%0t] MXIC_PBUFF: PBuff0[0]=%h PBuff0[1]=%h protect=%b WP_B=%b",
                         $time, PBuff0[0], PBuff0[1], block_protect(Latch_A_4TMP), WP_B_IN);
        end
        if ( capgm_op == 1'b1 ) begin
                sr6 = 1'b1;
                CMD_11h_flag = 1'b0;
        end
        if ( Array_Mode[0] == 1'b0 && ERE_Mode[0] == 1'b0 && PBL_Mode[0] == 1'b0 ) begin
                if ( DPPGM_Mode_4TMP == 1'b1 ) begin
                        if ( block_protect(Latch_A_4TMP) == 1'b1 && block_protect(Latch_A_st_4TMP) == 1'b1 || !WP_B_IN ) begin
                                if ( capgm_op == 1'b1 ) begin
                                        if ( Tpbsy > Tcbsy )
                                                #(Tpbsy-Tcbsy);
                                end
                                else
                                        #Tpbsy;
                        end
                        else if ( ere_area(Latch_A_4TMP) == 1'b1 || ere_area(Latch_A_st_4TMP) == 1'b1 ) begin
                                if ( capgm_op == 1'b1 ) begin
                                        if ( Tprog_ere > Tcbsy )
                                                #( Tprog_ere-Tcbsy);
                                end
                                else
                                        #Tprog_ere;
                        end
                        else if ( ECC_Enable == 1'b1 ) begin
                                if ( capgm_op == 1'b1 ) begin
                                        if ( Tdprog_ecc > Tcbsy )
                                                #( Tdprog_ecc-Tcbsy);
                                end
                                else
                                        #Tdprog_ecc;
                        end
                        else begin
                                if ( capgm_op == 1'b1 ) begin
                                        if ( Tprog > Tcbsy )
                                                #(Tprog-Tcbsy);
                                end
                                else
                                        #Tprog;
                        end
                end
                else begin
                        if ( block_protect(Latch_A_4TMP) == 1'b1 || !WP_B_IN ) begin
                                if ( capgm_op == 1'b1 ) begin
                                        if ( Tpbsy > Tcbsy )
                                                #(Tpbsy-Tcbsy);
                                end
                                else
                                        #Tpbsy;
                        end
                        else if ( ere_area(Latch_A_4TMP) == 1'b1 ) begin
                                if ( capgm_op == 1'b1 ) begin
                                        if ( Tprog_ere > Tcbsy )
                                                #( Tprog_ere-Tcbsy);
                                end
                                else
                                        #Tprog_ere;
                        end
                        else if ( ECC_Enable == 1'b1 ) begin
                                if ( capgm_op == 1'b1 ) begin
                                        if ( Tdprog_ecc > Tcbsy )
                                                #( Tprog_ecc-Tcbsy);
                                end
                                else
                                        #Tprog_ecc;
                        end
                        else begin
                                if ( capgm_op == 1'b1 ) begin
                                        if ( Tprog > Tcbsy )
                                                #(Tprog-Tcbsy);
                                end
                                else
                                        #Tprog;
                        end
                end
                if ( block_protect(Latch_A_4TMP) == 1'b0 && WP_B_IN ) begin // protection check
                        if ( PGM_Count[Latch_A_4TMP[A_MSB:CA_MSB+1]] == NOP ) begin
                                $display($time,"Warning: The page in address PA[A_MSB:CA_MSB+1]=%h programmed times reaches NOP limit\n",Latch_A_4TMP[A_MSB:CA_MSB+1]);
                        end
                        else begin
                                PGM_Count[Latch_A_4TMP[A_MSB:CA_MSB+1]] = PGM_Count[Latch_A_4TMP[A_MSB:CA_MSB+1]] + 1;
                                if ( Latch_A_4TMP[CA_MSB+7] == 1'b1 ) begin
                                        for ( pa_count = 0; pa_count <= Top_Cache; pa_count = pa_count + 1) begin
                                                ARRAY[Latch_A_4TMP[A_MSB:0] + pa_count] = PBuff1[pa_count] & ARRAY[Latch_A_4TMP[A_MSB:0] + pa_count];
                                        end
                                        sr0_1 = 1'b0;
                                        sr1_1_pre = 1'b0;
                                        sr0 = sr0_1;
                                end
                                else begin
                                        for ( pa_count = 0; pa_count <= Top_Cache; pa_count = pa_count + 1) begin
                                                ARRAY[Latch_A_4TMP[A_MSB:0] + pa_count] = PBuff0[pa_count] & ARRAY[Latch_A_4TMP[A_MSB:0] + pa_count];
                                        end
                                        $display("[%0t] MXIC_ARRAY: ARRAY[0]=%h ARRAY[1]=%h ARRAY[2]=%h",
                                                 $time, ARRAY[0], ARRAY[1], ARRAY[2]);
                                        sr0_0 = 1'b0;
                                        sr1_0_pre = 1'b0;
                                        sr0 = sr0_0;
                                end
                        end
                        sr7 = 1'b1; 
                end // protection check
                else begin
                        if ( Latch_A_4TMP[CA_MSB+7] == 1'b1 ) begin
                                sr0_1 = 1'b1;
                                sr1_1_pre = 1'b1;
                                sr0 = sr0_1;
                        end
                        else begin
                                sr0_0 = 1'b1;
                                sr1_0_pre = 1'b1;
                                sr0 = sr0_0;
                        end
                        sr7 = 1'b0;
                end
                if ( DPPGM_Mode_4TMP == 1'b1 ) begin
                        if ( block_protect(Latch_A_st_4TMP) == 1'b0 && WP_B_IN ) begin // protection check
                                if ( PGM_Count[Latch_A_st_4TMP[A_MSB:CA_MSB+1]] == NOP ) begin
                                        $display($time,"Warning: The page in address PA[A_MSB:CA_MSB+1]=%h programmed times reaches NOP limit\n",Latch_A_st_4TMP[A_MSB:CA_MSB+1]);
                                end
                                else begin
                                        PGM_Count[Latch_A_st_4TMP[A_MSB:CA_MSB+1]] = PGM_Count[Latch_A_st_4TMP[A_MSB:CA_MSB+1]] + 1;
                                        if ( Latch_A_st_4TMP[CA_MSB+7] == 1'b1 ) begin
                                                for ( pa_count = 0; pa_count <= Top_Cache; pa_count = pa_count + 1) begin
                                                        ARRAY[Latch_A_st_4TMP[A_MSB:0] + pa_count] = PBuff1[pa_count] & ARRAY[Latch_A_st_4TMP[A_MSB:0] + pa_count];
                                                end
                                                sr0_1 = 1'b0;
                                                sr1_1_pre = 1'b0;
                                        end
                                        else begin
                                                for ( pa_count = 0; pa_count <= Top_Cache; pa_count = pa_count + 1) begin
                                                        ARRAY[Latch_A_st_4TMP[A_MSB:0] + pa_count] = PBuff0[pa_count] & ARRAY[Latch_A_st_4TMP[A_MSB:0] + pa_count];
                                                end
                                                sr0_1 = 1'b0;
                                                sr1_1_pre = 1'b0;
                                        end
                                end
                                sr7 = 1'b1; 
                        end // protection check
                        else begin
                                if ( Latch_A_st_4TMP[CA_MSB+7] == 1'b1 ) begin
                                        sr0_1 = 1'b1;
                                        sr1_1_pre = 1'b1;
                                end
                                else begin
                                        sr0_0 = 1'b1;
                                        sr1_0_pre = 1'b1;
                                end
                                sr7 = 1'b0;
                        end
                end
        end
        else if ( Array_Mode[0] == 1'b1 && ERE_Mode[0] == 1'b0 && PBL_Mode[0] == 1'b0 && DPPGM_Mode_4TMP == 1'b0 ) begin
                if ( Array_Mode[1] == 1'b0 && OTP_Protect == 1'b0 ) begin // protection check
                        if ( Latch_A_4TMP[A_MSB:CA_MSB+1] >= 24'h000002 && Latch_A_4TMP[A_MSB:CA_MSB+1] <= 24'h00001f ) begin
                                if ( ECC_Enable == 1'b1 ) begin
                                        if ( capgm_op == 1'b1 ) begin
                                                if ( Tprog_ecc > Tcbsy )
                                                        #( Tprog_ecc-Tcbsy);
                                        end
                                        else
                                                #Tprog_ecc;
                                end
                                else begin
                                        if ( capgm_op == 1'b1 ) begin
                                                if ( Tprog > Tcbsy )
                                                        #(Tprog-Tcbsy);
                                        end
                                        else
                                                #Tprog;
                                end
                                if ( OTP_PGM_Count[Latch_A_4TMP[A_MSB:CA_MSB+1]] == OTP_NOP ) begin
                                        $display($time,"Warning: The page in OTP address PA[A_MSB:CA_MSB+1]=%h programmed times reaches OTP_NOP limit\n",Latch_A_4TMP[A_MSB:CA_MSB+1]);
                                end
                                else begin
                                        OTP_PGM_Count[Latch_A_4TMP[A_MSB:CA_MSB+1]] = OTP_PGM_Count[Latch_A_4TMP[A_MSB:CA_MSB+1]] + 1;
                                        if ( Latch_A_4TMP[CA_MSB+7] == 1'b1 ) begin
                                                for ( pa_count = 0; pa_count <= Top_Cache; pa_count = pa_count + 1) begin
                                                        OTP_ARRAY[Latch_A_4TMP[A_MSB:0] + pa_count] = PBuff1[pa_count] & OTP_ARRAY[Latch_A_4TMP[A_MSB:0] + pa_count];
                                                end
                                                sr0_1 = 1'b0;
                                                sr0 = sr0_1;
                                        end
                                        else begin
                                                for ( pa_count = 0; pa_count <= Top_Cache; pa_count = pa_count + 1) begin
                                                        OTP_ARRAY[Latch_A_4TMP[A_MSB:0] + pa_count] = PBuff0[pa_count] & OTP_ARRAY[Latch_A_4TMP[A_MSB:0] + pa_count];
                                                end
                                                sr0_0 = 1'b0;
                                                sr0 = sr0_0;
                                        end
                                end
                                sr7 = 1'b1; 
                        end
                        else begin
                                $display ( $time, "Warning: The address of OTP is located on 02h-1Fh page address\n" );
                        end
                end // protection check
                else if ( Array_Mode[1] == 1'b1 ) begin
                        if ( ECC_Enable == 1'b1 ) begin
                                if ( capgm_op == 1'b1 ) begin
                                        if ( Tprog_ecc > Tcbsy )
                                                #( Tprog_ecc-Tcbsy);
                                end
                                else
                                        #Tprog_ecc;
                        end
                        else begin
                                if ( capgm_op == 1'b1 ) begin
                                        if ( Tprog > Tcbsy )
                                                #(Tprog-Tcbsy);
                                end
                                else
                                        #Tprog;
                        end
                        if ( Latch_A_4TMP[CA_MSB+7] == 1'b1 ) begin
                                PBuff_TMP = PBuff1[Latch_A[CA_MSB:0]-1];
                                if ( PBuff_TMP == 8'h00 && last_cycle_addr == 8'h00 ) begin
                                        OTP_Protect = 1'b1; // non-volatile bit
                                end
                                else begin
                                        $display ( $time, "Warning: OTP protection Operation: address and data before 10h should be 00h\n" );
                                end
                        end
                        else begin
                                PBuff_TMP = PBuff0[Latch_A[CA_MSB:0]-1];
                                if ( PBuff_TMP == 8'h00 && last_cycle_addr == 8'h00 ) begin
                                        OTP_Protect = 1'b1; // non-volatile bit
                                end
                                else begin
                                        $display ( $time, "Warning: OTP protection Operation: address and data before 10h should be 00h\n" );
                                end
                        end
                end
                else begin
                        if ( Latch_A_4TMP[A_MSB:CA_MSB+1] >= 24'h000002 && Latch_A_4TMP[A_MSB:CA_MSB+1] <= 24'h00001f ) begin
                                if ( ECC_Enable == 1'b1 ) begin
                                        if ( capgm_op == 1'b1 ) begin
                                                if ( Tobsy_ecc > Tcbsy )
                                                        #( Tobsy_ecc-Tcbsy);
                                        end
                                        else
                                                #Tobsy_ecc;
                                end
                                else begin
                                        if ( capgm_op == 1'b1 ) begin
                                                if ( Tobsy > Tcbsy )
                                                        #(Tobsy-Tcbsy);
                                        end
                                        else
                                                #Tobsy;
                                end
                                if ( Latch_A_4TMP[CA_MSB+7] == 1'b1 ) begin
                                        sr0_1 = 1'b1;
                                        sr0 = sr0_1;
                                end
                                else begin
                                        sr0_0 = 1'b1;
                                        sr0 = sr0_0;
                                end
                                sr7 = 1'b0;
                        end
                        else begin
                                $display ( $time, "Warning: The address of OTP is located on 02h-1Fh page address\n" );
                        end
                end
        end
        else if ( Array_Mode[0] == 1'b0 && ERE_Mode[0] == 1'b1 && PBL_Mode[0] == 1'b0 && DPPGM_Mode_4TMP == 1'b0 ) begin
                if ( Latch_A[7:0] == 8'h01 ) begin
                        if ( ECC_Enable == 1'b1 ) begin
                                if ( capgm_op == 1'b1 ) begin
                                        if ( Tprog_ecc > Tcbsy )
                                                #(Tprog_ecc-Tcbsy);
                                end
                                else
                                        #Tprog_ecc;
                        end
                        else begin
                                if ( capgm_op == 1'b1 ) begin
                                        if ( Tprog > Tcbsy )
                                                #(Tprog-Tcbsy);
                                end
                                else
                                        #Tprog;
                        end
                        ERE_status = ERE_status_dum;
                end
                else begin
                        $display ( $time, "Warning: Set ERE should begin with address 01h\n" );
                end
        end
        else if ( Array_Mode[0] == 1'b0 && ERE_Mode[0] == 1'b0 && PBL_Mode[0] == 1'b1 && DPPGM_Mode_4TMP == 1'b0 ) begin
                if ( Latch_A[7:0] == 8'h09 ) begin
                        if ( ECC_Enable == 1'b1 ) begin
                                if ( capgm_op == 1'b1 ) begin
                                        if ( Tprog_ecc > Tcbsy )
                                                #(Tprog_ecc-Tcbsy);
                                end
                                else
                                        #Tprog_ecc;
                        end
                        else begin
                                if ( capgm_op == 1'b1 ) begin
                                        if ( Tprog > Tcbsy )
                                                #(Tprog-Tcbsy);
                                end
                                else
                                        #Tprog;
                        end
                        if ( PBL_status_dum[31] == 1'b0 && PBL_status == 32'hffff_ffff ) begin
                                PBL_status = PBL_status_dum;
                        end
                end
                else begin
                        $display ( $time, "Warning: Set PBL should begin with address 09h\n" );
                end
        end
        else if ( (Array_Mode[0] == 1'b1 || ERE_Mode[0] == 1'b1 || PBL_Mode[0] == 1'b1) && DPPGM_Mode_4TMP == 1'b1 ) begin
                $display ( $time, "Warning: Can't issue two plane program during OTP mode, ERE mode or PBL mode\n" );
        end
        else begin
                $display ( $time, "Warning: Can't enter OTP mode, ERE mode or PBL mode simultaneously\n" );
        end
        pgm_busy = 1'b0;
        if ( DPPGM_Mode_4TMP == 1'b1 ) begin
                sr0 = sr0_0 || sr0_1;
                sr1 = sr1_0 || sr1_1;
        end
        sr5 = 1'b1;
        if ( capgm_op == 1'b0 ) begin
                sr6 = 1'b1;
                CMD_11h_flag = 1'b0;
        end
        sr5_flag = 1'b1;
        if ( !capgm_op_mode ) begin
                capgm_op = 1'b0;
                if ( CMD_11h_flag == 1'b0 ) begin
                        DPPGM_Mode = 1'b0;
                        DPPGM_Mode_4TMP = 1'b0;
                end
        end
end

always @ ( cache_pgm ) begin: cache_pgm_p
        sr6 <= #Twb 1'b0;
        capgm_op_mode = 1'b1;
        if ( DPPGM_Mode == 1'b1 ) begin
                Latch_A_st_CAOP[A_MSB:CA_MSB+1] = Latch_A_st[A_MSB:CA_MSB+1];
                Latch_A_nd_CAOP[A_MSB:CA_MSB+1] = Latch_A_nd[A_MSB:CA_MSB+1];
        end
        else begin
                Latch_A_CAOP[A_MSB:CA_MSB+1] = Latch_A[A_MSB:CA_MSB+1];
        end
        if ( sr5 == 1'b0 ) begin
                wait ( sr5 );
                sr5 = 1'b0;
        end
        -> page_pgm;
end

always @ ( capgm_op_event ) begin
        wait ( sr5_flag );
        capgm_op = 1'b0;
end

always @ ( set_feature ) begin: set_feature_p
        wait ( ADR_CYC == 1 );
        wait ( DATA_CYC == 4 );
        #Twb;
        sr5 = 1'b0;
        sr6 = 1'b0;
        sr5_flag = 1'b0;
        feature_busy = 1'b1;
        #Tfeat;

        if ( Latch_A[7:0] == 8'hb0 ) begin
                FEAT_ARRAY_TMP    = FEAT_ARRAY1[8'hb0];
                FEAT_ARRAY_TMP[0] = FEAT_ARRAY_DUM1[0];
                { RANDOPT_TMP , RANDEN_TMP } = FEAT_ARRAY_DUM1[2:1];
                FEAT_ARRAY1[8'hb0] = FEAT_ARRAY_TMP;
                FEAT_ARRAY2[8'hb0] = FEAT_ARRAY_DUM2;
                FEAT_ARRAY3[8'hb0] = FEAT_ARRAY_DUM3;
                FEAT_ARRAY4[8'hb0] = FEAT_ARRAY_DUM4;
        end
        else if ( Latch_A[7:0] == 8'h80 ) begin
                if ( FEAT_ARRAY_DUM1[0] == 1'b1) begin
                    FEAT_ARRAY1[8'h80] = FEAT_ARRAY1[8'h80] | 8'h01;
                end
                FEAT_ARRAY2[8'h80] = FEAT_ARRAY_DUM2;
                FEAT_ARRAY3[8'h80] = FEAT_ARRAY_DUM3;
                FEAT_ARRAY4[8'h80] = FEAT_ARRAY_DUM4;
        end
        else if ( !(Latch_A[7:0] == 8'ha0 && BP_Solid == 1'b1) ) begin
                FEAT_ARRAY1[Latch_A[7:0]] = FEAT_ARRAY_DUM1;
                FEAT_ARRAY2[Latch_A[7:0]] = FEAT_ARRAY_DUM2;
                FEAT_ARRAY3[Latch_A[7:0]] = FEAT_ARRAY_DUM3;
                FEAT_ARRAY4[Latch_A[7:0]] = FEAT_ARRAY_DUM4;
        end
        if ( Array_Mode[0]&&ERE_Mode[0] || Array_Mode[0]&&PBL_Mode[0] || ERE_Mode[0]&&PBL_Mode[0] ) begin
                $display ( $time, "Warning: ERE Mode, OTP Mode and PBL mode conflict, please set to Normal Mode\n" );
        end
        sr5 = 1'b1;
        sr6 = 1'b1;
        sr5_flag = 1'b1;
        feature_busy = 1'b0;
        set_feature_flag = 1'b0;
end

    /*----------------------------------------------------------------------*/
    /*  Erase related blocks                                                */
    /*----------------------------------------------------------------------*/
always @ ( block_ers ) begin: block_ers_p
        DPERS_Mode_4TMP = DPERS_Mode;
        #Twb;
        if ( DPERS_Mode_4TMP == 1'b1 ) begin
                Latch_A_st_4TMP[A_MSB:CA_MSB+1] = Latch_A_st[A_MSB:CA_MSB+1];
                Latch_A_4TMP[A_MSB:CA_MSB+1] = Latch_A_nd[A_MSB:CA_MSB+1];
        end
        else begin
                Latch_A_4TMP[A_MSB:CA_MSB+1] = Latch_A[A_MSB:CA_MSB+1];
        end
        if ( DPERS_Mode_4TMP == 1'b1 ) begin
                sr0_0 = 1'b0;
                sr0_1 = 1'b0;
                sr0 = sr0_0 || sr0_1;
        end
        else begin
                if ( Latch_A_4TMP[CA_MSB+7] == 1'b1 ) begin
                        sr0_1 = 1'b0;
                        sr0 = sr0_1;
                end
                else begin
                        sr0_0 = 1'b0;
                        sr0 = sr0_0;
                end
        end
        sr5 = 1'b0;
        sr6 = 1'b0;
        sr5_flag = 1'b0;
        ers_busy = 1'b1;
        if ( block_protect(Latch_A_4TMP) == 1'b0 && WP_B_IN ) begin // protection check
                for ( block_count = 0; block_count < Page_NUM; block_count = block_count + 1) begin
                        Latch_A_4TMP[CA_MSB+MSB_PA_IN_BLOCK+1:CA_MSB+1] = block_count;
                        for ( pa_count = 0; pa_count <= Top_Cache; pa_count = pa_count + 1) begin
                                Latch_A_4TMP[CA_MSB:0] = pa_count;
                                ARRAY[Latch_A_4TMP[A_MSB:0]] = (IO_MSB==7)?8'hx:16'hx;
                        end
                end
        end
        if ( DPERS_Mode_4TMP == 1'b1 ) begin
                if ( block_protect(Latch_A_st_4TMP) == 1'b0 && WP_B_IN ) begin // protection check
                        for ( block_count = 0; block_count < Page_NUM; block_count = block_count + 1) begin
                                Latch_A_st_4TMP[CA_MSB+MSB_PA_IN_BLOCK+1:CA_MSB+1] = block_count;
                                for ( pa_count = 0; pa_count <= Top_Cache; pa_count = pa_count + 1) begin
                                        Latch_A_st_4TMP[CA_MSB:0] = pa_count;
                                        ARRAY[Latch_A_st_4TMP[A_MSB:0]] = (IO_MSB==7)?8'hx:16'hx;
                                end
                        end
                end
        end
        if ( DPERS_Mode_4TMP == 1'b0 ) begin
                if ( block_protect(Latch_A_4TMP) == 1'b0 && WP_B_IN )
                        #Terase;
                else
                        #Tpbsy;
        end
        else begin
                if ( block_protect(Latch_A_4TMP) == 1'b1 && block_protect(Latch_A_st_4TMP) == 1'b1 || !WP_B_IN )
                        #Tpbsy;
                else
                        #Terase;
        end     
        if ( block_protect(Latch_A_4TMP) == 1'b0 && WP_B_IN ) begin // protection check
                for ( block_count = 0; block_count < Page_NUM; block_count = block_count + 1) begin
                        Latch_A_4TMP[CA_MSB+MSB_PA_IN_BLOCK+1:CA_MSB+1] = block_count;
                        for ( pa_count = 0; pa_count <= Top_Cache; pa_count = pa_count + 1) begin
                                Latch_A_4TMP[CA_MSB:0] = pa_count;
                                ARRAY[Latch_A_4TMP[A_MSB:0]] = ~0;
                                PGM_Count[Latch_A_4TMP[A_MSB:CA_MSB+1]] = 0;
                        end 
                end
                if ( Latch_A_4TMP[CA_MSB+7] == 1'b1 ) begin
                        sr0_1 = 1'b0;
                        sr0 = sr0_1;
                end
                else begin
                        sr0_0 = 1'b0;
                        sr0 = sr0_0;
                end
                sr7 = 1'b1;
        end
        else begin
                if ( Latch_A_4TMP[CA_MSB+7] == 1'b1 ) begin
                        sr0_1 = 1'b1;
                        sr0 = sr0_1;
                end
                else begin
                        sr0_0 = 1'b1;
                        sr0 = sr0_0;
                end
                sr7 = 1'b0;
        end
        if ( DPERS_Mode_4TMP == 1'b1 ) begin
                if ( block_protect(Latch_A_st_4TMP) == 1'b0 && WP_B_IN ) begin // protection check
                        for ( block_count = 0; block_count < Page_NUM; block_count = block_count + 1) begin
                                Latch_A_st_4TMP[CA_MSB+MSB_PA_IN_BLOCK+1:CA_MSB+1] = block_count;
                                for ( pa_count = 0; pa_count <= Top_Cache; pa_count = pa_count + 1) begin
                                        Latch_A_st_4TMP[CA_MSB:0] = pa_count;
                                        ARRAY[Latch_A_st_4TMP[A_MSB:0]] = ~0;
                                        PGM_Count[Latch_A_st_4TMP[A_MSB:CA_MSB+1]] = 0;
                                end 
                        end
                        if ( Latch_A_st_4TMP[CA_MSB+7] == 1'b1 ) begin
                                sr0_1 = 1'b0;
                                sr0 = sr0_1;
                        end
                        else begin
                                sr0_0 = 1'b0;
                                sr0 = sr0_0;
                        end
                        sr7 = 1'b1;
                end
                else begin
                        if ( Latch_A_st_4TMP[CA_MSB+7] == 1'b1 ) begin
                                sr0_1 = 1'b1;
                                sr0 = sr0_1;
                        end
                        else begin
                                sr0_0 = 1'b1;
                                sr0 = sr0_0;
                        end
                        sr7 = 1'b0;
                end
                sr0 = sr0_0 || sr0_1;
        end
        ers_busy = 1'b0;
        sr5 = 1'b1;
        sr6 = 1'b1;
        sr5_flag = 1'b1;
        DPERS_Mode = 1'b0;
        DPERS_Mode_4TMP = 1'b0;
end


    /*----------------------------------------------------------------------*/
    /*  Reset related blocks                                                */
    /*----------------------------------------------------------------------*/
always @ ( negedge WP_B ) begin
        if (ers_busy || pgm_busy)
                -> reset_event;
end

always @ ( reset_event ) begin
        #Twb;
        sr6 = 1'b0;
        if (ers_busy) fork: rst_ers
                begin
                        wait ( sr6 );
                        sr6 = 1'b0;
                end
                begin
                        #Trst_e;
                        disable rst_ers;
                end
        join
        else if (pgm_busy) fork: rst_pgm
                begin
                        wait ( sr6 );
                        sr6 = 1'b0;
                end
                begin
                        #Trst_p;
                        disable rst_pgm;
                end
        join
        else fork: rst_read
                begin
                        wait ( sr6 );
                        sr6 = 1'b0;
                end
                begin
                        #Trst_r;
                        disable rst_read;
                end
        join
        tk_reset;
end

task tk_reset;
begin
        for ( pa_count = 0; pa_count <= Top_Cache; pa_count = pa_count + 1) begin
                Cache0[pa_count] = ~0;
                Cache1[pa_count] = ~0;
                PBuff0[pa_count] = ~0;
                PBuff1[pa_count] = ~0;
        end
        for ( j = 0; j <= 5; j = j + 1 ) begin
                id_buffer1[j] = ~0;
        end
        for ( j = 0; j <= 3; j = j + 1 ) begin
                id_buffer2[j] = ~0;
        end
        FEAT_ARRAY_DUM1         = ~0;
        FEAT_ARRAY_DUM2         = ~0;
        FEAT_ARRAY_DUM3         = ~0;
        FEAT_ARRAY_DUM4         = ~0;
        FEAT_ARRAY_TMP          = 0;
        RANDEN_TMP              = 0;
        RANDOPT_TMP             = 0;
        ERE_status_dum          = ~0;
        PBL_status_dum          = ~0;
        Q_Reg                   = ~0;
        Latch_A                 = 0;
        Latch_A_4TMP            = 0;
        Latch_A_OUT             = 0;
        Latch_A_st              = 0;
        Latch_A_st_4TMP         = 0;
        Latch_A_nd              = 0;
        Latch_A_nd_4TMP         = 0;
        STATE                   = INIT_STAT;
        OUT_EN                  = 1'b0;
        OUTZ_EN                 = 1'b0;
        last_addr_flag          = 1'b0;
        Page_EN                 = 1'b0;
        RD_Mode                 = 1'b0;
        READ_Mode               = 1'b0;
        CARD_Mode               = 1'b0;
        CARD_Mode_End           = 1'b0; 
        RANDCARD_Mode           = 1'b0;
        RANDCARD_Mode_End       = 1'b0;
        capgm_op                = 1'b0;
        capgm_op_mode           = 1'b0;
        pgm_busy                = 1'b0;
        ers_busy                = 1'b0;
        sr7                     = 1'b1;
        sr6                     = 1'b1;
        sr5                     = 1'b1;
        sr4                     = 1'b0;
        sr3                     = 1'b0;
        sr2                     = 1'b0;
        sr1                     = 1'b0;
        sr0                     = 1'b0;
        sr1_0                   = 1'b0;
        sr1_0_pre               = 1'b0;
        sr0_0                   = 1'b0;
        sr1_1                   = 1'b0;
        sr1_1_pre               = 1'b0;
        sr0_1                   = 1'b0;
        rdid_flag               = 1'b0;
        status_flag             = 1'b0;
        enhance_status_flag     = 1'b0;
        parameter_flag          = 1'b0;
        unid_flag               = 1'b0;
        read_feature_flag       = 1'b0;
        set_feature_flag        = 1'b0;
        read_ere_flag           = 1'b0;
        Feature_EN              = 1'b0;
        feature_busy            = 1'b0;
        DPRD_Mode               = 1'b0;
        DPRD_Mode_4TMP          = 1'b0;
        DPRD_addr_chk           = 1'b0;
        plane_flag              = 1'b0;
        CMD_11h_flag            = 1'b0;
        DPPGM_Mode              = 1'b0;
        DPPGM_Mode_4TMP         = 1'b0;
        DPPGM_addr_chk          = 1'b0;
        DPERS_Mode              = 1'b0;
        DPERS_Mode_4TMP         = 1'b0;
        DPERS_addr_chk          = 1'b0;
        unprotect_low_flag      = 1'b0;
        unprotect_upper_flag    = 1'b0;
        protect_status_flag     = 1'b0;
        j                       = 0;
        ADR_CYC                 = 0;
        DATA_CYC                = 0;
        disable load_pagebuffer1;
        disable load_pagebuffer2;
        disable load_pagebuffer3;
        disable load_pagebuffer4;
        disable load_pagebuffer5;
        disable load_pagebuffer6;
        disable load_pagebuffer7;
        disable read_ere_p;
        disable read_id_p;
        disable load_cache;
        disable read_mode;
        disable page_pgm_p;
        disable cache_pgm_p;
        disable set_feature_p;
        disable block_ers_p;
end
endtask // tk_reset

// *==============================================================================================
// * Function blocks Declaration
// *==============================================================================================

    /*----------------------------------------------------------------------*/
    /*  Block protect function                                              */
    /*----------------------------------------------------------------------*/
function block_protect;
        input [A_MSB:0] address;
        begin
                block_protect = 1'b0;
                if ( protect_en == 1'b1 ) begin
                        case ({BP_Bit, BP_Invert, BP_Complement})
                                5'b00000,5'b00001,5'b00010,5'b00011: begin
                                        block_protect = 1'b0;
                                end
                                5'b00100: begin
                                        block_protect = ( &address[A_MSB:A_MSB-5] ) ? 1'b1 : 1'b0;
                                end
                                5'b01000: begin
                                        block_protect = ( &address[A_MSB:A_MSB-4] ) ? 1'b1 : 1'b0;
                                end
                                5'b01100: begin
                                        block_protect = ( &address[A_MSB:A_MSB-3] ) ? 1'b1 : 1'b0;
                                end
                                5'b10000: begin
                                        block_protect = ( &address[A_MSB:A_MSB-2] ) ? 1'b1 : 1'b0;
                                end
                                5'b10100: begin
                                        block_protect = ( &address[A_MSB:A_MSB-1] ) ? 1'b1 : 1'b0;
                                end
                                5'b11000: begin
                                        block_protect = ( address[A_MSB] ) ? 1'b1 : 1'b0;
                                end
                                5'b11100,5'b11101,5'b11110,5'b11111: begin
                                        block_protect = 1'b1;
                                end
                                5'b00110: begin
                                        block_protect = ( &(~address[A_MSB:A_MSB-5]) ) ? 1'b1 : 1'b0;
                                end
                                5'b01010: begin
                                        block_protect = ( &(~address[A_MSB:A_MSB-4]) ) ? 1'b1 : 1'b0;
                                end
                                5'b01110: begin
                                        block_protect = ( &(~address[A_MSB:A_MSB-3]) ) ? 1'b1 : 1'b0;
                                end
                                5'b10010: begin
                                        block_protect = ( &(~address[A_MSB:A_MSB-2]) ) ? 1'b1 : 1'b0;
                                end
                                5'b10110: begin
                                        block_protect = ( &(~address[A_MSB:A_MSB-1]) ) ? 1'b1 : 1'b0;
                                end
                                5'b11010: begin
                                        block_protect = ( ~address[A_MSB] ) ? 1'b1 : 1'b0;
                                end
                                5'b00101: begin
                                        block_protect = !(( &address[A_MSB:A_MSB-5] ) ? 1'b1 : 1'b0);
                                end
                                5'b01001: begin
                                        block_protect = !(( &address[A_MSB:A_MSB-4] ) ? 1'b1 : 1'b0);
                                end
                                5'b01101: begin
                                        block_protect = !(( &address[A_MSB:A_MSB-3] ) ? 1'b1 : 1'b0);
                                end
                                5'b10001: begin
                                        block_protect = !(( &address[A_MSB:A_MSB-2] ) ? 1'b1 : 1'b0);
                                end
                                5'b10101: begin
                                        block_protect = !(( &address[A_MSB:A_MSB-1] ) ? 1'b1 : 1'b0);
                                end
                                5'b11001: begin
                                        block_protect = ( address[A_MSB:CA_MSB+7] == 0 ) ? 1'b1 : 1'b0;
                                end
                                5'b00111: begin
                                        block_protect = !(( &(~address[A_MSB:A_MSB-5]) ) ? 1'b1 : 1'b0);
                                end
                                5'b01011: begin
                                        block_protect = !(( &(~address[A_MSB:A_MSB-4]) ) ? 1'b1 : 1'b0);
                                end
                                5'b01111: begin
                                        block_protect = !(( &(~address[A_MSB:A_MSB-3]) ) ? 1'b1 : 1'b0);
                                end
                                5'b10011: begin
                                        block_protect = !(( &(~address[A_MSB:A_MSB-2]) ) ? 1'b1 : 1'b0);
                                end
                                5'b10111: begin
                                        block_protect = !(( &(~address[A_MSB:A_MSB-1]) ) ? 1'b1 : 1'b0);
                                end
                                5'b11011: begin
                                        block_protect = ( address[A_MSB:CA_MSB+7] == 0 ) ? 1'b1 : 1'b0;
                                end
                                default: begin
                                        block_protect = 1'b1;
                                end
                        endcase
                end
                if ( PBL_Enb == 1'b0 ) begin
                        if ( PBL_Invert == 1'b1 ) begin
                                if ( address[A_MSB:CA_MSB+7] <= PBL_status[A_MSB-CA_MSB-7:0]
                                        && address[A_MSB:CA_MSB+7] >= PBL_status[A_MSB-CA_MSB+8:15] ) begin
                                        block_protect = 1'b1;
                                end
                                else begin
                                end
                        end
                        else begin
                                if ( address[A_MSB:CA_MSB+7] <= PBL_status[A_MSB-CA_MSB-7:0]
                                        && address[A_MSB:CA_MSB+7] >= PBL_status[A_MSB-CA_MSB+8:15] ) begin
                                end
                                else begin
                                        block_protect = 1'b1;
                                end
                        end
                end

        end
endfunction

    /*----------------------------------------------------------------------*/
    /*  ERE area function                                                   */
    /*----------------------------------------------------------------------*/
function ere_area;
        input [A_MSB:0] address;
        begin
                if ( ERE_status[0] == 1'b0 ) begin
                        if ( address[A_MSB:A_MSB-4] <= ERE_status[5:1] ) begin
                                ere_area = 1'b1;
                        end
                        else if ( address[A_MSB:A_MSB-4] == 5'b11111 && ERE_status[7:6] == 2'b00 ) begin
                                if ( address[A_MSB:CA_MSB+10] == ((1<<(A_MSB-CA_MSB-9)) - 1) ) begin
                                        ere_area = 1'b1;
                                end
                                else begin
                                        ere_area = 1'b0;
                                end
                        end
                        else if ( address[A_MSB:A_MSB-4] == 5'b11111 && ERE_status[7:6] == 2'b10 ) begin
                                if ( address[A_MSB:CA_MSB+10] == ((1<<(A_MSB-CA_MSB-9)) - 1) && address[CA_MSB+9:CA_MSB+7] >= 3'b100 ) begin
                                        ere_area = 1'b1;
                                end
                                else begin
                                        ere_area = 1'b0;
                                end
                        end
                        else if ( address[A_MSB:A_MSB-4] == 5'b11111 && ERE_status[7:6] == 2'b01 ) begin
                                if ( address[A_MSB:CA_MSB+10] == ((1<<(A_MSB-CA_MSB-9)) - 1) && address[CA_MSB+9:CA_MSB+7] >= 3'b110 ) begin
                                        ere_area = 1'b1;
                                end
                                else begin
                                        ere_area = 1'b0;
                                end
                        end
                        else if ( address[A_MSB:A_MSB-4] == 5'b11111 && ERE_status[7:6] == 2'b11 ) begin
                                ere_area = 1'b0;
                        end
                        else begin
                                ere_area = 1'b0;
                        end
                end
                else begin
                        ere_area = 1'b0;
                end
        end
endfunction

endmodule
