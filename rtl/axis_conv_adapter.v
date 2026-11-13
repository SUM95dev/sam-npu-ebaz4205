module axis_conv_adapter #(
    parameter DATA_W=8,
    parameter AXIS_W=128
)(
    input  wire clk,
    input  wire rst,
    input  wire conv_ready,
    input  wire [AXIS_W-1:0] s_axis_tdata,
    input  wire s_axis_tvalid,
    input  wire s_axis_tlast,
    output wire s_axis_tready,
    output wire sample_valid,
    output wire signed [DATA_W-1:0] activation,
    output wire signed [DATA_W-1:0] weight,
    output wire last_sample,
    output wire job_last,
    output wire signed [31:0] sample_bias
);
    assign s_axis_tready = conv_ready;
    assign sample_valid  = s_axis_tvalid;
    assign activation    = s_axis_tdata[DATA_W-1:0];
    assign weight        = s_axis_tdata[2*DATA_W-1:DATA_W];
    // Bit 16 marks the final MAC sample for one output scalar.
    assign last_sample   = s_axis_tdata[16];
    // Bits [63:32] carry the INT32 bias for the output scalar. The value is
    // consumed only on the first sample of a new scalar; packers place zero on
    // subsequent beats. Old zero-bias packets therefore remain compatible.
    assign sample_bias   = $signed(s_axis_tdata[63:32]);
    // AXI TLAST is reserved for the final beat of the entire Conv stream job.
    assign job_last      = s_axis_tlast;
endmodule
