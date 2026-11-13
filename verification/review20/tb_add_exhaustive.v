`timescale 1ns/1ps
module tb_add_exhaustive;
reg clk=0,rst=1,start=0,sv=0,sl=0,ready=0,relu=0;
reg [127:0] data=0;wire sr;wire signed [7:0] out;wire ov,ol,busy,done;
integer a,b,r,expected,count=0,cycles=0;
axis_elementwise_add_engine dut(.clk(clk),.rst(rst),.start(start),.relu_en(relu),.s_axis_tdata(data),.s_axis_tvalid(sv),.s_axis_tlast(sl),.s_axis_tready(sr),.out_data(out),.out_valid(ov),.out_ready(ready),.out_last(ol),.busy(busy),.done(done));
always #5 clk=~clk;
always @(negedge clk)begin cycles=cycles+1;ready=(cycles%7!=0 && cycles%7!=1);end
initial begin
 #12;rst=0;
 for(r=0;r<2;r=r+1)begin
  @(negedge clk);relu=r;start=1;@(negedge clk);start=0;
  for(a=-128;a<128;a=a+1)for(b=-128;b<128;b=b+1)begin
   @(negedge clk);while(!sr)@(negedge clk);
   data={112'd0,b[7:0],a[7:0]};sv=1;sl=(a==127&&b==127);
   @(posedge clk);#1;expected=a+b;
   if(r&&expected<0)expected=0;if(expected>127)expected=127;if(expected< -128)expected=-128;
   if(!ov || $signed(out)!==expected || ol!==sl)begin $display("FAIL Add a=%0d b=%0d relu=%0d got=%0d expected=%0d",a,b,r,out,expected);$finish;end
   count=count+1;@(negedge clk);sv=0;
  end
  wait(done);@(negedge clk);
 end
 $display("PASS exhaustive Add: %0d signed pairs including ReLU and stalls",count);$finish;
end
initial begin #10000000;$display("FAIL timeout");$finish;end
endmodule
