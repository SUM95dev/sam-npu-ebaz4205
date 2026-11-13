`timescale 1ns/1ps
module tb_case_7_0;
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
reg [127:0] stream[0:21];
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
stream[0]=128'h000000000000000200000000000000ff;
stream[1]=128'h00000000000002000000000000000201;
stream[2]=128'h0000000000fdfdff0000000000fdfefd;
stream[3]=128'h0000000002fefd0300000000000102fe;
stream[4]=128'h00000002fd00030000000001fd030100;
stream[5]=128'h00000300ffff0000000000fffdfd0000;
stream[6]=128'h00ff0102ff0000000000ff01ff000000;
stream[7]=128'hfffffffd0000000003fe000100000000;
stream[8]=128'hfe01fe0000000000fd01020000000000;
stream[9]=128'hfe03000000000000fdff000000000000;
stream[10]=128'hfd000000000000000000000000000000;
stream[11]=128'h000000000000000200000000000000ff;
stream[12]=128'h00000000000001fe0000000000000201;
stream[13]=128'h000000000003ff030000000000fdfefd;
stream[14]=128'h000000000101fdfd00000000000102fe;
stream[15]=128'h0000000001fffe0000000001fd030100;
stream[16]=128'h0000fe0100010000000000fffdfd0000;
stream[17]=128'h00000302000000000000ff01ff000000;
stream[18]=128'hfdfe00000000000003fe000100000000;
stream[19]=128'h01fffd0000000000fd01020000000000;
stream[20]=128'hfdfe000000000000fdff000000000000;
stream[21]=128'hff000000000000000000000000000000;
expected[0]=-5;
expected[1]=-2;
expected[2]=3;
expected[3]=0;
expected[4]=-2;
expected[5]=5;
expected[6]=-9;
expected[7]=11;
expected[8]=5;
expected[9]=7;
expected[10]=-3;
expected[11]=7;
expected[12]=5;
expected[13]=0;
expected[14]=5;
expected[15]=-5;
expected[16]=-18;
expected[17]=-27;
expected[18]=10;
expected[19]=-9;
expected[20]=9;
expected[21]=-5;
expected[22]=-4;
expected[23]=4;
expected[24]=0;
expected[25]=15;
expected[26]=7;
expected[27]=13;
expected[28]=-3;
expected[29]=2;
expected[30]=-3;
expected[31]=15;
expected[32]=4;
expected[33]=5;
expected[34]=-2;
expected[35]=3;
expected[36]=1;
expected[37]=-1;
expected[38]=4;
expected[39]=-4;
expected[40]=6;
expected[41]=9;
expected[42]=0;
expected[43]=1;
expected[44]=-6;
expected[45]=-5;
expected[46]=7;
expected[47]=-4;
expected[48]=-4;
expected[49]=0;
expected[50]=5;
expected[51]=6;
expected[52]=5;
expected[53]=-1;
expected[54]=0;
expected[55]=5;
expected[56]=9;
expected[57]=24;
expected[58]=-3;
expected[59]=18;
expected[60]=0;
expected[61]=9;
expected[62]=-3;
expected[63]=9;
expected[64]=-7;
expected[65]=11;
expected[66]=-1;
expected[67]=0;
expected[68]=-5;
expected[69]=11;
expected[70]=5;
expected[71]=15;
expected[72]=11;
expected[73]=-4;
expected[74]=3;
expected[75]=0;
expected[76]=2;
expected[77]=-13;
expected[78]=0;
expected[79]=-15;
expected[80]=10;
expected[81]=-7;
expected[82]=-14;
expected[83]=-2;
expected[84]=7;
expected[85]=18;
expected[86]=1;
expected[87]=4;
expected[88]=0;
expected[89]=14;
expected[90]=-1;
expected[91]=-3;
expected[92]=-9;
expected[93]=-6;
expected[94]=11;
expected[95]=7;
expected[96]=4;
expected[97]=-3;
expected[98]=2;
expected[99]=0;
expected[100]=1;
expected[101]=-8;
expected[102]=-1;
expected[103]=-8;
expected[104]=-4;
expected[105]=-3;
expected[106]=1;
expected[107]=-1;
expected[108]=-1;
expected[109]=-9;
expected[110]=-2;
expected[111]=-3;
expected[112]=10;
expected[113]=1;
expected[114]=-4;
expected[115]=-2;
expected[116]=0;
expected[117]=-3;
expected[118]=5;
expected[119]=-4;
expected[120]=3;
expected[121]=15;
expected[122]=9;
expected[123]=0;
expected[124]=-9;
expected[125]=-15;
expected[126]=9;
expected[127]=-3;
#30;aresetn=1;
axiw(6'h04,8);axiw(6'h08,16);axiw(6'h0C,4);
axiw(6'h10,0);axiw(6'h18,1);axiw(6'h1C,0);axiw(6'h20,0);
axiw(6'h00,1);
@(negedge clk);siv=1;sid=stream[0];sil=0;
while(sent<22) begin
 @(negedge clk);
 if(sent<22) begin sid=stream[sent];sil=(sent==21);end
end
siv=0;sil=0;
repeat(400) @(negedge clk);
if(got!=128 || !dut.regs.done_sticky || errors!=0) $display("FAIL got=%0d errors=%0d done=%b",got,errors,dut.regs.done_sticky);
else $display("PASS shape=8,16,4 bias=False");
$finish;end
initial begin #500000;$display("FAIL TIMEOUT sent=%0d got=%0d",sent,got);$finish;end
endmodule
