`timescale 1ns/1ps
module tb_conv_config_latch;
reg clk=0,rst=1,start=0,valid=0,last=0;
reg signed [7:0] a=0,w=0,zp=0;
reg signed [31:0] bias=0,qmul=1;
reg [5:0] qshift=0;
reg relu=0;
wire ready,ov,busy,done; wire signed [7:0] out;

conv2d_stream_engine dut(
 .clk(clk),.rst(rst),.start(start),.sample_valid(valid),.activation(a),.weight(w),.last_sample(last),
 .bias(bias),.relu_en(relu),.qmul(qmul),.qshift(qshift),.zero_point(zp),
 .sample_ready(ready),.out_data(out),.out_valid(ov),.busy(busy),.done(done));
always #5 clk=~clk;

initial begin
 #12; rst=0;
 // First sample is accepted on the same cycle as START.
 @(negedge clk); start=1; valid=1; a=2; w=3; last=0; bias=5; qmul=1; qshift=0; relu=0; zp=0;
 // Change all config inputs after START. Engine must keep the latched values.
 @(negedge clk); start=0; a=4; w=5; last=1; bias=100; qmul=7; qshift=1; relu=1; zp=10;
 @(negedge clk); valid=0; last=0;
 wait(ov); #1;
 // (2*3 + 4*5) + original bias 5 = 31.
 if(out!==8'sd31) begin $display("FAIL CONV LATCH out=%0d",out); $finish; end
 $display("PASS CONV CONFIG LATCH"); $finish;
end
endmodule
