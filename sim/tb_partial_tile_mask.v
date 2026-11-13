`timescale 1ns/1ps
module tb_partial_tile_mask;
localparam P=2,DW=8,AW=32;
reg clk=0,rst=1,start=0,valid=0; wire [15:0] tm,tn; wire [16:0] step; wire req;
reg signed[P*DW-1:0] a=0,b=0; reg signed[P*P*AW-1:0] bias=0;
wire signed[P*P*DW-1:0] out; wire[P*P-1:0] mask; wire ov,busy,done;
matmul_engine #(.N(P),.DATA_W(DW),.ACC_W(AW)) dut(.clk(clk),.rst(rst),.start(start),.M(16'd1),.Ndim(16'd2),.K(16'd1),
 .tile_m(tm),.tile_n(tn),.feed_step(step),.feed_req(req),.feed_valid(valid),.a_left(a),.b_top(b),.bias_flat(bias),
 .relu_en(1'b0),.qmul(32'sd1),.qshift(6'd0),.zero_point(8'sd0),.out_tile(out),.out_lane_valid(mask),.out_tile_valid(ov),.out_job_last(),.out_tile_ready(1'b1),.busy(busy),.done(done));
always #5 clk=~clk;
always @(negedge clk) begin valid<=0; if(req) begin valid<=1; a<=0; b<=0; end end
initial begin #12;rst=0;@(negedge clk);start=1;@(negedge clk);start=0;wait(ov);#1;
 if(mask!==4'b0011) begin $display("FAIL mask %b",mask);$finish;end
 $display("PASS partial mask");wait(done);$finish; end
endmodule
