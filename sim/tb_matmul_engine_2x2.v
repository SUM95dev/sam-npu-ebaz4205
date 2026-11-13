`timescale 1ns/1ps
module tb_matmul_engine_2x2;
localparam N=2,DW=8,AW=32;
reg clk=0,rst=1,start=0;
wire [15:0] tm,tn; wire [16:0] step; wire req;
reg valid=0;
reg signed [N*DW-1:0] a_left=0,b_top=0;
reg signed [N*N*AW-1:0] bias_flat=0;
wire signed [N*N*DW-1:0] out_tile;
wire [N*N-1:0] lane_valid;
wire out_valid,busy,done;
integer stalled_once=0;

matmul_engine #(.N(N),.DATA_W(DW),.ACC_W(AW)) dut(
 .clk(clk),.rst(rst),.start(start),.M(16'd2),.Ndim(16'd2),.K(16'd2),
 .tile_m(tm),.tile_n(tn),.feed_step(step),.feed_req(req),.feed_valid(valid),
 .a_left(a_left),.b_top(b_top),.bias_flat(bias_flat),
 .relu_en(1'b0),.qmul(32'sd1),.qshift(6'd0),.zero_point(8'sd0),
 .out_tile(out_tile),.out_lane_valid(lane_valid),.out_tile_valid(out_valid),.out_job_last(),.out_tile_ready(1'b1),.busy(busy),.done(done));

always #5 clk=~clk;

function signed [7:0] O;
input integer i;
begin O=out_tile[(i+1)*DW-1 -: DW]; end
endfunction

// Synchronous feeder. It deliberately stalls step 1 once.
always @(negedge clk) begin
  valid <= 0;
  if(req) begin
    if(step==1 && stalled_once==0) begin
      stalled_once <= 1;
      valid <= 0;
    end else begin
      case(step)
        0: begin a_left<={8'sd0,8'sd1}; b_top<={8'sd0,8'sd5}; end
        1: begin a_left<={8'sd3,8'sd2}; b_top<={8'sd6,8'sd7}; end
        2: begin a_left<={8'sd4,8'sd0}; b_top<={8'sd8,8'sd0}; end
        default: begin a_left<=0;b_top<=0; end
      endcase
      valid <= 1;
    end
  end
end

initial begin
 #12;rst=0;@(negedge clk);start=1;@(negedge clk);start=0;
 wait(out_valid); #1;
 if(O(0)!==19 || O(1)!==22 || O(2)!==43 || O(3)!==50) begin
   $display("FAIL ENGINE %0d %0d %0d %0d",O(0),O(1),O(2),O(3));$finish;
 end
 $display("PASS ENGINE 2x2 with stall");
 wait(done);$finish;
end
endmodule
