`timescale 1ns/1ps
module tb_matmul_output_backpressure;
reg clk=0,rst=1,start=0,feed_valid=1,post_done=0,out_ready=0;
wire [15:0] tm,tn;wire [16:0] step;wire req,clr,flush,ps,ov,ol,busy,done;
integer held=0;
matmul_controller #(.N(2)) dut(
 .clk(clk),.rst(rst),.start(start),.M(1),.Ndim(1),.K(1),.tile_m(tm),.tile_n(tn),.feed_step(step),
 .feed_req(req),.feed_valid(feed_valid),.clear_acc(clr),.flush_en(flush),.post_start(ps),.post_done(post_done),
 .output_ready(out_ready),.output_valid(ov),.output_last(ol),.busy(busy),.done(done));
always #5 clk=~clk;
always @(posedge clk) begin
 post_done<=ps;
 if(ov&&!out_ready) held=held+1;
end
initial begin
 #12;rst=0;@(negedge clk);start=1;@(negedge clk);start=0;
 wait(ov); repeat(5) @(posedge clk);
 if(!ov||done) begin $display("FAIL did not hold output");$finish;end
 out_ready=1; wait(done); #1;
 if(!ol && ov) begin $display("FAIL last");$finish;end
 if(held<4) begin $display("FAIL hold cycles %0d",held);$finish;end
 $display("PASS matmul output backpressure");$finish;
end
endmodule
