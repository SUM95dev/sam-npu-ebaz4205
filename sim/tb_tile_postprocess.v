`timescale 1ns/1ps
module tb_tile_postprocess;
localparam N=2,DW=8,AW=32;
reg clk=0,rst=1,start=0;
reg signed [N*N*AW-1:0] acc_flat=0,bias_flat=0;
wire signed [N*N*DW-1:0] out_tile;
wire busy,done;

tile_postprocess #(.N(N),.DATA_W(DW),.ACC_W(AW)) dut(
 .clk(clk),.rst(rst),.start(start),.acc_flat(acc_flat),.bias_flat(bias_flat),
 .relu_en(1'b0),.qmul(32'sd1),.qshift(6'd0),.zero_point(8'sd0),
 .out_tile(out_tile),.busy(busy),.done(done));
always #5 clk=~clk;
function signed [7:0] O; input integer i; begin O=out_tile[i*DW +: DW]; end endfunction
initial begin
 acc_flat[0*AW +: AW]=32'sd19;
 acc_flat[1*AW +: AW]=32'sd22;
 acc_flat[2*AW +: AW]=32'sd43;
 acc_flat[3*AW +: AW]=32'sd50;
 #12;rst=0;@(negedge clk);start=1;@(negedge clk);start=0;
 wait(done); #1;
 if(O(0)!==19||O(1)!==22||O(2)!==43||O(3)!==50) begin
   $display("FAIL TILE POST %0d %0d %0d %0d",O(0),O(1),O(2),O(3));$finish;
 end
 $display("PASS TILE POST");$finish;
end
endmodule
