`timescale 1ns/1ps
module tb_conv_stream_bias;
reg clk=0,rst=1,start=0,sv=0,lasts=0,joblast=0,outready=1;
reg signed [7:0] a=0,w=0;reg signed [31:0] bias=0;
wire sr;wire signed[7:0] out;wire ov,ol,busy,done;
integer count=0;
conv_stream_job_engine dut(.clk(clk),.rst(rst),.start(start),.sample_valid(sv),.activation(a),.weight(w),
 .last_sample(lasts),.job_last(joblast),.sample_bias(bias),.relu_en(0),.qmul(1),.qshift(6'd0),.zero_point(8'sd0),
 .sample_ready(sr),.out_data(out),.out_valid(ov),.out_ready(outready),.out_last(ol),.busy(busy),.done(done));
always #5 clk=~clk;
always @(posedge clk) if(ov&&outready) begin
 count=count+1;
 if(count==1 && out!==8'sd11) begin $display("FAIL conv bias first=%0d",out);$finish;end
 if(count==2 && (out!==8'sd17 || !ol)) begin $display("FAIL conv bias second=%0d last=%b",out,ol);$finish;end
end
task beat; input integer av,wv,bv; input jl; begin
 @(negedge clk);while(!sr)@(negedge clk);a=av;w=wv;bias=bv;lasts=1;joblast=jl;sv=1;
 @(negedge clk);sv=0;lasts=0;joblast=0;bias=0;
end endtask
initial begin
 #12;rst=0;@(negedge clk);start=1;@(negedge clk);start=0;
 beat(2,3,5,0); // 6 + 5 = 11
 beat(4,5,-3,1); // 20 - 3 = 17
 wait(done);#1;if(count!==2)begin $display("FAIL conv bias count=%0d",count);$finish;end
 $display("PASS conv per-output bias");$finish;
end
endmodule
