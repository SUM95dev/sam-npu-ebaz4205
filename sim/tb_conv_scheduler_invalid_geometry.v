`timescale 1ns/1ps
module tb_conv_scheduler_invalid_geometry;
reg clk=0,rst=1,start=0;wire busy,done;wire[15:0] oy,ox,oc,ic;wire[7:0] ky,kx;wire signed[31:0] iy,ix;wire inside,lasts,firsts;
conv2d_scheduler dut(.clk(clk),.rst(rst),.start(start),.in_h(2),.in_w(2),.in_c(1),.out_c(1),
 .k_h(3),.k_w(3),.stride_h(0),.stride_w(1),.pad_h(0),.pad_w(0),.sample_accepted(0),
 .oy(oy),.ox(ox),.oc(oc),.ic(ic),.ky(ky),.kx(kx),.iy(iy),.ix(ix),.inside(inside),.last_sample(lasts),
 .output_first_sample(firsts),.busy(busy),.done(done));
always #5 clk=~clk;
initial begin #12;rst=0;@(negedge clk);start=1;@(negedge clk);start=0;repeat(3)@(posedge clk);
 if(busy!==0) begin $display("FAIL invalid geometry started");$finish;end
 $display("PASS invalid geometry rejected");$finish;end
endmodule
