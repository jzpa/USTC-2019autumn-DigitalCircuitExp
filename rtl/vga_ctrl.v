`timescale 1ns / 1ps
//VGA模块现用代码
module vga_ctrl
(
    input                   R_clk_65M   , // 系统65MHz时钟
    input                   rst , // 系统复位
	//写RAM
    input                   R_ram_we,
    input                   [11:0]R_ram_waddr,
    input                   [7:0]R_ram_wdata,
	//输出到编译器
	output 				[7:0]Compile_data,
	//输出到显示器
    output reg [11:0] vga_data,//输出RGB
	output hs,
	output vs
);

// 分辨率为640*480时行时序各个参数定义
parameter       C_H_SYNC_PULSE      =   136  , 
                C_H_BACK_PORCH      =   160  ,
                C_H_ACTIVE_TIME     =   1024 ,
                C_H_FRONT_PORCH     =   24  ,
                C_H_LINE_PERIOD     =   1344 ;

// 分辨率为640*480时场时序各个参数定义               
parameter       C_V_SYNC_PULSE      =   6   , 
                C_V_BACK_PORCH      =   29  ,
                C_V_ACTIVE_TIME     =   768 ,
                C_V_FRONT_PORCH     =   3  ,
                C_V_FRAME_PERIOD    =   806 ;

//界面的安排设置
parameter		C_ROAD_WIDTH		=	64,
				C_FRAME_WIDTH		=	640,
				C_BUTTON_RIGHT		=	16,
				C_WORD_WIDTH		=	8,
				C_WORD_HEIGHT		=	16;
parameter       C_IMAGE_WIDTH       =   500     ,//128
                C_IMAGE_HEIGHT      =   500     ,//128
                C_IMAGE_PIX_NUM     =   250000   ;     //16384           

reg     [11:0]      R_h_cnt         ; // 行时序计数器
reg     [11:0]      R_v_cnt         ; // 列时序计数器
reg     [11:0]      R_ram_addr      ; // 输入缓冲区RAM的地址
wire    [7:0]       R_ram_data      ; // 输入缓冲区RAM中存储的数据
wire	[127:0]		R_rom_data		; // ROM中对应的字形
reg   [6:0]		R_rom_place		; // ROM中对应字形扫描到的位置
wire            W_active_flag   ; // 激活标志，当这个信号为1时RGB的数据可以显示在屏幕上

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
// 功能：产生场时序
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
// 产生有效区域标志，当这个信号为高时往RGB送的数据才会显示到屏幕上
//////////////////////////////////////////////////////////////////
assign W_active_flag =  (R_h_cnt >= (C_H_SYNC_PULSE + C_H_BACK_PORCH                     ))  &&
                        (R_h_cnt <= (C_H_SYNC_PULSE + C_H_BACK_PORCH + C_H_ACTIVE_TIME     ))  && 
                        (R_v_cnt >= (C_V_SYNC_PULSE + C_V_BACK_PORCH                    ))  &&
                        (R_v_cnt <= (C_V_SYNC_PULSE + C_V_BACK_PORCH + C_V_ACTIVE_TIME     ))  ;                     

//////////////////////////////////////////////////////////////////
// 功能：把ROM里面的图片数据输出
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
