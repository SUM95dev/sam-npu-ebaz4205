`timescale 1ns/1ps
module tb_case_7_1;
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
reg [127:0] stream[0:25];
reg signed [31:0] expected[0:127];
always @(posedge clk) if(aresetn) begin
 if(siv && sir) sent=sent+1;
 if(mov && mor) begin
  if(got>=128) errors=errors+1;
  else if($signed(mod)!==expected[got] || mol!==(got==127)) begin
   $display("MISMATCH idx=%0d got=%0d expected=%0d last=%b",got,$signed(mod),expected[got],mol);errors=errors+1;
  end
  got=got+1;
 end
end
always @(negedge clk) begin cycles=cycles+1;mor=(cycles%7!=0 && cycles%11!=0);end
initial begin
stream[0]=128'hfffffff6fffffff70000000800000005;
stream[1]=128'hfffffff6000000010000000a00000002;
stream[2]=128'h00000000000000fe00000000000000ff;
stream[3]=128'h00000000000003ff0000000000000202;
stream[4]=128'h000000000002fd03000000000003ffff;
stream[5]=128'h000000000202010300000000ff01ff00;
stream[6]=128'h0000000101000200000000fffe020100;
stream[7]=128'h00000201fdfd0000000000ff02030000;
stream[8]=128'h00ff02fd0300000000fe030301000000;
stream[9]=128'hfefeff03000000000000feff00000000;
stream[10]=128'hfdfe03000000000000fefd0000000000;
stream[11]=128'h00fd00000000000003fd000000000000;
stream[12]=128'hff00000000000000fe00000000000000;
stream[13]=128'h00000005fffffff9fffffffc0000000a;
stream[14]=128'h00000001000000040000000afffffffe;
stream[15]=128'h00000000000000fe00000000000000ff;
stream[16]=128'h000000000000fdff0000000000000202;
stream[17]=128'h0000000000feff03000000000003ffff;
stream[18]=128'h00000000feff010200000000ff01ff00;
stream[19]=128'h000000fe01020200000000fffe020100;
stream[20]=128'h0000010203fd0000000000ff02030000;
stream[21]=128'h00ff03ff0300000000fe030301000000;
stream[22]=128'h00fe0000000000000000feff00000000;
stream[23]=128'h0303fe000000000000fefd0000000000;
stream[24]=128'hff0000000000000003fd000000000000;
stream[25]=128'h0000000000000000fe00000000000000;
expected[0]=2;
expected[1]=-2;
expected[2]=-7;
expected[3]=-7;
expected[4]=6;
expected[5]=13;
expected[6]=0;
expected[7]=-14;
expected[8]=2;
expected[9]=18;
expected[10]=-10;
expected[11]=-1;
expected[12]=9;
expected[13]=16;
expected[14]=0;
expected[15]=-12;
expected[16]=13;
expected[17]=22;
expected[18]=-10;
expected[19]=0;
expected[20]=9;
expected[21]=25;
expected[22]=-17;
expected[23]=-22;
expected[24]=18;
expected[25]=15;
expected[26]=-18;
expected[27]=-17;
expected[28]=-4;
expected[29]=5;
expected[30]=-1;
expected[31]=-3;
expected[32]=14;
expected[33]=9;
expected[34]=-10;
expected[35]=-25;
expected[36]=-12;
expected[37]=0;
expected[38]=1;
expected[39]=-4;
expected[40]=-13;
expected[41]=-9;
expected[42]=6;
expected[43]=-10;
expected[44]=2;
expected[45]=9;
expected[46]=8;
expected[47]=-16;
expected[48]=-6;
expected[49]=-6;
expected[50]=-4;
expected[51]=-17;
expected[52]=-3;
expected[53]=-1;
expected[54]=16;
expected[55]=-3;
expected[56]=8;
expected[57]=7;
expected[58]=-3;
expected[59]=-25;
expected[60]=-13;
expected[61]=1;
expected[62]=1;
expected[63]=-8;
expected[64]=7;
expected[65]=-4;
expected[66]=-9;
expected[67]=6;
expected[68]=5;
expected[69]=15;
expected[70]=-2;
expected[71]=8;
expected[72]=6;
expected[73]=-8;
expected[74]=-15;
expected[75]=0;
expected[76]=-7;
expected[77]=7;
expected[78]=1;
expected[79]=-1;
expected[80]=15;
expected[81]=-6;
expected[82]=-19;
expected[83]=15;
expected[84]=-8;
expected[85]=10;
expected[86]=5;
expected[87]=2;
expected[88]=22;
expected[89]=5;
expected[90]=-2;
expected[91]=14;
expected[92]=-6;
expected[93]=1;
expected[94]=15;
expected[95]=-7;
expected[96]=20;
expected[97]=1;
expected[98]=5;
expected[99]=12;
expected[100]=-5;
expected[101]=8;
expected[102]=16;
expected[103]=-5;
expected[104]=-5;
expected[105]=-15;
expected[106]=-5;
expected[107]=-7;
expected[108]=6;
expected[109]=25;
expected[110]=-8;
expected[111]=12;
expected[112]=2;
expected[113]=-6;
expected[114]=2;
expected[115]=-6;
expected[116]=4;
expected[117]=14;
expected[118]=0;
expected[119]=3;
expected[120]=15;
expected[121]=-5;
expected[122]=5;
expected[123]=8;
expected[124]=-5;
expected[125]=14;
expected[126]=13;
expected[127]=-2;
#30;aresetn=1;
axiw(6'h04,8);axiw(6'h08,16);axiw(6'h0C,4);
axiw(6'h10,0);axiw(6'h18,1);axiw(6'h1C,0);axiw(6'h20,0);
axiw(6'h00,17);
@(negedge clk);siv=1;sid=stream[0];sil=0;
while(sent<26) begin
 @(negedge clk);
 if(sent<26) begin sid=stream[sent];sil=(sent==25);end
end
siv=0;sil=0;
repeat(400) @(negedge clk);
if(got!=128 || !dut.regs.done_sticky || errors!=0) $display("FAIL got=%0d errors=%0d done=%b",got,errors,dut.regs.done_sticky);
else $display("PASS shape=8,16,4 bias=True");
$finish;end
initial begin #500000;$display("FAIL TIMEOUT sent=%0d got=%0d",sent,got);$finish;end
endmodule
