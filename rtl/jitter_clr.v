module jitter_clr(clk,button,button_clean);
	input clk;
	input button;
	output button_clean;
	reg [11:0]   cnt;

always@(posedge clk)
begin
	if(button==1'b0)  
		cnt <= 12'h000;
	else if(cnt<12'hfff)
		cnt <= cnt + 12'h001;
end
assign button_clean = cnt[11];
endmodule