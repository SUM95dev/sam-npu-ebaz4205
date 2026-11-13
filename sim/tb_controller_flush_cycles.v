`timescale 1ns/1ps
module tb_controller_flush_cycles;
reg clk=0,rst=1,start2=0,start8=0;
wire [15:0] tm2,tn2,tm8,tn8; wire [16:0] fs2,fs8; wire fr2,fr8;
wire ca2,fl2,ps2,ov2,bz2,dn2; wire ca8,fl8,ps8,ov8,bz8,dn8;
reg pd2=0,pd8=0;
integer flush2=0,flush8=0;
reg done2_seen=0, done8_seen=0;
matmul_controller #(.N(2)) c2(.clk(clk),.rst(rst),.start(start2),.M(1),.Ndim(1),.K(1),
 .tile_m(tm2),.tile_n(tn2),.feed_step(fs2),.feed_req(fr2),.feed_valid(1'b1),
 .clear_acc(ca2),.flush_en(fl2),.post_start(ps2),.post_done(pd2),.output_ready(1'b1),.output_valid(ov2),.output_last(),.busy(bz2),.done(dn2));
matmul_controller #(.N(8)) c8(.clk(clk),.rst(rst),.start(start8),.M(1),.Ndim(1),.K(1),
 .tile_m(tm8),.tile_n(tn8),.feed_step(fs8),.feed_req(fr8),.feed_valid(1'b1),
 .clear_acc(ca8),.flush_en(fl8),.post_start(ps8),.post_done(pd8),.output_ready(1'b1),.output_valid(ov8),.output_last(),.busy(bz8),.done(dn8));
always #5 clk=~clk;
always @(posedge clk) begin
 if(fl2) flush2=flush2+1;
 if(fl8) flush8=flush8+1;
 if(dn2) done2_seen<=1;
 if(dn8) done8_seen<=1;
 pd2<=ps2; pd8<=ps8;
end
initial begin
 #12;rst=0; @(negedge clk);start2=1;start8=1; @(negedge clk);start2=0;start8=0;
 wait(done2_seen && done8_seen); #1;
 if(flush2!==1) begin $display("FAIL N2 flush=%0d",flush2);$finish; end
 if(flush8!==7) begin $display("FAIL N8 flush=%0d",flush8);$finish; end
 $display("PASS flush counts N2=%0d N8=%0d",flush2,flush8);$finish;
end
endmodule
