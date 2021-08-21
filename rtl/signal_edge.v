module signal_edge(clk,button,button_redge);
    input clk;
    input button;
    output button_redge;
    reg button_r1;

always@(posedge clk)
    button_r1 <= button;
assign button_redge = button & (~button_r1);
endmodule
