`timescale 1ns/1ps
module tb_case_5_0;
localparam N=8,DW=8,AWIN=128,AWOUT=32;
reg clk=0,aresetn=0;
reg [5:0] awaddr=0,araddr=0; reg awvalid=0,wvalid=0,bready=1,arvalid=0,rready=1;
reg [31:0] wdata=0; reg [3:0] wstrb=4'hF;
wire awready,wready; wire [1:0] bresp; wire bvalid; wire arready; wire [31:0] rdata; wire [1:0] rresp; wire rvalid;
reg [AWIN-1:0] sid=0; reg siv=0,sil=0; wire sir;
wire [AWOUT-1:0] mod; wire mov,mol; reg mor=0;
wire signed [N*N*32-1:0] bias=0;
integer held=0;

npu_axis_system_top #(.N(N),.DATA_W(DW),.ACC_W(32),.AXIS_IN_W(AWIN),.AXIS_OUT_W(AWOUT)) dut(
 .aclk(clk),.aresetn(aresetn),
 .s_axi_awaddr(awaddr),.s_axi_awvalid(awvalid),.s_axi_awready(awready),
 .s_axi_wdata(wdata),.s_axi_wstrb(wstrb),.s_axi_wvalid(wvalid),.s_axi_wready(wready),
 .s_axi_bresp(bresp),.s_axi_bvalid(bvalid),.s_axi_bready(bready),
 .s_axi_araddr(araddr),.s_axi_arvalid(arvalid),.s_axi_arready(arready),
 .s_axi_rdata(rdata),.s_axi_rresp(rresp),.s_axi_rvalid(rvalid),.s_axi_rready(rready),
 .s_axis_tdata(sid),.s_axis_tvalid(siv),.s_axis_tready(sir),.s_axis_tlast(sil),
 .m_axis_tdata(mod),.m_axis_tvalid(mov),.m_axis_tready(mor),.m_axis_tlast(mol),
 .bias_flat(bias));
always #5 clk=~clk;
always @(posedge clk) if(mov && !mor) held=held+1;

task axiw; input [5:0] a; input [31:0] d; begin
  @(negedge clk); awaddr=a; wdata=d; awvalid=1; wvalid=1;
  while(!(awready && wready)) @(negedge clk);
  @(negedge clk); awvalid=0; wvalid=0;
  while(!bvalid) @(negedge clk);
end endtask

task axir; input [5:0] a; output [31:0] d; begin
  @(negedge clk); araddr=a; arvalid=1;
  while(!arready) @(negedge clk);
  @(negedge clk); arvalid=0;
  while(!rvalid) @(negedge clk);
  d=rdata;
end endtask

task feed; input [31:0] d; input last; begin
  @(negedge clk); sid=d; sil=last; siv=1;
  while(!sir) @(negedge clk);
  @(negedge clk); siv=0; sil=0;
end endtask

integer sent=0,got=0,cycles=0,errors=0;
reg [127:0] stream[0:7];
reg signed [31:0] expected[0:63];
always @(posedge clk) if(aresetn) begin
 if(siv && sir) sent=sent+1;
 if(mov && mor) begin
  if(got>=64) errors=errors+1;
  else if($signed(mod)!==expected[got] || mol!==(got==63)) begin
   $display("MISMATCH idx=%0d got=%0d expected=%0d last=%b",got,$signed(mod),expected[got],mol);errors=errors+1;
  end
  got=got+1;
 end
end
always @(negedge clk) begin cycles=cycles+1;mor=(cycles%7!=0 && cycles%11!=0);end
initial begin
stream[0]=128'h00000000000000fd00000000000000ff;
stream[1]=128'h000000000000ff000000000000000100;
stream[2]=128'h00000000000300000000000000ff0000;
stream[3]=128'h00000000fe0000000000000002000000;
stream[4]=128'h00000000000000000000000000000000;
stream[5]=128'h0000fd00000000000000fe0000000000;
stream[6]=128'h00fd0000000000000002000000000000;
stream[7]=128'h0100000000000000ff00000000000000;
expected[0]=3;
expected[1]=1;
expected[2]=-3;
expected[3]=2;
expected[4]=0;
expected[5]=3;
expected[6]=3;
expected[7]=-1;
expected[8]=-3;
expected[9]=-1;
expected[10]=3;
expected[11]=-2;
expected[12]=0;
expected[13]=-3;
expected[14]=-3;
expected[15]=1;
expected[16]=3;
expected[17]=1;
expected[18]=-3;
expected[19]=2;
expected[20]=0;
expected[21]=3;
expected[22]=3;
expected[23]=-1;
expected[24]=-6;
expected[25]=-2;
expected[26]=6;
expected[27]=-4;
expected[28]=0;
expected[29]=-6;
expected[30]=-6;
expected[31]=2;
expected[32]=0;
expected[33]=0;
expected[34]=0;
expected[35]=0;
expected[36]=0;
expected[37]=0;
expected[38]=0;
expected[39]=0;
expected[40]=6;
expected[41]=2;
expected[42]=-6;
expected[43]=4;
expected[44]=0;
expected[45]=6;
expected[46]=6;
expected[47]=-2;
expected[48]=-6;
expected[49]=-2;
expected[50]=6;
expected[51]=-4;
expected[52]=0;
expected[53]=-6;
expected[54]=-6;
expected[55]=2;
expected[56]=3;
expected[57]=1;
expected[58]=-3;
expected[59]=2;
expected[60]=0;
expected[61]=3;
expected[62]=3;
expected[63]=-1;
#30;aresetn=1;
axiw(6'h04,8);axiw(6'h08,8);axiw(6'h0C,1);
axiw(6'h10,0);axiw(6'h18,1);axiw(6'h1C,0);axiw(6'h20,0);
axiw(6'h00,1);
@(negedge clk);siv=1;sid=stream[0];sil=0;
while(sent<8) begin
 @(negedge clk);
 if(sent<8) begin sid=stream[sent];sil=(sent==7);end
end
siv=0;sil=0;
repeat(400) @(negedge clk);
if(got!=64 || !dut.regs.done_sticky || errors!=0) $display("FAIL got=%0d errors=%0d done=%b",got,errors,dut.regs.done_sticky);
else $display("PASS shape=8,8,1 bias=False");
$finish;end
initial begin #500000;$display("FAIL TIMEOUT sent=%0d got=%0d",sent,got);$finish;end
endmodule
