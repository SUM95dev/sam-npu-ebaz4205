`timescale 1ns/1ps
module tb_conv_stream;
reg clk=0,rst=1,start=0,valid=0,last=0; reg signed[7:0] a=0,w=0; wire ready,ov,busy,done; wire signed[7:0] out;
conv2d_stream_engine dut(.clk(clk),.rst(rst),.start(start),.sample_valid(valid),.activation(a),.weight(w),.last_sample(last),
 .bias(32'sd0),.relu_en(1'b0),.qmul(32'sd1),.qshift(6'd0),.zero_point(8'sd0),.sample_ready(ready),.out_data(out),.out_valid(ov),.busy(busy),.done(done));
always #5 clk=~clk;
initial begin #12;rst=0;@(negedge clk);start=1;valid=1;a=2;w=3;last=0;@(negedge clk);start=0;a=4;w=5;last=1;
 @(negedge clk);valid=0;last=0;wait(ov);#1;if(out!==26) $display("FAIL CONV %0d",out); else $display("PASS CONV");$finish;end
endmodule
