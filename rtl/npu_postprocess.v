module npu_postprocess #(
    parameter ACC_W = 32,
    parameter OUT_W = 8
)(
    input  wire signed [ACC_W-1:0] acc_in,
    input  wire signed [ACC_W-1:0] bias_in,
    input  wire                    relu_en,
    input  wire signed [31:0]      multiplier,
    input  wire [5:0]              shift,
    input  wire signed [OUT_W-1:0] zero_point,
    output reg  signed [OUT_W-1:0] out
);
    localparam BIAS_W  = ACC_W + 1;
    localparam SCALE_W = BIAS_W + 32;

    // Explicit extension avoids silent truncation before the wider result is stored.
    wire signed [BIAS_W-1:0] acc_ext  = {acc_in[ACC_W-1],  acc_in};
    wire signed [BIAS_W-1:0] bias_ext = {bias_in[ACC_W-1], bias_in};
    wire signed [BIAS_W-1:0] biased_w = acc_ext + bias_ext;

    // Keep the multiplier operands at their true widths: 33 x 32 -> 65 bits.
    // Extending the biased operand to 65 bits *before* multiplication can make
    // synthesis infer a much larger multiplier than the arithmetic requires.
    (* use_dsp = "yes" *) wire signed [SCALE_W-1:0] scaled_w;
    assign scaled_w = $signed(biased_w) * $signed(multiplier);

    reg signed [SCALE_W-1:0] shifted;
    reg signed [SCALE_W-1:0] activated;
    reg signed [SCALE_W-1:0] with_zp;

    // Saturation limits sign-extended to SCALE_W.
    reg signed [SCALE_W-1:0] out_max;
    reg signed [SCALE_W-1:0] out_min;

    always @* begin
        out_max = ({{(SCALE_W-1){1'b0}},1'b1} <<< (OUT_W-1)) - 1'b1;
        out_min = -({{(SCALE_W-1){1'b0}},1'b1} <<< (OUT_W-1));

        shifted   = scaled_w >>> shift;
        activated = (relu_en && shifted < 0) ? {SCALE_W{1'b0}} : shifted;
        with_zp   = activated + {{(SCALE_W-OUT_W){zero_point[OUT_W-1]}}, zero_point};

        if (with_zp > out_max)
            out = out_max[OUT_W-1:0];
        else if (with_zp < out_min)
            out = out_min[OUT_W-1:0];
        else
            out = with_zp[OUT_W-1:0];
    end
endmodule
