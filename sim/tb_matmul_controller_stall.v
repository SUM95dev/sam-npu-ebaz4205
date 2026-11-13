`timescale 1ns/1ps
module tb_matmul_controller_stall;
reg clk=0,rst=1,start=0,feed_valid=0,post_done=0;
wire [15:0] tm,tn; wire [16:0] step; wire req,clr,flush,post_start,ov,busy,done;
matmul_controller #(.N(2)) dut(
 .clk(clk),.rst(rst),.start(start),.M(16'd2),.Ndim(16'd2),.K(16'd2),
 .tile_m(tm),.tile_n(tn),.feed_step(step),.feed_req(req),.feed_valid(feed_valid),
 .clear_acc(clr),.flush_en(flush),.post_start(post_start),.post_done(post_done),.output_ready(1'b1),
 .output_valid(ov),.busy(busy),.done(done));
always #5 clk=~clk;

// Model a postprocessor that completes one cycle after start.
always @(negedge clk) begin
  post_done <= post_start;
end

initial begin
 #12;rst=0;@(negedge clk);start=1;@(negedge clk);start=0;
 wait(req);
 repeat(3) @(negedge clk);
 if(step!==0) begin $display("FAIL stall step=%0d",step);$finish; end
 feed_valid=1;@(negedge clk);feed_valid=0;
 wait(req); #1;
 if(step!==1) begin $display("FAIL next step=%0d",step);$finish; end
 feed_valid=1;@(negedge clk);feed_valid=0;
 wait(req); #1;
 if(step!==2) begin $display("FAIL next step2=%0d",step);$finish; end
 feed_valid=1;@(negedge clk);feed_valid=0;
 wait(ov); $display("PASS controller stall handshake");
 wait(done); $finish;
end
endmodule
