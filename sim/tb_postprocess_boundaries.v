`timescale 1ns/1ps
module tb_postprocess_boundaries;
reg signed [31:0] acc,bias,mul;
reg [5:0] shift;
reg relu;
reg signed [7:0] zp;
wire signed [7:0] out;

npu_postprocess dut(
 .acc_in(acc),.bias_in(bias),.relu_en(relu),.multiplier(mul),
 .shift(shift),.zero_point(zp),.out(out));

initial begin
 acc=32'sd100; bias=32'sd20; mul=32'sd1; shift=0; relu=0; zp=0; #1;
 if(out!==8'sd120) begin $display("FAIL post normal %0d",out);$finish;end

 acc=32'sh7fffffff; bias=32'sh7fffffff; mul=32'sd1; #1;
 if(out!==8'sd127) begin $display("FAIL post positive wide add %0d",out);$finish;end

 acc=-32'sh80000000; bias=-32'sh7fffffff; mul=32'sd1; #1;
 if(out!==-8'sd128) begin $display("FAIL post negative wide add %0d",out);$finish;end

 acc=-32'sd10; bias=0; relu=1; #1;
 if(out!==0) begin $display("FAIL post relu %0d",out);$finish;end

 acc=32'sd10; relu=0; mul=32'sd3; shift=1; zp=-8'sd2; #1;
 if(out!==8'sd13) begin $display("FAIL post scale %0d",out);$finish;end

 $display("PASS postprocess boundaries");
 $finish;
end
endmodule
