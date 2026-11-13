`timescale 1ns/1ps
module tb_axis_maxpool;
reg clk=0,rst=1,start=0,tv=0,tl=0,ready=0;reg [127:0] td=0;
wire tr;wire signed[7:0] od;wire ov,ol,busy,done;
axis_maxpool2x2_engine dut(.clk(clk),.rst(rst),.start(start),.s_axis_tdata(td),.s_axis_tvalid(tv),
 .s_axis_tlast(tl),.s_axis_tready(tr),.out_data(od),.out_valid(ov),.out_ready(ready),.out_last(ol),.busy(busy),.done(done));
always #5 clk=~clk;
task beat; input integer v;input l;begin @(negedge clk);while(!tr)@(negedge clk);td=0;td[7:0]=v;tv=1;tl=l;@(negedge clk);tv=0;tl=0;end endtask
initial begin
 #12;rst=0;@(negedge clk);start=1;@(negedge clk);start=0;
 beat(-3,0);beat(7,0);beat(2,0);beat(5,1);
 wait(ov);#1;if(od!==8'sd7 || !ol)begin $display("FAIL pool out=%0d last=%b",od,ol);$finish;end
 repeat(2)@(negedge clk);if(!ov || od!==8'sd7)begin $display("FAIL pool backpressure");$finish;end
 ready=1;wait(done);#1;
 $display("PASS axis maxpool2x2");$finish;
end
endmodule
