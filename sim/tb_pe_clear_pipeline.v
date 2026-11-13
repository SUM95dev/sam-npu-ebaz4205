`timescale 1ns/1ps
module tb_pe_clear_pipeline;
reg clk=0,rst=1,clear=0,en=0;reg signed[7:0]a=0,b=0;
wire signed[7:0]ao,bo;wire signed[31:0]acc;
npu_pe dut(.clk(clk),.rst(rst),.clear_acc(clear),.en(en),.a_in(a),.b_in(b),.a_out(ao),.b_out(bo),.acc(acc));
always #5 clk=~clk;
initial begin
 #12;rst=0;@(negedge clk);en=1;a=7;b=9;@(negedge clk);en=0;
 @(negedge clk);clear=1;@(negedge clk);clear=0;#1;
 if(acc!==0 || ao!==0 || bo!==0) begin $display("FAIL clear pipeline");$finish;end
 $display("PASS clear pipeline");$finish;
end
endmodule
