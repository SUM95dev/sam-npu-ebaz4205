`timescale 1ns/1ps
module tb_system_done_after_stream;
localparam N=2,DW=8,AWIN=32,AWOUT=32;
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

reg [31:0] st;
initial begin
  #30; aresetn=1;
  axiw(6'h04,1); axiw(6'h08,1); axiw(6'h0C,1); // M=N=K=1
  axiw(6'h10,0); axiw(6'h18,1); axiw(6'h1C,0); axiw(6'h20,0);
  axiw(6'h00,1); // start MatMul
  // N=2 skewed feed, K+N-1=2 beats. low 16=A rows, high 16=B cols.
  feed({8'd0,8'd3,8'd0,8'd2},0);
  feed(32'd0,1);
  wait(mov);
  repeat(5) @(posedge clk);
  axir(6'h00,st);
  if(st[0]!==1 || st[1]!==0) begin $display("FAIL early status busy=%b done=%b",st[0],st[1]);$finish;end
  if(held<3) begin $display("FAIL stream did not stall");$finish;end
  mor=1;
  wait(mov && mol); @(posedge clk); mor=0;
  repeat(3) @(posedge clk);
  axir(6'h00,st);
  if(st[0]!==0 || st[1]!==1) begin $display("FAIL drained status busy=%b done=%b",st[0],st[1]);$finish;end
  $display("PASS system done after AXIS drain"); $finish;
end
endmodule
