`timescale 1ns/1ps
module tb_npu_pe;
reg clk=0,rst=1,clear_acc=0,en=0; reg signed [7:0] a=0,b=0;
wire signed [7:0] ao,bo; wire signed [31:0] acc;
npu_pe dut(.clk(clk),.rst(rst),.clear_acc(clear_acc),.en(en),.a_in(a),.b_in(b),.a_out(ao),.b_out(bo),.acc(acc));
always #5 clk=~clk;
initial begin
 #12;rst=0; @(negedge clk);clear_acc=1; @(negedge clk);clear_acc=0;en=1;a=2;b=4;
 @(negedge clk);a=3;b=5; @(negedge clk);a=-1;b=6; @(negedge clk);en=0; #2;
 if(acc!==17) $display("FAIL PE got=%0d",acc); else $display("PASS PE"); $finish;
end
endmodule
