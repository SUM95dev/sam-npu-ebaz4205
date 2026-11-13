`timescale 1ns/1ps
module tb_postprocess_pipe_equivalence;
reg clk=0,rst=1,valid=0,relu=0;
reg signed [31:0] acc=0,bias=0,mul=1;
reg [5:0] shift=0;
reg signed [7:0] zp=0;
wire signed [7:0] ref_out,out;
wire ov;
reg signed [7:0] expected[0:5];
integer i,seen=0,seed=9511;
npu_postprocess reference(.acc_in(acc),.bias_in(bias),.relu_en(relu),.multiplier(mul),.shift(shift),.zero_point(zp),.out(ref_out));
npu_postprocess_pipe dut(.clk(clk),.rst(rst),.in_valid(valid),.acc_in(acc),.bias_in(bias),.relu_en(relu),.multiplier(mul),.shift(shift),.zero_point(zp),.out_valid(ov),.out(out));
always #5 clk=~clk;
always @(posedge clk) begin
 if(rst) begin for(i=0;i<6;i=i+1) expected[i]<=0;end
 else begin
  expected[0]<=ref_out;
  for(i=1;i<6;i=i+1) expected[i]<=expected[i-1];
  if(ov) begin
   if(out!==expected[5]) begin $display("FAIL PIPE out=%0d expected=%0d",out,expected[5]);$finish;end
   seen=seen+1;
  end
 end
end
integer n;
initial begin
 #12;rst=0;
 for(n=0;n<10000;n=n+1) begin
  @(negedge clk);
  valid=(n%13!=0);
  acc=$random(seed);bias=$random(seed);mul=$random(seed);
  shift=$random(seed);relu=$random(seed);zp=$random(seed);
  if(n%17==0) begin acc=32'h80000000;bias=32'h80000000;mul=32'h80000000;end
  if(n%19==0) begin acc=32'h7fffffff;bias=32'h7fffffff;mul=32'h7fffffff;end
 end
 @(negedge clk);valid=0;
 repeat(10) @(negedge clk);
 if(seen<9000) begin $display("FAIL PIPE count=%0d",seen);$finish;end
 $display("PASS PIPE equivalent valid_samples=%0d",seen);$finish;
end
initial begin #200000;$display("FAIL PIPE timeout");$finish;end
endmodule
