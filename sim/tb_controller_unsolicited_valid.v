`timescale 1ns/1ps
module tb_controller_unsolicited_valid;
reg clk=0,rst=1,start=0,valid=1,post_done=0;
wire [15:0] tm,tn; wire [16:0] step; wire req,clr,flush,post_start,ov,busy,done;
matmul_controller #(.N(2)) dut(.clk(clk),.rst(rst),.start(start),.M(16'd2),.Ndim(16'd2),.K(16'd2),
 .tile_m(tm),.tile_n(tn),.feed_step(step),.feed_req(req),.feed_valid(valid),
 .clear_acc(clr),.flush_en(flush),.post_start(post_start),.post_done(post_done),.output_ready(1'b1),
 .output_valid(ov),.busy(busy),.done(done));
always #5 clk=~clk;
always @(negedge clk) post_done <= post_start;
initial begin
 #12;rst=0;@(negedge clk);start=1;@(negedge clk);start=0;
 wait(req); #1;
 if(step!==0) begin $display("FAIL unsolicited valid advanced step=%0d",step);$finish;end
 @(posedge clk); #1;
 if(step!==1) begin $display("FAIL first handshake step=%0d",step);$finish;end
 $display("PASS unsolicited-valid handshake");$finish;
end
endmodule
