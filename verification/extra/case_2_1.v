`timescale 1ns/1ps
module tb_case_2_1;
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
reg [127:0] stream[0:43];
reg signed [31:0] expected[0:80];
always @(posedge clk) if(aresetn) begin
 if(siv && sir) sent=sent+1;
 if(mov && mor) begin
  if(got>=81) errors=errors+1;
  else if($signed(mod)!==expected[got] || mol!==(got==80)) begin
   $display("MISMATCH idx=%0d got=%0d expected=%0d last=%b",got,$signed(mod),expected[got],mol);errors=errors+1;
  end
  got=got+1;
 end
end
always @(negedge clk) begin cycles=cycles+1;mor=(cycles%7!=0 && cycles%11!=0);end
initial begin
stream[0]=128'h00000000000000000000000900000001;
stream[1]=128'hffffffff00000002000000070000000a;
stream[2]=128'h00000000000000010000000000000000;
stream[3]=128'h0000000000000200000000000000fd01;
stream[4]=128'h000000000000fd00000000000002ff00;
stream[5]=128'h00000000020000000000000001fd0000;
stream[6]=128'h000000fe03000000000000fe00000000;
stream[7]=128'h00000103000000000000020300000000;
stream[8]=128'h00fd0300000000000002030000000000;
stream[9]=128'hfd0200000000000001ff000000000000;
stream[10]=128'h0100000000000000fe00000000000000;
stream[11]=128'h00000000000000000000000000000001;
stream[12]=128'h00000000000000000000000000000000;
stream[13]=128'h00000000000000ff0000000000000000;
stream[14]=128'h0000000000000003000000000000fd01;
stream[15]=128'h0000000000000000000000000002ff00;
stream[16]=128'h00000000000000000000000001fd0000;
stream[17]=128'h0000000000000000000000fe00000000;
stream[18]=128'h00000000000000000000020300000000;
stream[19]=128'h00000000000000000002030000000000;
stream[20]=128'h000000000000000001ff000000000000;
stream[21]=128'h0000000000000000fe00000000000000;
stream[22]=128'h00000000000000000000000900000001;
stream[23]=128'hffffffff00000002000000070000000a;
stream[24]=128'h000000000000000100000000000000fd;
stream[25]=128'h00000000000002000000000000000003;
stream[26]=128'h000000000000fd000000000000000000;
stream[27]=128'h00000000020000000000000000000000;
stream[28]=128'h000000fe030000000000000000000000;
stream[29]=128'h00000103000000000000000000000000;
stream[30]=128'h00fd0300000000000000000000000000;
stream[31]=128'hfd020000000000000000000000000000;
stream[32]=128'h01000000000000000000000000000000;
stream[33]=128'h00000000000000000000000000000001;
stream[34]=128'h00000000000000000000000000000000;
stream[35]=128'h00000000000000ff00000000000000fd;
stream[36]=128'h00000000000000030000000000000003;
stream[37]=128'h00000000000000000000000000000000;
stream[38]=128'h00000000000000000000000000000000;
stream[39]=128'h00000000000000000000000000000000;
stream[40]=128'h00000000000000000000000000000000;
stream[41]=128'h00000000000000000000000000000000;
stream[42]=128'h00000000000000000000000000000000;
stream[43]=128'h00000000000000000000000000000000;
expected[0]=1;
expected[1]=6;
expected[2]=0;
expected[3]=3;
expected[4]=13;
expected[5]=10;
expected[6]=4;
expected[7]=0;
expected[8]=-2;
expected[9]=6;
expected[10]=0;
expected[11]=-9;
expected[12]=13;
expected[13]=1;
expected[14]=9;
expected[15]=7;
expected[16]=3;
expected[17]=22;
expected[18]=0;
expected[19]=-5;
expected[20]=-3;
expected[21]=0;
expected[22]=-10;
expected[23]=-10;
expected[24]=2;
expected[25]=11;
expected[26]=0;
expected[27]=2;
expected[28]=8;
expected[29]=8;
expected[30]=-1;
expected[31]=-4;
expected[32]=-1;
expected[33]=-4;
expected[34]=0;
expected[35]=5;
expected[36]=23;
expected[37]=14;
expected[38]=14;
expected[39]=8;
expected[40]=3;
expected[41]=4;
expected[42]=0;
expected[43]=13;
expected[44]=15;
expected[45]=18;
expected[46]=2;
expected[47]=-4;
expected[48]=3;
expected[49]=16;
expected[50]=0;
expected[51]=1;
expected[52]=3;
expected[53]=6;
expected[54]=-6;
expected[55]=-8;
expected[56]=2;
expected[57]=17;
expected[58]=0;
expected[59]=-4;
expected[60]=2;
expected[61]=2;
expected[62]=-5;
expected[63]=-6;
expected[64]=4;
expected[65]=1;
expected[66]=-10;
expected[67]=0;
expected[68]=12;
expected[69]=8;
expected[70]=-4;
expected[71]=-6;
expected[72]=-2;
expected[73]=-6;
expected[74]=0;
expected[75]=3;
expected[76]=25;
expected[77]=13;
expected[78]=17;
expected[79]=11;
expected[80]=13;
#30;aresetn=1;
axiw(6'h04,9);axiw(6'h08,9);axiw(6'h0C,2);
axiw(6'h10,0);axiw(6'h18,1);axiw(6'h1C,0);axiw(6'h20,0);
axiw(6'h00,17);
@(negedge clk);siv=1;sid=stream[0];sil=0;
while(sent<44) begin
 @(negedge clk);
 if(sent<44) begin sid=stream[sent];sil=(sent==43);end
end
siv=0;sil=0;
repeat(400) @(negedge clk);
if(got!=81 || !dut.regs.done_sticky || errors!=0) $display("FAIL got=%0d errors=%0d done=%b",got,errors,dut.regs.done_sticky);
else $display("PASS shape=9,9,2 bias=True");
$finish;end
initial begin #500000;$display("FAIL TIMEOUT sent=%0d got=%0d",sent,got);$finish;end
endmodule
