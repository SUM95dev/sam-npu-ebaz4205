`timescale 1ns/1ps
module tb_axi_lite_random_stalls;
reg clk=0,rstn=0;always #5 clk=~clk;
reg [5:0] aa=0,ra=0;reg av=0,wv=0,br=0,rv=0,rr=0;reg [31:0] wd=0;reg [3:0] ws=0;
wire ar,wr,bv,rar,rrv;wire [1:0] bp,rp;wire [31:0] rd;
wire regwr,regrd;wire [5:0] regwa,regra;wire [31:0] regwd;wire [3:0] regws;reg [31:0] bank[0:15],expected[0:15];
wire [31:0] regrdata=regrd?bank[regra[5:2]]:32'd0;
npu_axi_lite_slave dut(.aclk(clk),.aresetn(rstn),.s_axi_awaddr(aa),.s_axi_awvalid(av),.s_axi_awready(ar),
.s_axi_wdata(wd),.s_axi_wstrb(ws),.s_axi_wvalid(wv),.s_axi_wready(wr),.s_axi_bresp(bp),.s_axi_bvalid(bv),.s_axi_bready(br),
.s_axi_araddr(ra),.s_axi_arvalid(rv),.s_axi_arready(rar),.s_axi_rdata(rd),.s_axi_rresp(rp),.s_axi_rvalid(rrv),.s_axi_rready(rr),
.reg_wr(regwr),.reg_waddr(regwa),.reg_wdata(regwd),.reg_wstrb(regws),.reg_rd(regrd),.reg_raddr(regra),.reg_rdata(regrdata));
integer i,j,n,ad,dd,stall,idx,seed=7231,writes=0;
always @(posedge clk)if(regwr)begin
 writes=writes+1;
 for(j=0;j<4;j=j+1)if(regws[j])bank[regwa[5:2]][j*8+:8]<=regwd[j*8+:8];
end
initial begin
 for(i=0;i<16;i=i+1)begin bank[i]=0;expected[i]=0;end
 #12;rstn=1;
 for(n=0;n<300;n=n+1)begin
  idx=($random(seed)&32'h7fffffff)%16;ad=($random(seed)&7);dd=($random(seed)&7);stall=($random(seed)&7);
  @(negedge clk);aa=idx*4;wd=$random(seed);ws=$random(seed);
  for(i=0;i<4;i=i+1)if(ws[i])expected[idx][i*8+:8]=wd[i*8+:8];
  fork
   begin repeat(ad)@(negedge clk);av=1;@(posedge clk);while(!ar)@(posedge clk);@(negedge clk);av=0;end
   begin repeat(dd)@(negedge clk);wv=1;@(posedge clk);while(!wr)@(posedge clk);@(negedge clk);wv=0;end
  join
  wait(bv);repeat(stall)begin @(negedge clk);if(!bv||bp!==0)begin $display("FAIL B hold");$finish;end end
  @(negedge clk);br=1;@(posedge clk);@(negedge clk);br=0;
  ra=idx*4;rv=1;@(posedge clk);while(!rar)@(posedge clk);@(negedge clk);rv=0;
  wait(rrv);repeat(stall)begin @(negedge clk);if(!rrv||rd!==expected[idx]||rp!==0)begin $display("FAIL R hold/value txn=%0d got=%h want=%h",n,rd,expected[idx]);$finish;end end
  if(rd!==expected[idx])begin $display("FAIL readback txn=%0d",n);$finish;end
  @(negedge clk);rr=1;@(posedge clk);@(negedge clk);rr=0;
 end
 if(writes!=300)begin $display("FAIL duplicate/missing writes %0d",writes);$finish;end
 $display("PASS AXI-Lite 300 random AW/W delays, WSTRB and stalled B/R responses");$finish;
end
initial begin #190000;$display("FAIL AXI stress timeout");$finish;end
endmodule
