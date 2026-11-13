`timescale 1ns/1ps
module tb_systolic_2x2;
localparam N=2,DW=8,AW=32; reg clk=0,rst=1,clear_acc=0,en=0;
reg signed [N*DW-1:0] a_left=0,b_top=0; wire signed [N*N*AW-1:0] acc_flat;
systolic_array #(.N(N),.DATA_W(DW),.ACC_W(AW)) dut(.clk(clk),.rst(rst),.clear_acc(clear_acc),.en(en),.a_left(a_left),.b_top(b_top),.acc_flat(acc_flat));
always #5 clk=~clk;
function signed [31:0] G; input integer i; begin G=acc_flat[(i+1)*AW-1 -: AW]; end endfunction
task D;input signed[7:0]a0,a1,b0,b1;begin @(negedge clk);a_left={a1,a0};b_top={b1,b0};en=1;end endtask
initial begin #12;rst=0;@(negedge clk);clear_acc=1;@(negedge clk);clear_acc=0;
 D(1,0,5,0);D(2,3,7,6);D(0,4,0,8);D(0,0,0,0);@(negedge clk);en=0;#2;
 if(G(0)!==19||G(1)!==22||G(2)!==43||G(3)!==50) $display("FAIL SYS %0d %0d %0d %0d",G(0),G(1),G(2),G(3)); else $display("PASS SYS");$finish;end
endmodule
