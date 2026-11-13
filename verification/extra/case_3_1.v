`timescale 1ns/1ps
module tb_case_3_1;
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
reg [127:0] stream[0:41];
reg signed [31:0] expected[0:50];
always @(posedge clk) if(aresetn) begin
 if(siv && sir) sent=sent+1;
 if(mov && mor) begin
  if(got>=51) errors=errors+1;
  else if($signed(mod)!==expected[got] || mol!==(got==50)) begin
   $display("MISMATCH idx=%0d got=%0d expected=%0d last=%b",got,$signed(mod),expected[got],mol);errors=errors+1;
  end
  got=got+1;
 end
end
always @(negedge clk) begin cycles=cycles+1;mor=(cycles%7!=0 && cycles%11!=0);end
initial begin
stream[0]=128'hffffffff00000007fffffffc00000003;
stream[1]=128'h00000003000000020000000900000005;
stream[2]=128'h00000000000000030000000000000001;
stream[3]=128'h000000000000fe020000000000000203;
stream[4]=128'h0000000000fe01020000000000fe01fd;
stream[5]=128'h0000000002fffe020000000000ffff02;
stream[6]=128'h000000fefd00fd020000000000ff0002;
stream[7]=128'h000001fd00ff02000000000000fe0300;
stream[8]=128'h00fdfdfe020200000000000000ff0000;
stream[9]=128'hfe0203fd020000000000000000000000;
stream[10]=128'hfefe0001000000000000000000000000;
stream[11]=128'h00000100000000000000000000000000;
stream[12]=128'h01ff0000000000000000000000000000;
stream[13]=128'h00000000000000000000000000000000;
stream[14]=128'h00000001fffffffa00000001fffffff9;
stream[15]=128'hfffffffbfffffff80000000000000001;
stream[16]=128'h00000000000000fd0000000000000001;
stream[17]=128'h00000000000001fd0000000000000203;
stream[18]=128'h0000000000fefdff0000000000fe01fd;
stream[19]=128'h00000000010102fd0000000000ffff02;
stream[20]=128'h000000fefdfe02ff0000000000ff0002;
stream[21]=128'h00000301ff0101000000000000fe0300;
stream[22]=128'h0001fe01feff00000000000000ff0000;
stream[23]=128'h00020103020000000000000000000000;
stream[24]=128'hfeff0001000000000000000000000000;
stream[25]=128'h0100fe00000000000000000000000000;
stream[26]=128'hfd010000000000000000000000000000;
stream[27]=128'h02000000000000000000000000000000;
stream[28]=128'h000000000000000000000000fffffffc;
stream[29]=128'h00000000000000000000000000000000;
stream[30]=128'h00000000000000ff0000000000000001;
stream[31]=128'h00000000000000010000000000000203;
stream[32]=128'h00000000000000030000000000fe01fd;
stream[33]=128'h00000000000000020000000000ffff02;
stream[34]=128'h00000000000000fe0000000000ff0002;
stream[35]=128'h00000000000000000000000000fe0300;
stream[36]=128'h00000000000000000000000000ff0000;
stream[37]=128'h00000000000000000000000000000000;
stream[38]=128'h00000000000000000000000000000000;
stream[39]=128'h00000000000000000000000000000000;
stream[40]=128'h00000000000000000000000000000000;
stream[41]=128'h00000000000000000000000000000000;
expected[0]=14;
expected[1]=1;
expected[2]=4;
expected[3]=0;
expected[4]=-4;
expected[5]=-6;
expected[6]=9;
expected[7]=-3;
expected[8]=15;
expected[9]=1;
expected[10]=8;
expected[11]=6;
expected[12]=3;
expected[13]=8;
expected[14]=-3;
expected[15]=-3;
expected[16]=-13;
expected[17]=5;
expected[18]=12;
expected[19]=-8;
expected[20]=19;
expected[21]=6;
expected[22]=9;
expected[23]=7;
expected[24]=-24;
expected[25]=-7;
expected[26]=1;
expected[27]=-4;
expected[28]=7;
expected[29]=-10;
expected[30]=4;
expected[31]=-16;
expected[32]=-18;
expected[33]=1;
expected[34]=-10;
expected[35]=7;
expected[36]=0;
expected[37]=-3;
expected[38]=0;
expected[39]=-2;
expected[40]=10;
expected[41]=-5;
expected[42]=-2;
expected[43]=5;
expected[44]=-4;
expected[45]=-3;
expected[46]=-12;
expected[47]=0;
expected[48]=-11;
expected[49]=-14;
expected[50]=-8;
#30;aresetn=1;
axiw(6'h04,3);axiw(6'h08,17);axiw(6'h0C,5);
axiw(6'h10,0);axiw(6'h18,1);axiw(6'h1C,0);axiw(6'h20,0);
axiw(6'h00,17);
@(negedge clk);siv=1;sid=stream[0];sil=0;
while(sent<42) begin
 @(negedge clk);
 if(sent<42) begin sid=stream[sent];sil=(sent==41);end
end
siv=0;sil=0;
repeat(400) @(negedge clk);
if(got!=51 || !dut.regs.done_sticky || errors!=0) $display("FAIL got=%0d errors=%0d done=%b",got,errors,dut.regs.done_sticky);
else $display("PASS shape=3,17,5 bias=True");
$finish;end
initial begin #500000;$display("FAIL TIMEOUT sent=%0d got=%0d",sent,got);$finish;end
endmodule
