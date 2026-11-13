`timescale 1ns/1ps
module tb_regs_extended;
reg clk=0,rst=1,wr=0,rd=0,busy=0,done=0;
reg [5:0] wa=0,ra=0; reg [31:0] wd=0; wire [31:0] rdata;
wire start,mc,mp,ma,mbias,relu,abort,irq; wire [15:0] M,N,K; wire signed [31:0] qmul; wire [5:0] qshift; wire signed [7:0] zp;
npu_regs dut(.clk(clk),.rst(rst),.wr_en(wr),.wr_addr(wa),.wr_data(wd),.wr_strb(4'hF),
 .rd_en(rd),.rd_addr(ra),.rd_data(rdata),.busy(busy),.done_pulse(done),.start_pulse(start),
 .mode_conv(mc),.mode_pool(mp),.mode_add(ma),.matmul_bias_en(mbias),.M(M),.Ndim(N),.K(K),.relu_en(relu),
 .qmul(qmul),.qshift(qshift),.zero_point(zp),.abort_pulse(abort),.irq(irq));
always #5 clk=~clk;
task write_reg; input [5:0] a; input [31:0] d; begin @(negedge clk);wa=a;wd=d;wr=1;@(negedge clk);wr=0;end endtask
task read_check_nonzero; input [5:0] a; begin ra=a;rd=1;#1;if(rdata===0)begin $display("FAIL zero register %h",a);$finish;end rd=0;end endtask
initial begin
 #12;rst=0;
 ra=6'h24;rd=1;#1;if(rdata!==32'h00020000)begin $display("FAIL version %h",rdata);$finish;end rd=0;
 ra=6'h28;rd=1;#1;if(rdata[7:0]!==8'hff)begin $display("FAIL caps %h",rdata);$finish;end rd=0;
 write_reg(6'h04,32'd1);write_reg(6'h08,32'd1);write_reg(6'h0c,32'd1);
 write_reg(6'h00,32'h00000010); // configure MatMul streamed bias without START
 #1;if(!mbias)begin $display("FAIL matmul bias config");$finish;end
 write_reg(6'h14,32'h1); // IRQ enable
 @(negedge clk);done=1;@(negedge clk);done=0;#1;
 if(!irq)begin $display("FAIL irq not asserted");$finish;end
 write_reg(6'h14,32'h3); // preserve irq_en + ACK_DONE
 #1;if(irq)begin $display("FAIL irq not cleared");$finish;end
 busy=1;repeat(5)@(negedge clk);busy=0;
 read_check_nonzero(6'h2c);read_check_nonzero(6'h30);
 busy=1;write_reg(6'h14,32'h11);#1;if(!abort)begin $display("FAIL abort pulse");$finish;end
 @(negedge clk);busy=0;
 // Two modes at once + START must be rejected and counted.
 write_reg(6'h00,32'h00000007); // start + conv + pool
 ra=6'h00;rd=1;#1;if(!rdata[2])begin $display("FAIL invalid multimode not flagged");$finish;end rd=0;
 read_check_nonzero(6'h38);
 $display("PASS extended regs irq abort caps perf");$finish;
end
endmodule
