`timescale 1ns / 1ps
module top( 
input clk,rst,
input [7:0]SW,//从开关处读入所需要的文本信息
input button,backspace,//输入与回退按钮
input Compile_begin,Queue_begin,//编译与执行开始按钮
input ps2_clk,ps2_data,//从键盘输入的信号
output [15:0]led,
output hs,vs,[11:0] vga_data,//显示屏输出的信号
output [7:0]SSEG_CA,//输出到七段数码管的信号
output reg[7:0]SSEG_AN
); 
wire    clk_65m,lock;
wire button_clean,button_rdedge; //输入按钮处理
wire backspace_clean,backspace_redge;//回退按钮处理

////////////////////////////
////////键盘信号转接////////
wire [7:0]ps2_byte;
wire ps2_state;

////////////////////////
////////写入信号////////

reg R_ram_we;
reg [11:0]R_ram_waddr;
reg [7:0]R_ram_wdata;
wire [11:0]R_ram_a;

//////////////////////////////
////////编译所用状态机////////

//从存储字符的module中读取信息所需要的信号
reg [11:0]Compile_addr;//读入地址
wire [7:0]Compile_data;//读出数据
//每8位为一个读取的字符，最大容纳16位字符。每个时钟边沿进行读入字符操作，并针对情况对程序进行编写，对内部信号进行清零
reg [127:0]Compiler;
//编译完成后需要向Queue中写入的信息
reg [63:0]QueueData;
//reg Queue_we;
//编译的控制使能信号
reg Compile_E;
//表征编译已经完成的信号
reg Compile_Finished;

////////////////////////
////////程序组成////////

////内部变量/常量表
//每4位存储一个值，0-25为字母表示的变量,26-35为常量。
reg [143:0] Val;
////实际执行队列
//采用一个distributed memory进行实现,采用dual port RAM，为此需要设置一些控制变量
reg QueueWe;
wire [63:0]QueueReadData;
//在编译中一次次向队列内加入新的活动项，此为写指针，初始开启时置0
reg [7:0] QueueWrite;
//在执行中一次次由队头开始执行活动项，或者是根据循环或者条件判断信号跳转，此为读指针，初始开启与结束时置0
reg [7:0] QueueRead;
//执行队列的控制使能信号
reg Queue_E;
//表征执行队列已经完成的信号
reg Queue_Finished;

//////////////////////
////////输出表////////

//每8位表示一个七段数码管对应的变量，共八个七段数码管
reg [63:0] OutputList;
//时分复用所必要的信号
reg [3:0]view;//用于片选
reg [16:0]Deg_counter;//用于时分复用的计数

////////////////////////
////////常量部分////////

parameter Compile_Width = 8;//编译时每次读取的字符的位宽度
parameter ValWidth = 4;//变量/常量表的每个存储值的位宽度

//////////////////////////////////////////////////////
////////////////以下为程序正式描述部分////////////////

//数值初始化模块

//处理信号模块
clk_wiz_0 clk65(.clk_in1(clk),.clk_out1(clk_65m),.reset(rst),.locked(lock));//生成65Mhz信号
jitter_clr cleanbutton(.clk(clk_65m),.button(button),.button_clean(button_clean));//按钮信号去抖动
signal_dedge edgeofbutton(.clk(clk_65m),.button(button_clean),.button_rdedge(button_rdedge));//按钮信号取下边沿
jitter_clr cleanback(.clk(clk_65m),.button(backspace),.button_clean(backspace_clean));//回退信号去抖动
signal_edge edgeofback(.clk(clk_65m),.button(backspace_clean),.button_redge(backspace_redge));//回退信号取上边沿

//键盘输入
//keyboard keyboard(.clk(clk_65m),.rst(rst),.ps2_clk(ps2_clk),.ps2_data(ps2_data),.data(led));
//ps2_keyboard_driver ps2_key_driver(.clk(clk_65m),.rst_n(~rst),.ps2k_clk(ps2_clk),.ps2k_data(ps2_data),.ps2_byte(ps2_byte),.ps2_state(ps2_state));

//文字输入模块
always @(posedge clk_65m)
begin
    if(rst)
    begin
        R_ram_we <= 0;
        R_ram_waddr <= 0;
        R_ram_wdata <= 0;
    end
    else if(backspace_redge)
    begin
        R_ram_waddr <= R_ram_waddr - 1 ;
    end
    else if(backspace_clean)
    begin
        R_ram_we <= 1;
        R_ram_wdata <= 0;
    end
    else
    begin
        if(button_rdedge)R_ram_waddr <= R_ram_waddr + 1;
        if (button_clean)
        begin
            R_ram_we <= 1;
            R_ram_wdata <= SW;
        end
        else
            R_ram_we <= 0; 
    end
end


//文字显示模块
vga_ctrl    vga_ctrl( 
.R_clk_65M        (clk_65m), 
.rst        (~lock), 
.R_ram_we   (R_ram_we),
.R_ram_waddr(R_ram_a),
.R_ram_wdata(R_ram_wdata),
.Compile_data(Compile_data),
.hs         (hs), 
.vs         (vs), 
.vga_data   (vga_data) 
);

assign R_ram_a= Compile_E ? Compile_addr : R_ram_waddr;

//读取文字进行编译模块
reg [2:0]Compile_cnt;//计数器,便于执行逐步操作
reg Compile_WhileTag;//标记语句处于while循环结构中
reg Compile_IfTag;//标记语句处于if循环结构中
reg Compile_StepIn;//标记应该写入一个新执行
reg Compile_SyntaxEnd;//标记循环或条件判断结构已经结束
reg Compile_End;
reg [39:0]Compile_WhileInfo;//记录while循环的相关信息，其中39-32记录了循环需要回到的操作位置，31:0记录了循环判断条件
reg [32:0]Compile_IfInfo;//记录if条件判断的相关信息，包括判断条件

always @(posedge clk)
begin
	if(Compile_begin==1)
	begin
		Compile_E <= 1;
		QueueWrite <= 0;
		QueueData <= 0;
		QueueWe <= 0;
		Compile_addr <= 0;
		Compiler <= 0;
		Compile_cnt <= 0;
		Compile_WhileTag <= 0;
		Compile_IfTag <= 0;
		Compile_StepIn <= 0;
		Compile_SyntaxEnd <= 0;
		Compile_End <= 0;
	end
	else if(Compile_E == 1)
	begin
		case (Compile_cnt)
			//第一过程，根据读入信息生成相应数据
			3'b000:
			begin
				//处理写指针后移以及写入的操作时,状态机不发生变化。状态机的推进发生于生成data的每一步之前。
				if(Compile_data != 0)
				Compiler <= (Compiler << 8) + {120'h00000_00000_00000_00000_00000_00000,Compile_data};
				Compile_addr <= Compile_addr + 1;
				Compile_cnt <= 3'b001;
			end
			3'b001:
			begin
				////不需要进行写入操作的前置部分,写指针不需要后移
				//处理While循环前置
				if({Compiler[95:88],Compiler[87:80],Compiler[79:72],Compiler[71:64],Compiler[63:56],Compiler[55:48],Compiler[15:8],Compiler[7:0]}==64'h17_08_09_0c_05_29_2a_2b)
				begin
					Compile_WhileTag <= 1;
					Compile_WhileInfo[31:0] <= Compiler[47:16];
					Compile_WhileInfo[39:32] <= QueueWrite;
				end
				//处理if条件判断前置
				else if({Compiler[71:64],Compiler[63:56],Compiler[55:48],Compiler[15:8],Compiler[7:0]}==40'h09_06_29_2a_2b)
				begin
					Compile_IfTag <= 1;
					Compile_IfInfo <= Compiler[47:16];
				end
				////需要进行写入操作的编写部分,写指针需要移动
				//元语句编译，并适时编入条件判断信息
				else if({Compiler[39:32],Compiler[7:0]} == 16'h2e_2d)	
				begin
					if(Compile_IfTag == 1)
					begin
						QueueData[5:0] <= Compile_IfInfo[29:24] - 1;
						QueueData[13:8] <= Compile_IfInfo[5:0] - 1;
						case (Compile_IfInfo[23:8])
							16'h2e_2e:
							begin
								QueueData[7:6] <= 2'b00;
							end		
							16'h2f_2e:
							begin
								QueueData[7:6] <= 2'b01;
							end
							16'h30_2e:
							begin
								QueueData[7:6] <= 2'b10;
							end
							16'h31_2e:
							begin
								QueueData[7:6] <= 2'b11;
							end
							default:;
						endcase
					end
					else
					begin
						QueueData[13:0] <= 14'b011011_00_011011;
					end
					QueueData[19:14] <= Compiler[45:40] - 1;
					QueueData[25:20] <= Compiler[29:24] - 1;
					QueueData[31:26] <= Compiler[13:8] - 1;
					case (Compiler[23:16])
						8'h25:
						begin
							QueueData[33:32] <= 2'b00;
						end
						8'h26:
						begin
							QueueData[33:32] <= 2'b01;
						end
						8'h27:
						begin		
							QueueData[33:32] <= 2'b10;
						end
						8'h28:
						begin
							QueueData[33:32] <= 2'b11;
						end
						default:;
					endcase
					QueueData[47:34] <= 14'b011011_00_011011;
					QueueData[63:56] <= QueueWrite+1;
					QueueData[55:48] <= QueueWrite+1;
					Compile_StepIn <= 1;
				end//元语句编译结束
				else if(Compiler[7:0]==8'h2c)
				begin
					Compile_SyntaxEnd <= 1;
					Compile_StepIn <= 1;
				end
				else if(Compiler[23:0]==24'h05_0e_04)//结束信号出现
				begin
					QueueData <= 64'hffff_6c6c_6800_1b5b;
					Compile_StepIn <= 1;
					Compile_End <= 1;
				end
				else;
				Compile_cnt <= 3'b010;
			end//第一过程结束
			3'b010:
			begin
				if(Compile_SyntaxEnd == 1 )
				begin
					if(Compile_WhileTag == 1)
					begin
						QueueData[39:34] <= Compile_WhileInfo[29:24] - 1;
						QueueData[47:42] <= Compile_WhileInfo[5:0] - 1;
						QueueData[55:48] <= Compile_WhileInfo[39:32];
						QueueData[63:56] <= QueueWrite;
						case (Compile_WhileInfo[23:8])
							16'h2e_2e:
							begin
								QueueData[41:40] <= 2'b00;
							end
							16'h2f_2e:
							begin
								QueueData[41:40] <= 2'b01;
							end
							16'h30_2e:
							begin
								QueueData[41:40] <= 2'b10;
							end
							16'h31_2e:
							begin
								QueueData[41:40] <= 2'b11;
							end
							default:;
						endcase
					end//处理While循环结束时的data赋值问题
					else ;
				end
				else ;
				Compile_cnt <= 3'b011;
			end
			3'b011:
			begin
			    if(Compile_SyntaxEnd==1)
			    begin
			        if(Compile_WhileTag == 1)
			        begin
			            Compile_WhileTag <= 0;
						Compile_WhileInfo <= 0;
			        end
			        else if(Compile_IfTag == 1)
			        begin
			            Compile_IfTag <= 0;
						Compile_IfInfo <= 0;
			        end
			        else ;
			        Compile_SyntaxEnd <= 0;
			        QueueWrite <= QueueWrite - 1;
			    end
			    Compile_cnt <= 3'b100;
			end
			3'b100:
			begin
				if(Compile_StepIn == 1)
				    QueueWe <= 1;
				Compile_cnt <= 3'b101;
			end
			3'b101:
			begin
				QueueWe <= 0;
				Compile_cnt <= 3'b110;
			end
			3'b110:
			begin
				if(Compile_StepIn == 1)
				    QueueWrite <= QueueWrite + 1;
				Compile_cnt <= 3'b000;
				Compile_StepIn <= 0;
				if(Compile_End == 1)
				    Compile_E <= 0;
			end
			default:;
		endcase//流程判断结束
	end//使能状态下的操作
	else ;
end


//程序执行模块

Queue Queue(
.a(QueueWrite),
.d(QueueData),
.dpra(QueueRead),
.clk(clk),
.we(QueueWe),
.dpo(QueueReadData)
);

reg [2:0]QueueNode_cnt;
reg [3:0]QueueNode_a,QueueNode_b;
reg ending;
reg QueueNode_E,QueueNode_R;
always @(posedge clk)
begin
if(Queue_begin)
begin
	Val[107:104] <= 0;
	Val[111:108] <= 1;
	Val[115:112] <= 2;
	Val[119:116] <= 3;
	Val[123:120] <= 4;
	Val[127:124] <= 5;
	Val[131:128] <= 6;
	Val[135:132] <= 7;
	Val[139:136] <= 8;
	Val[143:140] <= 9;
	Queue_E <= 1;
	QueueRead <= 0;
	QueueNode_cnt <= 0;
end
else if(Queue_E)
begin
	case(QueueNode_cnt)
		3'b000:
		begin
			if(QueueRead==8'hff)
			begin
				QueueNode_cnt <= 8'b110;
				ending <= 1;
			end	
			else
			begin
				ending <= 0;
			QueueNode_a <= {Val[QueueReadData[5:0]*ValWidth+ValWidth-1],Val[QueueReadData[5:0]*ValWidth+ValWidth-2],
			                Val[QueueReadData[5:0]*ValWidth+ValWidth-3],Val[QueueReadData[5:0]*ValWidth+ValWidth-4]};
			//QueueNode_a <= Val[QueueReadData[5:0]+ValWidth:QueueReadData[5:0]];
			QueueNode_b <= {Val[QueueReadData[13:8]*ValWidth+ValWidth-1],Val[QueueReadData[13:8]*ValWidth+ValWidth-2],
			                Val[QueueReadData[13:8]*ValWidth+ValWidth-3],Val[QueueReadData[13:8]*ValWidth+ValWidth-4]};
			QueueNode_cnt<=3'b001;
			end
		end
		3'b001:
		begin
			case(QueueReadData[7:6])
				2'b00:
				begin
					if(QueueNode_a==QueueNode_b)
						QueueNode_E <= 1;
					else
						QueueNode_E <= 0;
				end
				2'b01:
				begin
					if(QueueNode_a>=QueueNode_b)
						QueueNode_E <= 1;
					else
						QueueNode_E <= 0;
				end
				2'b10:
				begin
					if(QueueNode_a<=QueueNode_b)
						QueueNode_E <= 1;
					else
						QueueNode_E <= 0;
				end
				2'b11:
				begin
					if(QueueNode_a!=QueueNode_b)
						QueueNode_E <= 1;
					else
						QueueNode_E <= 0;
				end
			endcase
			QueueNode_cnt<=3'b010;
		end
		3'b010:
		begin
			if(QueueNode_E)
			begin
				case(QueueReadData[33:32])
					2'b00:
					begin
						{Val[QueueReadData[19:14]*ValWidth+ValWidth-1],Val[QueueReadData[19:14]*ValWidth+ValWidth-2],
			                Val[QueueReadData[19:14]*ValWidth+ValWidth-3],Val[QueueReadData[19:14]*ValWidth+ValWidth-4]}<=
			                {Val[QueueReadData[25:20]*ValWidth+ValWidth-1],Val[QueueReadData[25:20]*ValWidth+ValWidth-2],
			                Val[QueueReadData[25:20]*ValWidth+ValWidth-3],Val[QueueReadData[25:20]*ValWidth+ValWidth-4]}+
			                {Val[QueueReadData[31:26]*ValWidth+ValWidth-1],Val[QueueReadData[31:26]*ValWidth+ValWidth-2],
			                Val[QueueReadData[31:26]*ValWidth+ValWidth-3],Val[QueueReadData[31:26]*ValWidth+ValWidth-4]};
							//Val[QueueReadData[25:20]+ValWidth:QueueReadData[25:20]] + Val[QueueReadData[31:26]+ValWidth:QueueReadData[31:26]];
					end
					2'b01:
					begin
						{Val[QueueReadData[19:14]*ValWidth+ValWidth-1],Val[QueueReadData[19:14]*ValWidth+ValWidth-2],
			                Val[QueueReadData[19:14]*ValWidth+ValWidth-3],Val[QueueReadData[19:14]*ValWidth+ValWidth-4]}<=
			                {Val[QueueReadData[25:20]*ValWidth+ValWidth-1],Val[QueueReadData[25:20]*ValWidth+ValWidth-2],
			                Val[QueueReadData[25:20]*ValWidth+ValWidth-3],Val[QueueReadData[25:20]*ValWidth+ValWidth-4]}-
			                {Val[QueueReadData[31:26]*ValWidth+ValWidth-1],Val[QueueReadData[31:26]*ValWidth+ValWidth-2],
			                Val[QueueReadData[31:26]*ValWidth+ValWidth-3],Val[QueueReadData[31:26]*ValWidth+ValWidth-4]};
							//Val[QueueReadData[25:20]+ValWidth:QueueReadData[25:20]] + Val[QueueReadData[31:26]+ValWidth:QueueReadData[31:26]];
					end
					2'b10:
					begin
						{Val[QueueReadData[19:14]*ValWidth+ValWidth-1],Val[QueueReadData[19:14]*ValWidth+ValWidth-2],
			                Val[QueueReadData[19:14]*ValWidth+ValWidth-3],Val[QueueReadData[19:14]*ValWidth+ValWidth-4]}<=
			                {Val[QueueReadData[25:20]*ValWidth+ValWidth-1],Val[QueueReadData[25:20]*ValWidth+ValWidth-2],
			                Val[QueueReadData[25:20]*ValWidth+ValWidth-3],Val[QueueReadData[25:20]*ValWidth+ValWidth-4]}*
			                {Val[QueueReadData[31:26]*ValWidth+ValWidth-1],Val[QueueReadData[31:26]*ValWidth+ValWidth-2],
			                Val[QueueReadData[31:26]*ValWidth+ValWidth-3],Val[QueueReadData[31:26]*ValWidth+ValWidth-4]};
							//Val[QueueReadData[25:20]+ValWidth:QueueReadData[25:20]] + Val[QueueReadData[31:26]+ValWidth:QueueReadData[31:26]];
					end
					2'b11:
					begin
						{Val[QueueReadData[19:14]*ValWidth+ValWidth-1],Val[QueueReadData[19:14]*ValWidth+ValWidth-2],
			                Val[QueueReadData[19:14]*ValWidth+ValWidth-3],Val[QueueReadData[19:14]*ValWidth+ValWidth-4]}<=
			                {Val[QueueReadData[25:20]*ValWidth+ValWidth-1],Val[QueueReadData[25:20]*ValWidth+ValWidth-2],
			                Val[QueueReadData[25:20]*ValWidth+ValWidth-3],Val[QueueReadData[25:20]*ValWidth+ValWidth-4]}/
			                {Val[QueueReadData[31:26]*ValWidth+ValWidth-1],Val[QueueReadData[31:26]*ValWidth+ValWidth-2],
			                Val[QueueReadData[31:26]*ValWidth+ValWidth-3],Val[QueueReadData[31:26]*ValWidth+ValWidth-4]};
							//Val[QueueReadData[25:20]+ValWidth:QueueReadData[25:20]] + Val[QueueReadData[31:26]+ValWidth:QueueReadData[31:26]];
					end
				endcase
			end
			QueueNode_cnt <= 3'b011;
		end
		3'b011:
		begin
			QueueNode_a <= {Val[QueueReadData[39:34]*ValWidth+ValWidth-1],Val[QueueReadData[39:34]*ValWidth+ValWidth-2],
			                Val[QueueReadData[39:34]*ValWidth+ValWidth-3],Val[QueueReadData[39:34]*ValWidth+ValWidth-4]};
			QueueNode_b <= {Val[QueueReadData[47:42]*ValWidth+ValWidth-1],Val[QueueReadData[47:42]*ValWidth+ValWidth-2],
			                Val[QueueReadData[47:42]*ValWidth+ValWidth-3],Val[QueueReadData[47:42]*ValWidth+ValWidth-4]};
			//QueueNode_a <= Val[QueueReadData[39:34]+ValWidth:QueueReadData[39:34]];
			//QueueNode_b <= Val[QueueReadData[47:42]+ValWidth:QueueReadData[47:42]];
			QueueNode_cnt<=3'b100;
		end
		3'b100:
		begin
			case(QueueReadData[41:40])
				2'b00:
				begin
					if(QueueNode_a==QueueNode_b)
						QueueNode_R <= 1;
					else
						QueueNode_R <= 0;
				end
				2'b01:
				begin
					if(QueueNode_a>=QueueNode_b)
						QueueNode_R <= 1;
					else
						QueueNode_R <= 0;
				end
				2'b10:
				begin
					if(QueueNode_a<=QueueNode_b)
						QueueNode_R <= 1;
					else
						QueueNode_R <= 0;
				end
				2'b11:
				begin
					if(QueueNode_a!=QueueNode_b)
						QueueNode_R <= 1;
					else
						QueueNode_R <= 0;
				end
			endcase
			QueueNode_cnt<=3'b101;
		end
		3'b101:
		begin
			if(QueueNode_R ==1)
				QueueRead <= QueueReadData[55:48];
			else
				QueueRead <= QueueReadData[63:56];
			QueueNode_cnt<=3'b110;
		end
		3'b110:
		begin	
			if(ending==1)
			     QueueRead <= 8'h00;
			QueueNode_cnt<=3'b111;
		end
		3'b111:
		begin
			QueueNode_cnt<=3'b000;
			if(ending==1)
			begin
				ending <= 0;
				Queue_E <= 0;
		    end
		end
	endcase
end
else
begin
	Val[106:103] <= 0;
	Val[110:107] <= 1;
	Val[114:111] <= 2;
	Val[118:115] <= 3;
	Val[122:119] <= 4;
	Val[126:123] <= 5;
	Val[130:127] <= 6;
	Val[134:131] <= 7;
	Val[138:135] <= 8;
	Val[142:139] <= 9;
end
end

//时分复用输出模块
Seven_Seg SevenSeg(.a(view),.spo(SSEG_CA));
always @(posedge clk)
begin
    Deg_counter <= Deg_counter + 1;
    case(Deg_counter[16:14])
		3'b000:
		begin
			view <= Val[3:0];
			SSEG_AN <= 8'b1111_1110;
		end
		3'b001:
		begin
			view <= Val[7:4];
			SSEG_AN <= 8'b1111_1101;
		end
		3'b010:
		begin
			view <= Val[11:8];
			SSEG_AN <= 8'b1111_1011;
		end
		3'b011:
		begin
			view <= Val[15:12];
			SSEG_AN <= 8'b1111_0111;
		end
		3'b100:
		begin
			view <= Val[19:16];
			SSEG_AN <= 8'b1110_1111;
		end
		3'b101:
		begin
			view <= Val[23:20];
			SSEG_AN <= 8'b1101_1111;
		end
		3'b110:
		begin
			view <= Val[27:24];
			SSEG_AN <= 8'b1011_1111;
		end
		3'b111:
		begin
			view <= Val[31:28];
			SSEG_AN <= 8'b0111_1111;
		end
		default:;
    endcase
end

endmodule