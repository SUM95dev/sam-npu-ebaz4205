`timescale 1ns/1ps
module tb_matmul_bias_feeder;
localparam N=8, DATA_W=8, ACC_W=32, AXIS_W=128;
reg clk=0,rst=1;
reg feed_req=0;
reg [16:0] feed_step=0;
reg [15:0] K=1;
reg bias_stream_en=1;
reg [AXIS_W-1:0] tdata=0;
reg tvalid=0;
wire tready,feed_valid;
wire signed [N*DATA_W-1:0] a_left,b_top;
wire signed [N*N*ACC_W-1:0] bias_flat;

axis_matmul_feeder #(.N(N),.DATA_W(DATA_W),.ACC_W(ACC_W),.AXIS_W(AXIS_W)) dut(
 .clk(clk),.rst(rst),.feed_req(feed_req),.feed_step(feed_step),.K(K),
 .bias_stream_en(bias_stream_en),.feed_valid(feed_valid),.a_left(a_left),.b_top(b_top),.bias_flat(bias_flat),
 .s_axis_tdata(tdata),.s_axis_tvalid(tvalid),.s_axis_tready(tready));
always #5 clk=~clk;

task send_beat;
 input [127:0] d;
 begin
  @(negedge clk); tdata=d; tvalid=1;
  while(!tready) @(negedge clk);
  @(negedge clk); tvalid=0; tdata=0; #1;
 end
endtask

function signed [31:0] get_bias;
 input integer row; input integer col;
 begin get_bias = bias_flat[(row*N+col)*ACC_W +: ACC_W]; end
endfunction

integer c;
integer feed_pulses=0;
always @(posedge clk) if(feed_valid) feed_pulses=feed_pulses+1;
initial begin
 #12; rst=0; feed_req=1;
 // Two 128-bit bias beats = eight INT32 output-column biases.
 send_beat({32'sd4,32'sd3,32'sd2,32'sd1});
 if(feed_pulses!==0) begin $display("FAIL bias beat 0 leaked into feed"); $finish; end
 send_beat({32'sd8,32'sd7,32'sd6,32'sd5});
 if(feed_pulses!==0) begin $display("FAIL bias beat 1 leaked into feed"); $finish; end
 #1;
 for(c=0;c<N;c=c+1) begin
  if(get_bias(0,c)!==(c+1) || get_bias(7,c)!==(c+1)) begin
   $display("FAIL bias replicate col=%0d row0=%0d row7=%0d",c,get_bias(0,c),get_bias(7,c)); $finish;
  end
 end
 // First real feed beat must now pass through unchanged.
 @(negedge clk); feed_step=0; tdata={64'h0807060504030201,64'hF8F9FAFBFCFDFEFF}; tvalid=1;
 #1;
 if(!tready || !feed_valid) begin $display("FAIL data beat not accepted"); $finish; end
 if(a_left!==64'hF8F9FAFBFCFDFEFF || b_top!==64'h0807060504030201) begin
  $display("FAIL A/B passthrough a=%h b=%h",a_left,b_top); $finish;
 end
 @(negedge clk); tvalid=0;
 // With K=1,N=8 last feed step is 7. Consuming it must re-arm bias preamble.
 feed_step=7; send_beat(128'h11112222333344445555666677778888);
 // The above is a data beat, because the state was still data_phase.
 feed_step=0;
 @(negedge clk); tdata=128'hAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA; tvalid=1; #1;
 if(feed_valid) begin $display("FAIL next-tile bias preamble not re-armed"); $finish; end
 @(negedge clk); tvalid=0;
 $display("PASS matmul streamed bias feeder"); $finish;
end
endmodule
