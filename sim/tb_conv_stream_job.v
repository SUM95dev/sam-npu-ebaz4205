`timescale 1ns/1ps
module tb_conv_stream_job;
reg clk=0,rst=1,start=0,sv=0,lasts=0,joblast=0,outready=0;
reg signed [7:0] a=0,w=0; wire sr;wire signed[7:0] out;wire ov,ol,busy,done;
integer outcount=0;
conv_stream_job_engine dut(.clk(clk),.rst(rst),.start(start),.sample_valid(sv),.activation(a),.weight(w),
 .last_sample(lasts),.job_last(joblast),.sample_bias(32'sd0),.relu_en(0),.qmul(1),.qshift(6'd0),.zero_point(8'sd0),
 .sample_ready(sr),.out_data(out),.out_valid(ov),.out_ready(outready),.out_last(ol),.busy(busy),.done(done));
always #5 clk=~clk;
always @(posedge clk) if(ov&&outready) outcount=outcount+1;
task beat; input integer av;input integer wv;input ls;input jl; begin
 @(negedge clk); while(!sr) @(negedge clk); a=av;w=wv;lasts=ls;joblast=jl;sv=1;
 @(negedge clk);sv=0;lasts=0;joblast=0;
end endtask
initial begin
 #12;rst=0;@(negedge clk);start=1;@(negedge clk);start=0;outready=1;
 beat(2,3,0,0);beat(1,4,1,0); // output 10
 beat(5,2,0,0);beat(1,1,1,1); // output 11, job end
 wait(done);#1;
 if(outcount!==2) begin $display("FAIL outputs=%0d",outcount);$finish;end
 $display("PASS conv stream multi-output job");$finish;
end
endmodule
