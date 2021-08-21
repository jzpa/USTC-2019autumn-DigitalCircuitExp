`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2019/12/12 21:49:53
// Design Name: 
// Module Name: signal_dedge
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////
module signal_dedge(clk,button,button_rdedge);
    input clk;
    input button;
    output button_rdedge;
    reg button_r1;

always@(posedge clk)
    button_r1 <= button;
assign button_rdedge = ~button & (button_r1);
endmodule
