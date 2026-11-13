`timescale 1ns/1ps
module tb_conv_final_fence;
reg clk=0,rst=1,start=0,sv=0,lasts=0,joblast=0,outready=0;
reg signed [7:0] a=2,w=3;wire sr;wire signed [7:0] out;wire ov,ol,busy,done;
conv_stream_job_engine dut(.clk(clk),.rst(rst),.start(start),.sample_valid(sv),.activation(a),.weight(w),
.last_sample(lasts),.job_last(joblast),.sample_bias(32'sd0),.relu_en(1'b0),.qmul(32'sd1),.qshift(6'd0),.zero_point(8'sd0),
.sample_ready(sr),.out_data(out),.out_valid(ov),.out_ready(outready),.out_last(ol),.busy(busy),.done(done));
always #5 clk=~clk;
integer i;
initial begin
 #12;rst=0;@(negedge clk);start=1;@(negedge clk);start=0;
 sv=1;lasts=1;joblast=1;while(!sr)@(negedge clk);
 @(negedge clk);lasts=0;joblast=0; // Keep a following sample valid continuously.
 for(i=0;i<24;i=i+1)begin
  if(sr)begin $display("FAIL Conv accepted data beyond final sample");$finish;end
  @(negedge clk);
 end
 if(!ov || !ol || out!==8'sd6 || !busy)begin $display("FAIL final output stalled");$finish;end
 outready=1;@(negedge clk);#1;
 if(!done || busy || sr)begin $display("FAIL final completion");$finish;end
 sv=0;start=1;@(negedge clk);start=0;sv=1;lasts=1;joblast=1;a=-2;w=4;
 while(!sr)@(negedge clk);@(negedge clk);sv=0;
 wait(ov);#1;if(out!==-8'sd8 || !ol)begin $display("FAIL restart");$finish;end
 wait(done);$display("PASS Conv final fence and restart");$finish;
end
initial begin #10000;$display("FAIL timeout");$finish;end
endmodule
