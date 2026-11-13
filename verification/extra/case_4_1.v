`timescale 1ns/1ps
module tb_case_4_1;
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
reg [127:0] stream[0:50];
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
stream[0]=128'h00000000fffffffcfffffffefffffffe;
stream[1]=128'h00000000000000000000000000000000;
stream[2]=128'h00000000000000020000000000000001;
stream[3]=128'h0000000000000303000000000000fefd;
stream[4]=128'h000000000000fdff0000000000010302;
stream[5]=128'h00000000000202010000000003ff0100;
stream[6]=128'h0000000000fd01030000000202ff0200;
stream[7]=128'h000000000002000000000201ff020301;
stream[8]=128'h00000000000200fe00fe01fffdfe0300;
stream[9]=128'h000000000002fffefd00fffe02030103;
stream[10]=128'h0000000000ff0000ff01fe0100030100;
stream[11]=128'h0000000000010000fd02ff0101030000;
stream[12]=128'h0000000000000000000203fdfd000000;
stream[13]=128'h00000000000000000101fe0100000000;
stream[14]=128'h0000000000000000fefdff0000000000;
stream[15]=128'h00000000000000000101000000000000;
stream[16]=128'h0000000000000000fe00000000000000;
stream[17]=128'h00000000fffffffcfffffffefffffffe;
stream[18]=128'h00000000000000000000000000000000;
stream[19]=128'h000000000000000200000000000000fd;
stream[20]=128'h000000000000030300000000000001fe;
stream[21]=128'h000000000000fdff0000000000fffdfd;
stream[22]=128'h0000000000020201000000000302fefe;
stream[23]=128'h0000000000fd0103000000030101ff00;
stream[24]=128'h0000000000020000000001fefe010002;
stream[25]=128'h00000000000200fe0000fffd010103ff;
stream[26]=128'h000000000002fffe0101fd020003fdfe;
stream[27]=128'h0000000000ff0000fe0103fd01010300;
stream[28]=128'h000000000001000003fe030303010000;
stream[29]=128'h0000000000000000fefdff0301000000;
stream[30]=128'h0000000000000000fd00010300000000;
stream[31]=128'h0000000000000000fd02020000000000;
stream[32]=128'h00000000000000000202000000000000;
stream[33]=128'h00000000000000000100000000000000;
stream[34]=128'h00000000fffffffcfffffffefffffffe;
stream[35]=128'h00000000000000000000000000000000;
stream[36]=128'h000000000000000200000000000000fd;
stream[37]=128'h00000000000003030000000000000001;
stream[38]=128'h000000000000fdff0000000000000001;
stream[39]=128'h000000000002020100000000000000fd;
stream[40]=128'h0000000000fd01030000000000000003;
stream[41]=128'h000000000002000000000000000000fe;
stream[42]=128'h00000000000200fe00000000000000ff;
stream[43]=128'h000000000002fffe0000000000000001;
stream[44]=128'h0000000000ff00000000000000000000;
stream[45]=128'h00000000000100000000000000000000;
stream[46]=128'h00000000000000000000000000000000;
stream[47]=128'h00000000000000000000000000000000;
stream[48]=128'h00000000000000000000000000000000;
stream[49]=128'h00000000000000000000000000000000;
stream[50]=128'h00000000000000000000000000000000;
expected[0]=-17;
expected[1]=14;
expected[2]=-11;
expected[3]=9;
expected[4]=-14;
expected[5]=15;
expected[6]=-18;
expected[7]=1;
expected[8]=3;
expected[9]=18;
expected[10]=-5;
expected[11]=-3;
expected[12]=11;
expected[13]=0;
expected[14]=5;
expected[15]=7;
expected[16]=-1;
expected[17]=2;
expected[18]=5;
expected[19]=-1;
expected[20]=7;
expected[21]=-3;
expected[22]=-15;
expected[23]=-2;
expected[24]=-7;
expected[25]=-12;
expected[26]=0;
expected[27]=-8;
expected[28]=8;
expected[29]=6;
expected[30]=1;
expected[31]=-9;
expected[32]=7;
expected[33]=2;
expected[34]=-2;
expected[35]=6;
expected[36]=-18;
expected[37]=6;
expected[38]=5;
expected[39]=6;
expected[40]=0;
expected[41]=14;
expected[42]=-19;
expected[43]=-7;
expected[44]=-15;
expected[45]=-26;
expected[46]=9;
expected[47]=-34;
expected[48]=0;
expected[49]=-14;
expected[50]=-7;
#30;aresetn=1;
axiw(6'h04,17);axiw(6'h08,3);axiw(6'h0C,8);
axiw(6'h10,0);axiw(6'h18,1);axiw(6'h1C,0);axiw(6'h20,0);
axiw(6'h00,17);
@(negedge clk);siv=1;sid=stream[0];sil=0;
while(sent<51) begin
 @(negedge clk);
 if(sent<51) begin sid=stream[sent];sil=(sent==50);end
end
siv=0;sil=0;
repeat(400) @(negedge clk);
if(got!=51 || !dut.regs.done_sticky || errors!=0) $display("FAIL got=%0d errors=%0d done=%b",got,errors,dut.regs.done_sticky);
else $display("PASS shape=17,3,8 bias=True");
$finish;end
initial begin #500000;$display("FAIL TIMEOUT sent=%0d got=%0d",sent,got);$finish;end
endmodule
