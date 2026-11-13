`timescale 1ns/1ps
module tb_case_0_1;
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
reg [127:0] stream[0:19];
reg signed [31:0] expected[0:8];
always @(posedge clk) if(aresetn) begin
 if(siv && sir) sent=sent+1;
 if(mov && mor) begin
  if(got>=9) errors=errors+1;
  else if($signed(mod)!==expected[got] || mol!==(got==8)) begin
   $display("MISMATCH idx=%0d got=%0d expected=%0d last=%b",got,$signed(mod),expected[got],mol);errors=errors+1;
  end
  got=got+1;
 end
end
always @(negedge clk) begin cycles=cycles+1;mor=(cycles%7!=0 && cycles%11!=0);end
initial begin
stream[0]=128'hfffffffcfffffffffffffffdfffffffc;
stream[1]=128'hfffffffefffffff700000005fffffffd;
stream[2]=128'h00000000000000fe00000000000000fe;
stream[3]=128'h00000000000001000000000000000000;
stream[4]=128'h0000000000ff00000000000000000000;
stream[5]=128'h00000000030000000000000000000000;
stream[6]=128'h000000ff000000000000000000000000;
stream[7]=128'h00000200000000000000000000000000;
stream[8]=128'h00020000000000000000000000000000;
stream[9]=128'hff000000000000000000000000000000;
stream[10]=128'h00000000000000000000000000000005;
stream[11]=128'h00000000000000000000000000000000;
stream[12]=128'h000000000000000000000000000000fe;
stream[13]=128'h00000000000000000000000000000000;
stream[14]=128'h00000000000000000000000000000000;
stream[15]=128'h00000000000000000000000000000000;
stream[16]=128'h00000000000000000000000000000000;
stream[17]=128'h00000000000000000000000000000000;
stream[18]=128'h00000000000000000000000000000000;
stream[19]=128'h00000000000000000000000000000000;
expected[0]=0;
expected[1]=-5;
expected[2]=1;
expected[3]=-10;
expected[4]=-1;
expected[5]=1;
expected[6]=-13;
expected[7]=0;
expected[8]=5;
#30;aresetn=1;
axiw(6'h04,1);axiw(6'h08,9);axiw(6'h0C,1);
axiw(6'h10,0);axiw(6'h18,1);axiw(6'h1C,0);axiw(6'h20,0);
axiw(6'h00,17);
@(negedge clk);siv=1;sid=stream[0];sil=0;
while(sent<20) begin
 @(negedge clk);
 if(sent<20) begin sid=stream[sent];sil=(sent==19);end
end
siv=0;sil=0;
repeat(400) @(negedge clk);
if(got!=9 || !dut.regs.done_sticky || errors!=0) $display("FAIL got=%0d errors=%0d done=%b",got,errors,dut.regs.done_sticky);
else $display("PASS shape=1,9,1 bias=True");
$finish;end
initial begin #500000;$display("FAIL TIMEOUT sent=%0d got=%0d",sent,got);$finish;end
endmodule
