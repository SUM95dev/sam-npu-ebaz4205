`timescale 1ns/1ps
module tb_case_9_0;
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
reg [127:0] stream[0:59];
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
stream[0]=128'h00000000000000000000000000000003;
stream[1]=128'h000000000000fdfd000000000000fefe;
stream[2]=128'h0000000000ff01000000000000ff0300;
stream[3]=128'h00000000fd01030000000000ff030300;
stream[4]=128'h00000000fd0100000000000103ff0000;
stream[5]=128'h000003fffe00000000000003fe000000;
stream[6]=128'h000103fe00000000000102fe00000000;
stream[7]=128'h02ff0000000000000303030000000000;
stream[8]=128'h00fe00000000000000ff000000000000;
stream[9]=128'h01000000000000000300000000000000;
stream[10]=128'h00000000000000ff0000000000000003;
stream[11]=128'h00000000000003fe000000000000fefe;
stream[12]=128'h0000000000ff00010000000000ff0300;
stream[13]=128'h0000000002feff0000000000ff030300;
stream[14]=128'h00000001ff0100000000000103ff0000;
stream[15]=128'h00000102fd00000000000003fe000000;
stream[16]=128'h00ff000300000000000102fe00000000;
stream[17]=128'h03000200000000000303030000000000;
stream[18]=128'hff0300000000000000ff000000000000;
stream[19]=128'h02000000000000000300000000000000;
stream[20]=128'h00000000000000010000000000000003;
stream[21]=128'h0000000000000002000000000000fefe;
stream[22]=128'h00000000000000020000000000ff0300;
stream[23]=128'h000000000000000000000000ff030300;
stream[24]=128'h00000000000000000000000103ff0000;
stream[25]=128'h000000000000000000000003fe000000;
stream[26]=128'h0000000000000000000102fe00000000;
stream[27]=128'h00000000000000000303030000000000;
stream[28]=128'h000000000000000000ff000000000000;
stream[29]=128'h00000000000000000300000000000000;
stream[30]=128'h000000000000000000000000000000fe;
stream[31]=128'h000000000000fdfd0000000000000003;
stream[32]=128'h0000000000ff010000000000000000ff;
stream[33]=128'h00000000fd0103000000000000000000;
stream[34]=128'h00000000fd0100000000000000000000;
stream[35]=128'h000003fffe0000000000000000000000;
stream[36]=128'h000103fe000000000000000000000000;
stream[37]=128'h02ff0000000000000000000000000000;
stream[38]=128'h00fe0000000000000000000000000000;
stream[39]=128'h01000000000000000000000000000000;
stream[40]=128'h00000000000000ff00000000000000fe;
stream[41]=128'h00000000000003fe0000000000000003;
stream[42]=128'h0000000000ff000100000000000000ff;
stream[43]=128'h0000000002feff000000000000000000;
stream[44]=128'h00000001ff0100000000000000000000;
stream[45]=128'h00000102fd0000000000000000000000;
stream[46]=128'h00ff0003000000000000000000000000;
stream[47]=128'h03000200000000000000000000000000;
stream[48]=128'hff030000000000000000000000000000;
stream[49]=128'h02000000000000000000000000000000;
stream[50]=128'h000000000000000100000000000000fe;
stream[51]=128'h00000000000000020000000000000003;
stream[52]=128'h000000000000000200000000000000ff;
stream[53]=128'h00000000000000000000000000000000;
stream[54]=128'h00000000000000000000000000000000;
stream[55]=128'h00000000000000000000000000000000;
stream[56]=128'h00000000000000000000000000000000;
stream[57]=128'h00000000000000000000000000000000;
stream[58]=128'h00000000000000000000000000000000;
stream[59]=128'h00000000000000000000000000000000;
expected[0]=6;
expected[1]=-11;
expected[2]=-5;
expected[3]=-3;
expected[4]=2;
expected[5]=3;
expected[6]=5;
expected[7]=6;
expected[8]=-9;
expected[9]=18;
expected[10]=8;
expected[11]=-9;
expected[12]=-9;
expected[13]=3;
expected[14]=-11;
expected[15]=-1;
expected[16]=-9;
expected[17]=3;
expected[18]=3;
expected[19]=-4;
expected[20]=-1;
expected[21]=6;
expected[22]=-2;
expected[23]=-3;
expected[24]=-9;
expected[25]=0;
expected[26]=2;
expected[27]=-2;
expected[28]=1;
expected[29]=6;
expected[30]=0;
expected[31]=-4;
expected[32]=-9;
expected[33]=-6;
expected[34]=0;
expected[35]=-8;
expected[36]=1;
expected[37]=12;
expected[38]=2;
expected[39]=0;
expected[40]=-6;
expected[41]=11;
expected[42]=5;
expected[43]=-12;
expected[44]=-8;
expected[45]=6;
expected[46]=-8;
expected[47]=3;
expected[48]=-9;
expected[49]=-3;
expected[50]=1;
expected[51]=-10;
expected[52]=-1;
expected[53]=12;
expected[54]=0;
expected[55]=1;
expected[56]=0;
expected[57]=0;
expected[58]=0;
expected[59]=-15;
expected[60]=-6;
expected[61]=9;
expected[62]=-3;
expected[63]=9;
expected[64]=1;
expected[65]=9;
expected[66]=1;
expected[67]=8;
expected[68]=-1;
expected[69]=3;
expected[70]=-3;
expected[71]=11;
expected[72]=-1;
expected[73]=-9;
expected[74]=-1;
expected[75]=-16;
expected[76]=13;
expected[77]=4;
expected[78]=11;
expected[79]=-3;
expected[80]=-6;
expected[81]=-2;
expected[82]=-6;
expected[83]=-2;
expected[84]=2;
expected[85]=-3;
expected[86]=-2;
expected[87]=-8;
expected[88]=-7;
expected[89]=-1;
expected[90]=-7;
expected[91]=1;
expected[92]=-1;
expected[93]=-5;
expected[94]=-5;
expected[95]=-10;
expected[96]=-9;
expected[97]=5;
expected[98]=-9;
expected[99]=5;
expected[100]=1;
expected[101]=-3;
expected[102]=-7;
expected[103]=-4;
expected[104]=-1;
expected[105]=-3;
expected[106]=-1;
expected[107]=-11;
expected[108]=13;
expected[109]=6;
expected[110]=9;
expected[111]=4;
expected[112]=-8;
expected[113]=4;
expected[114]=-8;
expected[115]=2;
expected[116]=4;
expected[117]=-1;
expected[118]=-4;
expected[119]=-2;
expected[120]=0;
expected[121]=6;
expected[122]=0;
expected[123]=-3;
expected[124]=12;
expected[125]=9;
expected[126]=6;
expected[127]=15;
expected[128]=-1;
expected[129]=10;
expected[130]=3;
expected[131]=1;
expected[132]=3;
expected[133]=10;
expected[134]=5;
expected[135]=9;
expected[136]=-9;
expected[137]=6;
expected[138]=4;
expected[139]=-1;
expected[140]=-1;
expected[141]=3;
expected[142]=-3;
expected[143]=-5;
expected[144]=-5;
expected[145]=-5;
expected[146]=-5;
expected[147]=-4;
expected[148]=1;
expected[149]=-4;
expected[150]=-1;
expected[151]=-11;
expected[152]=2;
#30;aresetn=1;
axiw(6'h04,9);axiw(6'h08,17);axiw(6'h0C,3);
axiw(6'h10,0);axiw(6'h18,1);axiw(6'h1C,0);axiw(6'h20,0);
axiw(6'h00,1);
@(negedge clk);siv=1;sid=stream[0];sil=0;
while(sent<60) begin
 @(negedge clk);
 if(sent<60) begin sid=stream[sent];sil=(sent==59);end
end
siv=0;sil=0;
repeat(400) @(negedge clk);
if(got!=153 || !dut.regs.done_sticky || errors!=0) $display("FAIL got=%0d errors=%0d done=%b",got,errors,dut.regs.done_sticky);
else $display("PASS shape=9,17,3 bias=False");
$finish;end
initial begin #500000;$display("FAIL TIMEOUT sent=%0d got=%0d",sent,got);$finish;end
endmodule
