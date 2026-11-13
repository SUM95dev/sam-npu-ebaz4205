`timescale 1ns/1ps
module tb_regs_start_lock;
reg clk=0,rst=1,wr_en=0,rd_en=0,busy=0,done_pulse=0;
reg [5:0] wr_addr=0,rd_addr=0; reg [31:0] wr_data=0;
wire [31:0] rd_data; wire start_pulse,mode_conv,relu_en; wire [15:0] M,Ndim,K;
wire signed [31:0] qmul; wire [5:0] qshift; wire signed [7:0] zero_point;
npu_regs dut(.clk(clk),.rst(rst),.wr_en(wr_en),.wr_addr(wr_addr),.wr_data(wr_data),.wr_strb(4'hF),
 .rd_en(rd_en),.rd_addr(rd_addr),.rd_data(rd_data),.busy(busy),.done_pulse(done_pulse),
 .start_pulse(start_pulse),.mode_conv(mode_conv),.M(M),.Ndim(Ndim),.K(K),
 .relu_en(relu_en),.qmul(qmul),.qshift(qshift),.zero_point(zero_point));
always #5 clk=~clk;
task W; input [5:0] a; input [31:0] d; begin
 @(negedge clk); wr_en=1;wr_addr=a;wr_data=d;
 @(negedge clk); wr_en=0;
end endtask
initial begin
 #12;rst=0;
 W(6'h04,32'd2); W(6'h08,32'd2); W(6'h0C,32'd2);
 // Accept START while busy is still low.
 @(negedge clk); wr_en=1;wr_addr=0;wr_data=1;
 @(posedge clk); #1;
 if(!start_pulse) begin $display("FAIL no start pulse");$finish; end
 // Try to overwrite M during the start-pending cycle; must be ignored.
 @(negedge clk); wr_addr=6'h04;wr_data=32'd99;wr_en=1;
 @(posedge clk); #1;
 if(M!==16'd2) begin $display("FAIL start lock M=%0d",M);$finish; end
 wr_en=0;
 $display("PASS start-pending config lock");$finish;
end
endmodule
