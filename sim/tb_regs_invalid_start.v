`timescale 1ns/1ps
module tb_regs_invalid_start;
reg clk=0,rst=1,wr=0,rd=0,busy=0,done_pulse=0;
reg [5:0] wa=0,ra=0; reg [31:0] wd=0; wire [31:0] rddata;
wire start,mode,relu; wire [15:0] M,N,K; wire signed [31:0] qmul; wire [5:0] qshift; wire signed [7:0] zp;

npu_regs dut(.clk(clk),.rst(rst),.wr_en(wr),.wr_addr(wa),.wr_data(wd),.wr_strb(4'hF),.rd_en(rd),.rd_addr(ra),.rd_data(rddata),
 .busy(busy),.done_pulse(done_pulse),.start_pulse(start),.mode_conv(mode),.M(M),.Ndim(N),.K(K),
 .relu_en(relu),.qmul(qmul),.qshift(qshift),.zero_point(zp));
always #5 clk=~clk;

initial begin
 #12;rst=0;
 // MatMul START with zero dimensions must be rejected and raise config error.
 @(negedge clk);wr=1;wa=0;wd=32'h00000001;
 @(negedge clk);wr=0;wd=0;
 #1;
 if(start!==0) begin $display("FAIL invalid start pulsed");$finish;end
 rd=1;ra=0;#1;
 if(rddata[2]!==1) begin $display("FAIL config error not sticky");$finish;end

 // A partial reconfiguration must NOT clear a sticky configuration error.
 @(negedge clk);rd=0;wr=1;wa=6'h04;wd=1;
 @(negedge clk);wr=0;
 rd=1;ra=0;#1;
 if(rddata[2]!==1) begin $display("FAIL config error cleared by partial config");$finish;end

 // Program the remaining valid dimensions, then START must pulse and clear config error.
 @(negedge clk);rd=0;wr=1;wa=6'h08;wd=1;
 @(negedge clk);wa=6'h0C;wd=1;
 @(negedge clk);wa=0;wd=1;
 @(posedge clk); #1;
 if(start!==1) begin $display("FAIL valid start missing");$finish;end
 @(negedge clk);wr=0;
 rd=1;ra=0;#1;
 if(rddata[2]!==0) begin $display("FAIL config error not cleared");$finish;end
 $display("PASS invalid-start handling");
 $finish;
end
endmodule
