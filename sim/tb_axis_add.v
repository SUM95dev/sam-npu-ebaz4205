`timescale 1ns/1ps
module tb_axis_add;
reg clk=0,rst=1,start=0,tv=0,tl=0,ready=1,relu=0;reg [127:0] td=0;
wire tr;wire signed[7:0] od;wire ov,ol,busy,done;integer cnt=0;
axis_elementwise_add_engine dut(.clk(clk),.rst(rst),.start(start),.relu_en(relu),.s_axis_tdata(td),.s_axis_tvalid(tv),
 .s_axis_tlast(tl),.s_axis_tready(tr),.out_data(od),.out_valid(ov),.out_ready(ready),.out_last(ol),.busy(busy),.done(done));
always #5 clk=~clk;
always @(posedge clk) if(ov&&ready) begin cnt=cnt+1;
 if(cnt==1 && od!==8'sd127)begin $display("FAIL add sat+ %0d",od);$finish;end
 if(cnt==2 && (od!==8'sh80 || !ol))begin $display("FAIL add sat- %0d last=%b",od,ol);$finish;end
end
task beat;input integer a,b;input l;begin @(negedge clk);while(!tr)@(negedge clk);td=0;td[7:0]=a;td[15:8]=b;tv=1;tl=l;@(negedge clk);tv=0;tl=0;end endtask
initial begin #12;rst=0;@(negedge clk);start=1;@(negedge clk);start=0;
 beat(120,20,0);beat(-100,-50,1);wait(done);#1;if(cnt!==2)begin $display("FAIL add count=%0d",cnt);$finish;end
 $display("PASS axis elementwise add");$finish;end
endmodule
