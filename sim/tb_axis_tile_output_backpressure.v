`timescale 1ns/1ps
module tb_axis_tile_output_backpressure;
localparam N=2,DW=8,AW=32;
reg clk=0,rst=1,tv=0,tl=1,ready=0;
reg signed [N*N*DW-1:0] td=0;
reg [N*N-1:0] mask=4'b1111;
wire tr; wire [AW-1:0] data; wire valid,last,busy;
integer count=0; reg [7:0] seen[0:3];
axis_tile_output #(.N(N),.DATA_W(DW),.AXIS_W(AW)) dut(
 .clk(clk),.rst(rst),.tile_valid(tv),.tile_last(tl),.tile_ready(tr),.tile_data(td),.lane_valid(mask),
 .m_axis_tdata(data),.m_axis_tvalid(valid),.m_axis_tready(ready),.m_axis_tlast(last),.busy(busy));
always #5 clk=~clk;
always @(posedge clk) if(valid&&ready) begin seen[count]=data[7:0]; count=count+1; end
initial begin
 td[7:0]=8'd1;td[15:8]=8'd2;td[23:16]=8'd3;td[31:24]=8'd4;
 #12;rst=0;@(negedge clk);tv=1;@(negedge clk);tv=0;
 repeat(3) @(negedge clk); ready=1; @(negedge clk);ready=0;
 repeat(2) @(negedge clk); ready=1;
 wait(!busy); repeat(2) @(posedge clk);
 if(count!==4) begin $display("FAIL count=%0d",count);$finish;end
 if(seen[0]!=1||seen[1]!=2||seen[2]!=3||seen[3]!=4) begin $display("FAIL data");$finish;end
 $display("PASS axis tile backpressure");$finish;
end
endmodule
