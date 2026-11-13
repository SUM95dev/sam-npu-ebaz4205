`timescale 1ns/1ps
module tb_case_4_0;
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
reg [127:0] stream[0:44];
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
stream[0]=128'h00000000000000010000000000000000;
stream[1]=128'h000000000000fffd0000000000000001;
stream[2]=128'h0000000000fe0103000000000000feff;
stream[3]=128'h0000000000fdff0100000000fefdfefe;
stream[4]=128'h000000000001ffff000000fffd020202;
stream[5]=128'h0000000000ff02020000030103fffffe;
stream[6]=128'h000000000002fe0000fd00ffff00fdff;
stream[7]=128'h0000000000fe0103fefefe01fd030000;
stream[8]=128'h0000000000fefe0002fdfe020202fd00;
stream[9]=128'h0000000000fd000000fffe01ff030000;
stream[10]=128'h00000000000000000301fe0003000000;
stream[11]=128'h0000000000000000fd01fe0300000000;
stream[12]=128'h00000000000000000100fd0000000000;
stream[13]=128'h000000000000000003fd000000000000;
stream[14]=128'h0000000000000000ff00000000000000;
stream[15]=128'h00000000000000010000000000000003;
stream[16]=128'h000000000000fffd000000000000fd02;
stream[17]=128'h0000000000fe0103000000000000fdfd;
stream[18]=128'h0000000000fdff010000000002fe02ff;
stream[19]=128'h000000000001ffff0000000200030202;
stream[20]=128'h0000000000ff0202000003fefe01fd00;
stream[21]=128'h000000000002fe000001fdfdfd010100;
stream[22]=128'h0000000000fe0103fd03fe0201fdfefe;
stream[23]=128'h0000000000fefe00fefeff00ff010000;
stream[24]=128'h0000000000fd000002020001fe000000;
stream[25]=128'h00000000000000000001fd03fd000000;
stream[26]=128'h000000000000000000fe03fe00000000;
stream[27]=128'h0000000000000000fdfefd0000000000;
stream[28]=128'h0000000000000000fdfe000000000000;
stream[29]=128'h00000000000000000100000000000000;
stream[30]=128'h00000000000000010000000000000003;
stream[31]=128'h000000000000fffd00000000000000ff;
stream[32]=128'h0000000000fe01030000000000000003;
stream[33]=128'h0000000000fdff0100000000000000ff;
stream[34]=128'h000000000001ffff0000000000000003;
stream[35]=128'h0000000000ff02020000000000000003;
stream[36]=128'h000000000002fe000000000000000002;
stream[37]=128'h0000000000fe01030000000000000001;
stream[38]=128'h0000000000fefe000000000000000000;
stream[39]=128'h0000000000fd00000000000000000000;
stream[40]=128'h00000000000000000000000000000000;
stream[41]=128'h00000000000000000000000000000000;
stream[42]=128'h00000000000000000000000000000000;
stream[43]=128'h00000000000000000000000000000000;
stream[44]=128'h00000000000000000000000000000000;
expected[0]=-14;
expected[1]=11;
expected[2]=8;
expected[3]=-12;
expected[4]=8;
expected[5]=15;
expected[6]=29;
expected[7]=-14;
expected[8]=-7;
expected[9]=31;
expected[10]=-20;
expected[11]=0;
expected[12]=3;
expected[13]=-2;
expected[14]=-10;
expected[15]=-16;
expected[16]=5;
expected[17]=7;
expected[18]=-15;
expected[19]=11;
expected[20]=19;
expected[21]=-3;
expected[22]=-2;
expected[23]=-16;
expected[24]=-21;
expected[25]=11;
expected[26]=-4;
expected[27]=19;
expected[28]=-14;
expected[29]=11;
expected[30]=9;
expected[31]=3;
expected[32]=14;
expected[33]=-19;
expected[34]=11;
expected[35]=14;
expected[36]=-3;
expected[37]=2;
expected[38]=-5;
expected[39]=-10;
expected[40]=12;
expected[41]=11;
expected[42]=-23;
expected[43]=10;
expected[44]=1;
expected[45]=6;
expected[46]=0;
expected[47]=23;
expected[48]=20;
expected[49]=-6;
expected[50]=-6;
#30;aresetn=1;
axiw(6'h04,17);axiw(6'h08,3);axiw(6'h0C,8);
axiw(6'h10,0);axiw(6'h18,1);axiw(6'h1C,0);axiw(6'h20,0);
axiw(6'h00,1);
@(negedge clk);siv=1;sid=stream[0];sil=0;
while(sent<45) begin
 @(negedge clk);
 if(sent<45) begin sid=stream[sent];sil=(sent==44);end
end
siv=0;sil=0;
repeat(400) @(negedge clk);
if(got!=51 || !dut.regs.done_sticky || errors!=0) $display("FAIL got=%0d errors=%0d done=%b",got,errors,dut.regs.done_sticky);
else $display("PASS shape=17,3,8 bias=False");
$finish;end
initial begin #500000;$display("FAIL TIMEOUT sent=%0d got=%0d",sent,got);$finish;end
endmodule
