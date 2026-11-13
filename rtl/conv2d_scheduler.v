module conv2d_scheduler(
    input  wire clk,
    input  wire rst,
    input  wire start,

    input  wire [15:0] in_h,
    input  wire [15:0] in_w,
    input  wire [15:0] in_c,
    input  wire [15:0] out_c,
    input  wire [7:0]  k_h,
    input  wire [7:0]  k_w,
    input  wire [7:0]  stride_h,
    input  wire [7:0]  stride_w,
    input  wire [7:0]  pad_h,
    input  wire [7:0]  pad_w,

    input  wire sample_accepted,

    output reg  [15:0] oy,
    output reg  [15:0] ox,
    output reg  [15:0] oc,
    output reg  [15:0] ic,
    output reg  [7:0]  ky,
    output reg  [7:0]  kx,
    output wire signed [31:0] iy,
    output wire signed [31:0] ix,
    output wire inside,
    output wire last_sample,
    output wire output_first_sample,
    output reg  busy,
    output reg  done
);
    wire [31:0] padded_h = {16'd0,in_h} + ({24'd0,pad_h}<<1);
    wire [31:0] padded_w = {16'd0,in_w} + ({24'd0,pad_w}<<1);
    wire geom_valid = (stride_h != 0) && (stride_w != 0) &&
                      (k_h != 0) && (k_w != 0) &&
                      (padded_h >= k_h) && (padded_w >= k_w);
    wire [31:0] out_h_wide = geom_valid ? ((padded_h - k_h) / stride_h + 1) : 0;
    wire [31:0] out_w_wide = geom_valid ? ((padded_w - k_w) / stride_w + 1) : 0;
    wire size_valid = geom_valid && (out_h_wide > 0) && (out_w_wide > 0) &&
                      (out_h_wide <= 32'd65535) && (out_w_wide <= 32'd65535);
    wire [15:0] out_h = out_h_wide[15:0];
    wire [15:0] out_w = out_w_wide[15:0];

    assign iy = $signed({1'b0,oy}) * $signed({1'b0,stride_h})
              + $signed({1'b0,ky}) - $signed({1'b0,pad_h});
    assign ix = $signed({1'b0,ox}) * $signed({1'b0,stride_w})
              + $signed({1'b0,kx}) - $signed({1'b0,pad_w});
    assign inside = (iy >= 0) && (ix >= 0) && (iy < in_h) && (ix < in_w);
    assign last_sample = (ic + 1 >= in_c) && (kx + 1 >= k_w) && (ky + 1 >= k_h);
    assign output_first_sample = (ic == 0) && (kx == 0) && (ky == 0);

    always @(posedge clk) begin
        if (rst) begin
            oy<=0; ox<=0; oc<=0; ic<=0; ky<=0; kx<=0;
            busy<=0; done<=0;
        end else begin
            done<=0;
            if (start && !busy &&
                in_h!=0 && in_w!=0 && in_c!=0 && out_c!=0 &&
                size_valid) begin
                oy<=0; ox<=0; oc<=0; ic<=0; ky<=0; kx<=0;
                busy<=1;
            end else if (busy && sample_accepted) begin
                if (ic + 1 < in_c) begin
                    ic <= ic + 1'b1;
                end else begin
                    ic <= 0;
                    if (kx + 1 < k_w) begin
                        kx <= kx + 1'b1;
                    end else begin
                        kx <= 0;
                        if (ky + 1 < k_h) begin
                            ky <= ky + 1'b1;
                        end else begin
                            ky <= 0;
                            if (oc + 1 < out_c) begin
                                oc <= oc + 1'b1;
                            end else begin
                                oc <= 0;
                                if (ox + 1 < out_w) begin
                                    ox <= ox + 1'b1;
                                end else begin
                                    ox <= 0;
                                    if (oy + 1 < out_h) begin
                                        oy <= oy + 1'b1;
                                    end else begin
                                        busy <= 0;
                                        done <= 1;
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
endmodule
