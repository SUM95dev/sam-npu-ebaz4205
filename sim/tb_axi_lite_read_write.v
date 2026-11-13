`timescale 1ns/1ps
module tb_axi_lite_read_write;
reg clk=0, rstn=0;
reg [5:0] awaddr=0; reg awvalid=0; wire awready;
reg [31:0] wdata=0; reg [3:0] wstrb=0; reg wvalid=0; wire wready;
wire [1:0] bresp; wire bvalid; reg bready=0;
reg [5:0] araddr=0; reg arvalid=0; wire arready;
wire [31:0] rdata; wire [1:0] rresp; wire rvalid; reg rready=0;
wire reg_wr; wire [5:0] reg_waddr; wire [31:0] reg_wdata; wire [3:0] reg_wstrb;
wire reg_rd; wire [5:0] reg_raddr; reg [31:0] reg_rdata;
integer wr_seen=0;

always #5 clk=~clk;
always @* begin
    case (reg_raddr[5:2])
      4'h1: reg_rdata=32'h11112222;
      4'h2: reg_rdata=32'h33334444;
      default: reg_rdata=32'hDEADBEEF;
    endcase
end
always @(posedge clk) if(reg_wr) begin
    wr_seen=wr_seen+1;
    if(reg_waddr!==6'h0C || reg_wdata!==32'hA5A55A5A || reg_wstrb!==4'b0101) begin
        $display("FAIL AXIL write payload addr=%h data=%h strb=%b",reg_waddr,reg_wdata,reg_wstrb); $finish;
    end
end

npu_axi_lite_slave dut(
 .aclk(clk),.aresetn(rstn),
 .s_axi_awaddr(awaddr),.s_axi_awvalid(awvalid),.s_axi_awready(awready),
 .s_axi_wdata(wdata),.s_axi_wstrb(wstrb),.s_axi_wvalid(wvalid),.s_axi_wready(wready),
 .s_axi_bresp(bresp),.s_axi_bvalid(bvalid),.s_axi_bready(bready),
 .s_axi_araddr(araddr),.s_axi_arvalid(arvalid),.s_axi_arready(arready),
 .s_axi_rdata(rdata),.s_axi_rresp(rresp),.s_axi_rvalid(rvalid),.s_axi_rready(rready),
 .reg_wr(reg_wr),.reg_waddr(reg_waddr),.reg_wdata(reg_wdata),.reg_wstrb(reg_wstrb),
 .reg_rd(reg_rd),.reg_raddr(reg_raddr),.reg_rdata(reg_rdata));

initial begin
  #17; rstn=1;
  // AW and W deliberately arrive on different cycles.
  @(negedge clk); awaddr=6'h0C; awvalid=1;
  wait(awready); @(negedge clk); awvalid=0;
  repeat(2) @(negedge clk);
  wdata=32'hA5A55A5A; wstrb=4'b0101; wvalid=1;
  wait(wready); @(negedge clk); wvalid=0;
  wait(bvalid); if(bresp!==2'b00) begin $display("FAIL AXIL BRESP");$finish;end
  bready=1; @(posedge clk); #1; bready=0;
  if(wr_seen!==1) begin $display("FAIL AXIL write count=%0d",wr_seen);$finish;end

  // First read checks correct/current address, not stale address.
  araddr=6'h04; arvalid=1; wait(arready); @(negedge clk); arvalid=0;
  wait(rvalid); if(rdata!==32'h11112222) begin $display("FAIL AXIL read1 %h",rdata);$finish;end
  // Hold RREADY low: payload must remain stable.
  repeat(3) begin @(negedge clk); if(!rvalid || rdata!==32'h11112222) begin $display("FAIL AXIL read hold");$finish;end end
  rready=1; @(negedge clk); rready=0;

  // Back-to-back new address after response.
  araddr=6'h08; arvalid=1; wait(arready); @(negedge clk); arvalid=0;
  wait(rvalid); if(rdata!==32'h33334444) begin $display("FAIL AXIL read2 stale=%h",rdata);$finish;end
  rready=1; @(negedge clk); rready=0;
  $display("PASS AXI-Lite read/write sequencing"); $finish;
end
endmodule
