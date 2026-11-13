module conv2d_addrgen #(
    parameter ADDR_W=32
)(
    input wire [ADDR_W-1:0] input_base,
    input wire [ADDR_W-1:0] weight_base,
    input wire [ADDR_W-1:0] output_base,
    input wire [ADDR_W-1:0] bias_base,

    input wire [15:0] in_w,
    input wire [15:0] in_c,
    input wire [15:0] out_w,
    input wire [15:0] out_c,
    input wire [7:0]  k_h,
    input wire [7:0]  k_w,

    input wire [15:0] oy,ox,oc,ic,
    input wire [7:0] ky,kx,
    input wire signed [31:0] iy,ix,

    output wire [ADDR_W-1:0] input_addr,
    output wire [ADDR_W-1:0] weight_addr,
    output wire [ADDR_W-1:0] output_addr,
    output wire [ADDR_W-1:0] bias_addr
);
    // Widen every operand before multiply/shift.  Verilog expression sizing can
    // otherwise truncate intermediate products (for example 32b iy * 16b in_w
    // back to 32 bits) before the value reaches this 64-bit destination.
    wire [63:0] iy_u    = {32'd0,iy[31:0]};
    wire [63:0] ix_u    = {32'd0,ix[31:0]};
    wire [63:0] in_w_u  = {48'd0,in_w};
    wire [63:0] in_c_u  = {48'd0,in_c};
    wire [63:0] out_w_u = {48'd0,out_w};
    wire [63:0] out_c_u = {48'd0,out_c};
    wire [63:0] k_h_u   = {56'd0,k_h};
    wire [63:0] k_w_u   = {56'd0,k_w};
    wire [63:0] oy_u    = {48'd0,oy};
    wire [63:0] ox_u    = {48'd0,ox};
    wire [63:0] oc_u    = {48'd0,oc};
    wire [63:0] ic_u    = {48'd0,ic};
    wire [63:0] ky_u    = {56'd0,ky};
    wire [63:0] kx_u    = {56'd0,kx};

    wire [63:0] input_index = ((iy_u * in_w_u) + ix_u) * in_c_u + ic_u;
    wire [63:0] weight_index = ((((oc_u * k_h_u) + ky_u) * k_w_u + kx_u) * in_c_u) + ic_u;
    wire [63:0] output_index = ((oy_u * out_w_u) + ox_u) * out_c_u + oc_u;
    wire [63:0] bias_index = oc_u << 2;

    assign input_addr  = input_base  + input_index[ADDR_W-1:0];
    assign weight_addr = weight_base + weight_index[ADDR_W-1:0];
    assign output_addr = output_base + output_index[ADDR_W-1:0];
    assign bias_addr   = bias_base   + bias_index[ADDR_W-1:0]; // INT32 bias
endmodule
