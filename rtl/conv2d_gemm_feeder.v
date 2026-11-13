module conv2d_gemm_feeder #(
    parameter N=8,
    parameter DATA_W=8
)(
    input wire clk,
    input wire rst,
    input wire feed_req,
    input wire [16:0] feed_step,
    input wire [15:0] tile_m,
    input wire [15:0] tile_n,

    input wire [15:0] in_h,in_w,in_c,out_c,
    input wire [7:0] k_h,k_w,stride_h,stride_w,pad_h,pad_w,
    input wire [15:0] out_w,
    input wire [16:0] k_total,
    input wire [31:0] total_pos,

    output reg act_req,
    output reg [N*32-1:0] act_addr_flat,
    input wire [N*DATA_W-1:0] act_data_flat,
    input wire [N-1:0] act_valid,

    output reg w_req,
    output reg [N*32-1:0] w_addr_flat,
    input wire [N*DATA_W-1:0] w_data_flat,
    input wire [N-1:0] w_valid,

    output wire signed [N*DATA_W-1:0] a_left,
    output wire signed [N*DATA_W-1:0] b_top,
    output wire feed_valid
);
    reg active;
    reg [N-1:0] a_need,a_loaded,w_need,w_loaded;
    reg signed [N*DATA_W-1:0] a_hold,b_hold;
    integer r,c;
    integer kr,kc;
    integer pos,oc;
    integer oy,ox,ic_i,kx_i,ky_i;
    integer iy_i,ix_i;

    assign a_left = a_hold;
    assign b_top  = b_hold;
    assign feed_valid = active && ((a_loaded & a_need)==a_need) &&
                                     ((w_loaded & w_need)==w_need);

    always @(posedge clk) begin
        if (rst) begin
            active<=0; act_req<=0; w_req<=0;
            act_addr_flat<=0; w_addr_flat<=0;
            a_need<=0;a_loaded<=0;w_need<=0;w_loaded<=0;
            a_hold<=0;b_hold<=0;
        end else begin
            act_req<=0; w_req<=0;

            if (active) begin
                for (r=0;r<N;r=r+1) begin
                    if (a_need[r] && !a_loaded[r] && act_valid[r]) begin
                        a_hold[r*DATA_W +: DATA_W] <= act_data_flat[r*DATA_W +: DATA_W];
                        a_loaded[r] <= 1'b1;
                    end
                end
                for (c=0;c<N;c=c+1) begin
                    if (w_need[c] && !w_loaded[c] && w_valid[c]) begin
                        b_hold[c*DATA_W +: DATA_W] <= w_data_flat[c*DATA_W +: DATA_W];
                        w_loaded[c] <= 1'b1;
                    end
                end

                if (feed_valid && feed_req) begin
                    active<=0;
                end
            end else if (feed_req) begin
                a_need<=0; a_loaded<=0; w_need<=0; w_loaded<=0;
                a_hold<=0; b_hold<=0;

                for (r=0;r<N;r=r+1) begin
                    kr = feed_step - r;
                    pos = tile_m*N + r;
                    if (in_c != 0 && k_w != 0 && out_w != 0 &&
                        pos < total_pos && kr >= 0 && kr < k_total) begin
                        ic_i = kr % in_c;
                        kx_i = (kr / in_c) % k_w;
                        ky_i = (kr / in_c) / k_w;
                        oy = pos / out_w;
                        ox = pos % out_w;
                        iy_i = oy*stride_h + ky_i - pad_h;
                        ix_i = ox*stride_w + kx_i - pad_w;
                        if (iy_i >= 0 && ix_i >= 0 && iy_i < in_h && ix_i < in_w) begin
                            act_addr_flat[r*32 +: 32] <= ((iy_i*in_w)+ix_i)*in_c + ic_i;
                            a_need[r]<=1;
                        end else begin
                            act_addr_flat[r*32 +: 32] <= 32'hFFFFFFFF;
                            a_loaded[r]<=1;
                        end
                    end else begin
                        act_addr_flat[r*32 +: 32] <= 32'hFFFFFFFF;
                        a_loaded[r]<=1;
                    end
                end

                for (c=0;c<N;c=c+1) begin
                    kc = feed_step - c;
                    oc = tile_n*N + c;
                    if (in_c != 0 && k_w != 0 &&
                        oc < out_c && kc >= 0 && kc < k_total) begin
                        ic_i = kc % in_c;
                        kx_i = (kc / in_c) % k_w;
                        ky_i = (kc / in_c) / k_w;
                        w_addr_flat[c*32 +: 32] <= (((oc*k_h+ky_i)*k_w+kx_i)*in_c)+ic_i;
                        w_need[c]<=1;
                    end else begin
                        w_addr_flat[c*32 +: 32] <= 32'hFFFFFFFF;
                        w_loaded[c]<=1;
                    end
                end
                act_req<=1;
                w_req<=1;
                active<=1;
            end
        end
    end
endmodule
