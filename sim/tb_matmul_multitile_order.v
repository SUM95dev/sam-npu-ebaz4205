`timescale 1ns/1ps
module tb_matmul_multitile_order;
localparam N=2,DW=8,AW=32;
reg clk=0,rst=1,start=0,valid=0;
wire [15:0] tm,tn; wire [16:0] step; wire req;
reg signed [N*DW-1:0] a_left=0,b_top=0;
wire signed [N*N*DW-1:0] out_tile;
wire [N*N-1:0] mask;
wire out_valid,out_last,busy,done;
integer count=0;

matmul_engine #(.N(N),.DATA_W(DW),.ACC_W(AW)) dut(
 .clk(clk),.rst(rst),.start(start),.M(16'd3),.Ndim(16'd3),.K(16'd1),
 .tile_m(tm),.tile_n(tn),.feed_step(step),.feed_req(req),.feed_valid(valid),
 .a_left(a_left),.b_top(b_top),.bias_flat({N*N*AW{1'b0}}),
 .relu_en(1'b0),.qmul(32'sd1),.qshift(6'd0),.zero_point(8'sd0),
 .out_tile(out_tile),.out_lane_valid(mask),.out_tile_valid(out_valid),
 .out_job_last(out_last),.out_tile_ready(1'b1),.busy(busy),.done(done));

always #5 clk=~clk;
function signed [7:0] O; input integer i; begin O=out_tile[i*DW +: DW]; end endfunction
function signed [7:0] Aval; input integer row; begin case(row) 0:Aval=1;1:Aval=2;2:Aval=3;default:Aval=0;endcase end endfunction
function signed [7:0] Bval; input integer col; begin case(col) 0:Bval=10;1:Bval=20;2:Bval=30;default:Bval=0;endcase end endfunction

/* K=1, N=2 skewed feeder: step0 injects tile row0/col0, step1 row1/col1. */
always @(negedge clk) begin
  valid<=0; a_left<=0; b_top<=0;
  if(req) begin
    valid<=1;
    if(step==0) begin
      a_left[0*DW +: DW] <= Aval(tm*N+0);
      b_top [0*DW +: DW] <= Bval(tn*N+0);
    end else if(step==1) begin
      a_left[1*DW +: DW] <= Aval(tm*N+1);
      b_top [1*DW +: DW] <= Bval(tn*N+1);
    end
  end
end

task check_tile;
 input integer idx;
 begin
   case(idx)
    0: if(tm!==0 || tn!==0 || mask!==4'b1111 || O(0)!==10 || O(1)!==20 || O(2)!==20 || O(3)!==40 || out_last!==0) begin
         $display("FAIL MULTITILE t0 tm=%0d tn=%0d mask=%b data=%0d,%0d,%0d,%0d last=%b",tm,tn,mask,O(0),O(1),O(2),O(3),out_last); $finish; end
    1: if(tm!==0 || tn!==1 || mask!==4'b0101 || O(0)!==30 || O(2)!==60 || out_last!==0) begin
         $display("FAIL MULTITILE t1 tm=%0d tn=%0d mask=%b data=%0d,%0d,%0d,%0d last=%b",tm,tn,mask,O(0),O(1),O(2),O(3),out_last); $finish; end
    2: if(tm!==1 || tn!==0 || mask!==4'b0011 || O(0)!==30 || O(1)!==60 || out_last!==0) begin
         $display("FAIL MULTITILE t2 tm=%0d tn=%0d mask=%b data=%0d,%0d,%0d,%0d last=%b",tm,tn,mask,O(0),O(1),O(2),O(3),out_last); $finish; end
    3: if(tm!==1 || tn!==1 || mask!==4'b0001 || O(0)!==90 || out_last!==1) begin
         $display("FAIL MULTITILE t3 tm=%0d tn=%0d mask=%b data=%0d,%0d,%0d,%0d last=%b",tm,tn,mask,O(0),O(1),O(2),O(3),out_last); $finish; end
   endcase
 end
endtask

initial begin
 #12; rst=0; @(negedge clk); start=1; @(negedge clk); start=0;
 while(count<4) begin
   @(posedge clk); #1;
   if(out_valid) begin check_tile(count); count=count+1; end
 end
 wait(done); #1;
 $display("PASS MATMUL MULTITILE ORDER"); $finish;
end
endmodule
