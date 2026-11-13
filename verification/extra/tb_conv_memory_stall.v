`timescale 1ns/1ps
module tb_conv_memory_stall;
reg clk=0,rst=1,start=0,wrready=0;
wire [31:0] ia,wa,ba,oa;wire ir,wr,br,ov,busy,done;wire signed [7:0] od;
reg iv=0,wv=0,bv=0;reg signed [7:0] id=0,wd=2;reg signed [31:0] bd=1;
integer outputs=0,ireqs=0,wreqs=0,breqs=0;
conv2d_memory_top dut(.clk(clk),.rst(rst),.start(start),.in_h(16'd1),.in_w(16'd2),.in_c(16'd1),.out_c(16'd1),
.k_h(8'd1),.k_w(8'd1),.stride_h(8'd1),.stride_w(8'd1),.pad_h(8'd0),.pad_w(8'd0),
.input_base(32'd100),.weight_base(32'd200),.bias_base(32'd300),.output_base(32'd400),
.rd_input_addr(ia),.rd_input_req(ir),.rd_input_data(id),.rd_input_valid(iv),
.rd_weight_addr(wa),.rd_weight_req(wr),.rd_weight_data(wd),.rd_weight_valid(wv),
.rd_bias_addr(ba),.rd_bias_req(br),.rd_bias_data(bd),.rd_bias_valid(bv),
.wr_output_addr(oa),.wr_output_data(od),.wr_output_valid(ov),.wr_output_ready(wrready),
.relu_en(1'b0),.qmul(32'sd1),.qshift(6'd0),.zero_point(8'sd0),.busy(busy),.done(done));
always #5 clk=~clk;
always @(posedge clk)begin
 iv<=ir;wv<=wr;bv<=br;
 if(ir)begin id<=ia==100?3:6;ireqs=ireqs+1;end
 if(wr)wreqs=wreqs+1;
 if(br)breqs=breqs+1;
 if(ov&&wrready)begin
  if(oa!==(400+outputs)||$signed(od)!==(7+outputs*6))begin $display("FAIL memory Conv out=%0d addr=%0d data=%0d",outputs,oa,od);$finish;end
  outputs=outputs+1;
 end
end
initial begin
 #12;rst=0;@(negedge clk);start=1;@(negedge clk);start=0;
 wait(ov);repeat(30)begin @(negedge clk);if(!ov||oa!==400||od!==7||done)begin $display("FAIL output changed under stall");$finish;end end
 wrready=1;wait(done);#1;
 if(outputs!=2||ireqs!=2||wreqs!=2||breqs!=2)begin $display("FAIL memory counts out=%0d req=%0d/%0d/%0d",outputs,ireqs,wreqs,breqs);$finish;end
 $display("PASS Conv memory first sample and output stall");$finish;
end
initial begin #10000;$display("FAIL Conv memory timeout");$finish;end
endmodule
