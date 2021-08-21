`timescale 1ns / 1ps
//VGAģ�����ô���
module vga_ctrl
(
    input                   R_clk_65M   , // ϵͳ65MHzʱ��
    input                   rst , // ϵͳ��λ
	//дRAM
    input                   R_ram_we,
    input                   [11:0]R_ram_waddr,
    input                   [7:0]R_ram_wdata,
	//�����������
	output 				[7:0]Compile_data,
	//�������ʾ��
    output reg [11:0] vga_data,//���RGB
	output hs,
	output vs
);

// �ֱ���Ϊ640*480ʱ��ʱ�������������
parameter       C_H_SYNC_PULSE      =   136  , 
                C_H_BACK_PORCH      =   160  ,
                C_H_ACTIVE_TIME     =   1024 ,
                C_H_FRONT_PORCH     =   24  ,
                C_H_LINE_PERIOD     =   1344 ;

// �ֱ���Ϊ640*480ʱ��ʱ�������������               
parameter       C_V_SYNC_PULSE      =   6   , 
                C_V_BACK_PORCH      =   29  ,
                C_V_ACTIVE_TIME     =   768 ,
                C_V_FRONT_PORCH     =   3  ,
                C_V_FRAME_PERIOD    =   806 ;

//����İ�������
parameter		C_ROAD_WIDTH		=	64,
				C_FRAME_WIDTH		=	640,
				C_BUTTON_RIGHT		=	16,
				C_WORD_WIDTH		=	8,
				C_WORD_HEIGHT		=	16;
parameter       C_IMAGE_WIDTH       =   500     ,//128
                C_IMAGE_HEIGHT      =   500     ,//128
                C_IMAGE_PIX_NUM     =   250000   ;     //16384           

reg     [11:0]      R_h_cnt         ; // ��ʱ�������
reg     [11:0]      R_v_cnt         ; // ��ʱ�������
reg     [11:0]      R_ram_addr      ; // ���뻺����RAM�ĵ�ַ
wire    [7:0]       R_ram_data      ; // ���뻺����RAM�д洢������
wire	[127:0]		R_rom_data		; // ROM�ж�Ӧ������
reg   [6:0]		R_rom_place		; // ROM�ж�Ӧ����ɨ�赽��λ��
wire            W_active_flag   ; // �����־��������ź�Ϊ1ʱRGB�����ݿ�����ʾ����Ļ��

always @(posedge R_clk_65M or negedge rst)
begin
    if(rst)
        R_h_cnt <=  12'd0   ;
    else if(R_h_cnt == C_H_LINE_PERIOD - 1'b1)
        R_h_cnt <=  12'd0   ;
    else
        R_h_cnt <=  R_h_cnt + 1'b1  ;                
end                

assign hs =   (R_h_cnt < C_H_SYNC_PULSE) ? 1'b0 : 1'b1    ; 
//////////////////////////////////////////////////////////////////

//////////////////////////////////////////////////////////////////
// ���ܣ�������ʱ��
//////////////////////////////////////////////////////////////////
always @(posedge R_clk_65M or negedge rst)
begin
    if(rst)
        R_v_cnt <=  12'd0   ;
    else if(R_v_cnt == C_V_FRAME_PERIOD - 1'b1)
        R_v_cnt <=  12'd0   ;
    else if(R_h_cnt == C_H_LINE_PERIOD - 1'b1)
        R_v_cnt <=  R_v_cnt + 1'b1  ;
    else
        R_v_cnt <=  R_v_cnt ;                        
end                

assign vs =   (R_v_cnt < C_V_SYNC_PULSE) ? 1'b0 : 1'b1    ; 
//////////////////////////////////////////////////////////////////  
// ������Ч�����־��������ź�Ϊ��ʱ��RGB�͵����ݲŻ���ʾ����Ļ��
//////////////////////////////////////////////////////////////////
assign W_active_flag =  (R_h_cnt >= (C_H_SYNC_PULSE + C_H_BACK_PORCH                     ))  &&
                        (R_h_cnt <= (C_H_SYNC_PULSE + C_H_BACK_PORCH + C_H_ACTIVE_TIME     ))  && 
                        (R_v_cnt >= (C_V_SYNC_PULSE + C_V_BACK_PORCH                    ))  &&
                        (R_v_cnt <= (C_V_SYNC_PULSE + C_V_BACK_PORCH + C_V_ACTIVE_TIME     ))  ;                     

//////////////////////////////////////////////////////////////////
// ���ܣ���ROM�����ͼƬ�������
//////////////////////////////////////////////////////////////////
Words_Ram Words_Ram(
	.a(R_ram_waddr),
	.d(R_ram_wdata),
	.dpra(R_ram_addr),
	.clk(R_clk_65M),
	.we(R_ram_we),
	.dpo(R_ram_data),
	.spo(Compile_data)
);
WordToPicture WordToPicture(
	.a(R_ram_data),
	.spo(R_rom_data)
);

always @(posedge R_clk_65M or negedge rst)
begin
    if(rst) 
        R_ram_addr  <=  18'd0 ;
    else
    begin 
        if(W_active_flag)     
        begin
            if(R_h_cnt >= (C_H_SYNC_PULSE + C_H_BACK_PORCH + C_ROAD_WIDTH                       )  && 
               R_h_cnt <= (C_H_SYNC_PULSE + C_H_BACK_PORCH + C_ROAD_WIDTH + C_FRAME_WIDTH  - 1'b1)  &&
               R_v_cnt >= (C_V_SYNC_PULSE + C_V_BACK_PORCH + C_ROAD_WIDTH                       )  && 
               R_v_cnt <= (C_V_SYNC_PULSE + C_V_BACK_PORCH + C_ROAD_WIDTH + C_FRAME_WIDTH - 1'b1)  )
                begin
                    R_ram_addr <= (R_v_cnt - C_V_SYNC_PULSE - C_V_BACK_PORCH - C_ROAD_WIDTH) / C_WORD_HEIGHT * 80
	 	                +(R_h_cnt - C_H_SYNC_PULSE - C_H_BACK_PORCH - C_ROAD_WIDTH) / C_WORD_WIDTH ;
                    R_rom_place <= (R_v_cnt - C_V_SYNC_PULSE - C_V_BACK_PORCH - C_ROAD_WIDTH) % C_WORD_HEIGHT * 8
    				    +(R_h_cnt - C_H_SYNC_PULSE - C_H_BACK_PORCH - C_ROAD_WIDTH) % C_WORD_WIDTH;
    			    if(R_rom_data[R_rom_place] == 0)
	       			    vga_data <= 0;
			        else
					    vga_data <= 12'hfff; 
                end
            else
            begin
                vga_data[3:0]       <=  4'ha        ;
                vga_data[7:4]    <=  4'h2        ;
                vga_data[11:8]      <=  4'h4        ;
                R_ram_addr  <=  R_ram_addr  ;
            end                          
        end
        else
        begin
            vga_data[3:0]       <=  4'hf        ;
            vga_data[7:4]    <=  4'h0        ;
            vga_data[11:8]      <=  4'h0       ;
            R_ram_addr  <=  R_ram_addr  ;
        end
    end          
end
endmodule
