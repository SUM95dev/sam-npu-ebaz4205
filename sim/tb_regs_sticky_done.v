`timescale 1ns/1ps
module tb_regs_sticky_done;
reg clk=0,rst=1,wr=0,rd=0,busy=0,done_pulse=0;
reg [5:0] wa=0,ra=0; reg [31:0] wd=0; wire [31:0] rddata;
wire start,mode,relu; wire [15:0] M,N,K; wire signed [31:0] qmul; wire [5:0] qshift; wire signed [7:0] zp;

npu_regs dut(.clk(clk),.rst(rst),.wr_en(wr),.wr_addr(wa),.wr_data(wd),.wr_strb(4'hF),.rd_en(rd),.rd_addr(ra),.rd_data(rddata),
 .busy(busy),.done_pulse(done_pulse),.start_pulse(start),.mode_conv(mode),.M(M),.Ndim(N),.K(K),
 .relu_en(relu),.qmul(qmul),.qshift(qshift),.zero_point(zp));
always #5 clk=~clk;

initial begin
 #12;rst=0;
 // Latch DONE.
 @(negedge clk);done_pulse=1;
 @(negedge clk);done_pulse=0;
 rd=1;ra=0;#1;
 if(rddata[1]!==1) begin $display("FAIL sticky set");$finish;end

 // Program valid MatMul dimensions before starting a new job.
 @(negedge clk);rd=0;wr=1;wa=6'h04;wd=1;
 @(negedge clk);wa=6'h08;wd=1;
 @(negedge clk);wa=6'h0C;wd=1;
 // Valid START must clear sticky DONE.
 @(negedge clk);wa=0;wd=32'h1;
 @(posedge clk); #1;
 if(start!==1) begin $display("FAIL valid start missing");$finish;end
 @(negedge clk);wr=0;
 rd=1;ra=0;#1;
 if(rddata[1]!==0) begin $display("FAIL sticky clear");$finish;end
 $display("PASS sticky done");
 $finish;
end
endmodule
