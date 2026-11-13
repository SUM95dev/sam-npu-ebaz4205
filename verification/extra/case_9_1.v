`timescale 1ns/1ps
module tb_case_9_1;
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
reg [127:0] stream[0:71];
reg signed [31:0] expected[0:152];
always @(posedge clk) if(aresetn) begin
 if(siv && sir) sent=sent+1;
 if(mov && mor) begin
  if(got>=153) errors=errors+1;
  else if($signed(mod)!==expected[got] || mol!==(got==152)) begin
   $display("MISMATCH idx=%0d got=%0d expected=%0d last=%b",got,$signed(mod),expected[got],mol);errors=errors+1;
  end
  got=got+1;
 end
end
always @(negedge clk) begin cycles=cycles+1;mor=(cycles%7!=0 && cycles%11!=0);end
initial begin
stream[0]=128'h0000000700000005ffffffff00000004;
stream[1]=128'h000000050000000900000004fffffff8;
stream[2]=128'h00000000000000030000000000000003;
stream[3]=128'h000000000000fe01000000000000fe03;
stream[4]=128'h000000000000fdfd0000000000ff0002;
stream[5]=128'h0000000003fefd0000000000ff000200;
stream[6]=128'h00000000fd02000000000000fd020000;
stream[7]=128'h0000fd00ff000000000000fffe000000;
stream[8]=128'h00020202000000000000ff0300000000;
stream[9]=128'hfdfffe000000000002fe030000000000;
stream[10]=128'h01030000000000000200000000000000;
stream[11]=128'hfd00000000000000ff00000000000000;
stream[12]=128'h0000000a0000000700000004fffffffd;
stream[13]=128'hfffffffd0000000afffffffcffffffff;
stream[14]=128'h00000000000000000000000000000003;
stream[15]=128'h0000000000000101000000000000fe03;
stream[16]=128'h00000000000203fe0000000000ff0002;
stream[17]=128'h00000000fd03010000000000ff000200;
stream[18]=128'h0000000202ff000000000000fd020000;
stream[19]=128'h000000fe03000000000000fffe000000;
stream[20]=128'h00fd00fd000000000000ff0300000000;
stream[21]=128'hfefe03000000000002fe030000000000;
stream[22]=128'hfffe0000000000000200000000000000;
stream[23]=128'h0300000000000000ff00000000000000;
stream[24]=128'h000000000000000000000000fffffffc;
stream[25]=128'h00000000000000000000000000000000;
stream[26]=128'h00000000000000000000000000000003;
stream[27]=128'h0000000000000003000000000000fe03;
stream[28]=128'h00000000000000020000000000ff0002;
stream[29]=128'h000000000000000000000000ff000200;
stream[30]=128'h000000000000000000000000fd020000;
stream[31]=128'h0000000000000000000000fffe000000;
stream[32]=128'h00000000000000000000ff0300000000;
stream[33]=128'h000000000000000002fe030000000000;
stream[34]=128'h00000000000000000200000000000000;
stream[35]=128'h0000000000000000ff00000000000000;
stream[36]=128'h0000000700000005ffffffff00000004;
stream[37]=128'h000000050000000900000004fffffff8;
stream[38]=128'h00000000000000030000000000000003;
stream[39]=128'h000000000000fe0100000000000000fe;
stream[40]=128'h000000000000fdfd0000000000000003;
stream[41]=128'h0000000003fefd000000000000000000;
stream[42]=128'h00000000fd0200000000000000000000;
stream[43]=128'h0000fd00ff0000000000000000000000;
stream[44]=128'h00020202000000000000000000000000;
stream[45]=128'hfdfffe00000000000000000000000000;
stream[46]=128'h01030000000000000000000000000000;
stream[47]=128'hfd000000000000000000000000000000;
stream[48]=128'h0000000a0000000700000004fffffffd;
stream[49]=128'hfffffffd0000000afffffffcffffffff;
stream[50]=128'h00000000000000000000000000000003;
stream[51]=128'h000000000000010100000000000000fe;
stream[52]=128'h00000000000203fe0000000000000003;
stream[53]=128'h00000000fd0301000000000000000000;
stream[54]=128'h0000000202ff00000000000000000000;
stream[55]=128'h000000fe030000000000000000000000;
stream[56]=128'h00fd00fd000000000000000000000000;
stream[57]=128'hfefe0300000000000000000000000000;
stream[58]=128'hfffe0000000000000000000000000000;
stream[59]=128'h03000000000000000000000000000000;
stream[60]=128'h000000000000000000000000fffffffc;
stream[61]=128'h00000000000000000000000000000000;
stream[62]=128'h00000000000000000000000000000003;
stream[63]=128'h000000000000000300000000000000fe;
stream[64]=128'h00000000000000020000000000000003;
stream[65]=128'h00000000000000000000000000000000;
stream[66]=128'h00000000000000000000000000000000;
stream[67]=128'h00000000000000000000000000000000;
stream[68]=128'h00000000000000000000000000000000;
stream[69]=128'h00000000000000000000000000000000;
stream[70]=128'h00000000000000000000000000000000;
stream[71]=128'h00000000000000000000000000000000;
expected[0]=10;
expected[1]=-22;
expected[2]=3;
expected[3]=5;
expected[4]=-4;
expected[5]=-3;
expected[6]=18;
expected[7]=-7;
expected[8]=-8;
expected[9]=-3;
expected[10]=9;
expected[11]=-1;
expected[12]=-4;
expected[13]=6;
expected[14]=11;
expected[15]=5;
expected[16]=-5;
expected[17]=-5;
expected[18]=9;
expected[19]=2;
expected[20]=-4;
expected[21]=3;
expected[22]=13;
expected[23]=2;
expected[24]=4;
expected[25]=16;
expected[26]=7;
expected[27]=15;
expected[28]=-12;
expected[29]=5;
expected[30]=4;
expected[31]=11;
expected[32]=-6;
expected[33]=-7;
expected[34]=13;
expected[35]=7;
expected[36]=-2;
expected[37]=-4;
expected[38]=19;
expected[39]=-5;
expected[40]=-6;
expected[41]=-7;
expected[42]=13;
expected[43]=7;
expected[44]=-2;
expected[45]=-4;
expected[46]=19;
expected[47]=-5;
expected[48]=2;
expected[49]=5;
expected[50]=9;
expected[51]=13;
expected[52]=-8;
expected[53]=0;
expected[54]=11;
expected[55]=3;
expected[56]=15;
expected[57]=-8;
expected[58]=-1;
expected[59]=8;
expected[60]=-10;
expected[61]=4;
expected[62]=8;
expected[63]=4;
expected[64]=-4;
expected[65]=18;
expected[66]=20;
expected[67]=13;
expected[68]=-7;
expected[69]=2;
expected[70]=-9;
expected[71]=-6;
expected[72]=-7;
expected[73]=4;
expected[74]=1;
expected[75]=22;
expected[76]=-11;
expected[77]=2;
expected[78]=12;
expected[79]=7;
expected[80]=-7;
expected[81]=5;
expected[82]=3;
expected[83]=19;
expected[84]=-9;
expected[85]=2;
expected[86]=9;
expected[87]=5;
expected[88]=-2;
expected[89]=-8;
expected[90]=-2;
expected[91]=1;
expected[92]=9;
expected[93]=-10;
expected[94]=23;
expected[95]=-4;
expected[96]=-10;
expected[97]=4;
expected[98]=1;
expected[99]=17;
expected[100]=-8;
expected[101]=5;
expected[102]=6;
expected[103]=7;
expected[104]=-10;
expected[105]=4;
expected[106]=1;
expected[107]=17;
expected[108]=-8;
expected[109]=5;
expected[110]=6;
expected[111]=7;
expected[112]=-5;
expected[113]=-2;
expected[114]=1;
expected[115]=6;
expected[116]=3;
expected[117]=-4;
expected[118]=14;
expected[119]=-1;
expected[120]=1;
expected[121]=11;
expected[122]=18;
expected[123]=5;
expected[124]=2;
expected[125]=-7;
expected[126]=2;
expected[127]=-12;
expected[128]=9;
expected[129]=0;
expected[130]=0;
expected[131]=-17;
expected[132]=-1;
expected[133]=-1;
expected[134]=-10;
expected[135]=0;
expected[136]=2;
expected[137]=-10;
expected[138]=15;
expected[139]=19;
expected[140]=-2;
expected[141]=-15;
expected[142]=26;
expected[143]=-15;
expected[144]=-11;
expected[145]=4;
expected[146]=4;
expected[147]=6;
expected[148]=0;
expected[149]=5;
expected[150]=-1;
expected[151]=2;
expected[152]=-4;
#30;aresetn=1;
axiw(6'h04,9);axiw(6'h08,17);axiw(6'h0C,3);
axiw(6'h10,0);axiw(6'h18,1);axiw(6'h1C,0);axiw(6'h20,0);
axiw(6'h00,17);
@(negedge clk);siv=1;sid=stream[0];sil=0;
while(sent<72) begin
 @(negedge clk);
 if(sent<72) begin sid=stream[sent];sil=(sent==71);end
end
siv=0;sil=0;
repeat(400) @(negedge clk);
if(got!=153 || !dut.regs.done_sticky || errors!=0) $display("FAIL got=%0d errors=%0d done=%b",got,errors,dut.regs.done_sticky);
else $display("PASS shape=9,17,3 bias=True");
$finish;end
initial begin #500000;$display("FAIL TIMEOUT sent=%0d got=%0d",sent,got);$finish;end
endmodule
