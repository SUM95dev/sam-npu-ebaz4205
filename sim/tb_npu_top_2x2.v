`timescale 1ns/1ps
module tb_npu_top_2x2;
localparam N=2,DW=8,AW=32;
reg clk=0,rst=1;
reg reg_wr=0,reg_rd=0; reg [5:0] reg_waddr=0,reg_raddr=0; reg [31:0] reg_wdata=0;
wire [31:0] reg_rdata;
wire [15:0] tm,tn; wire [16:0] step; wire req;
reg feed_valid=0; reg signed [N*DW-1:0] a_left=0,b_top=0;
reg signed [N*N*AW-1:0] bias_flat=0;
wire signed [N*N*DW-1:0] out; wire [N*N-1:0] mask; wire out_valid;
reg conv_valid=0,conv_last=0; reg signed [DW-1:0] conv_a=0,conv_w=0; reg signed [AW-1:0] conv_bias=0;
wire conv_ready; wire signed [DW-1:0] conv_out; wire conv_ov,busy,done;
integer stalled_once=0;

npu_v4_top #(.N(N),.DATA_W(DW),.ACC_W(AW)) dut(
 .clk(clk),.rst(rst),.reg_wr(reg_wr),.reg_waddr(reg_waddr),.reg_wdata(reg_wdata),
 .reg_rd(reg_rd),.reg_raddr(reg_raddr),.reg_rdata(reg_rdata),
 .tile_m(tm),.tile_n(tn),.feed_step(step),.feed_req(req),.feed_valid(feed_valid),
 .a_left(a_left),.b_top(b_top),.bias_flat(bias_flat),.matmul_out(out),
 .matmul_lane_valid(mask),.matmul_out_valid(out_valid),
 .conv_sample_valid(conv_valid),.conv_activation(conv_a),.conv_weight(conv_w),
 .conv_last_sample(conv_last),.conv_bias(conv_bias),.conv_sample_ready(conv_ready),
 .conv_out(conv_out),.conv_out_valid(conv_ov),.busy(busy),.done(done));

always #5 clk=~clk;
function signed [7:0] O; input integer i; begin O=out[i*DW +: DW]; end endfunction

task WREG; input [5:0] a; input [31:0] d; begin
 @(negedge clk); reg_wr=1;reg_waddr=a;reg_wdata=d;
 @(negedge clk); reg_wr=0;reg_wdata=0;
end endtask

always @(negedge clk) begin
 feed_valid<=0;
 if(req) begin
   if(step==1 && stalled_once==0) begin stalled_once<=1; feed_valid<=0; end
   else begin
     case(step)
       0: begin a_left<={8'sd0,8'sd1}; b_top<={8'sd0,8'sd5}; end
       1: begin a_left<={8'sd3,8'sd2}; b_top<={8'sd6,8'sd7}; end
       2: begin a_left<={8'sd4,8'sd0}; b_top<={8'sd8,8'sd0}; end
       default: begin a_left<=0;b_top<=0; end
     endcase
     feed_valid<=1;
   end
 end
end

initial begin
 #12;rst=0;
 WREG(6'h04,32'd2); // M
 WREG(6'h08,32'd2); // N
 WREG(6'h0C,32'd2); // K
 WREG(6'h00,32'h00000001); // MatMul START
 wait(out_valid); #1;
 if(mask!==4'b1111 || O(0)!==19 || O(1)!==22 || O(2)!==43 || O(3)!==50) begin
   $display("FAIL TOP OUT mask=%b values=%0d %0d %0d %0d",mask,O(0),O(1),O(2),O(3));$finish;
 end
 wait(done);
 @(posedge clk); @(posedge clk);
 reg_rd=1;reg_raddr=0;#1;
 if(reg_rdata[1]!==1'b1 || reg_rdata[2]!==1'b0) begin
   $display("FAIL TOP STATUS %h",reg_rdata);$finish;
 end
 $display("PASS TOP 2x2");$finish;
end
endmodule
