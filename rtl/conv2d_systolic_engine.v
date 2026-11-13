module conv2d_systolic_engine #(
    parameter N=8,
    parameter DATA_W=8,
    parameter ACC_W=32
)(
    input wire clk,input wire rst,input wire start,
    input wire [15:0] in_h,in_w,in_c,out_c,
    input wire [7:0] k_h,k_w,stride_h,stride_w,pad_h,pad_w,

    output wire act_req,output wire [N*32-1:0] act_addr_flat,
    input wire [N*DATA_W-1:0] act_data_flat,input wire [N-1:0] act_valid,
    output wire w_req,output wire [N*32-1:0] w_addr_flat,
    input wire [N*DATA_W-1:0] w_data_flat,input wire [N-1:0] w_valid,

    input wire signed [N*N*ACC_W-1:0] bias_flat,
    input wire relu_en,input wire signed [31:0] qmul,input wire [5:0] qshift,
    input wire signed [DATA_W-1:0] zero_point,

    output wire [15:0] tile_pos_base,output wire [15:0] tile_oc_base,
    output wire signed [N*N*DATA_W-1:0] out_tile,
    output wire [N*N-1:0] out_lane_valid,
    output wire out_tile_valid,
    output wire out_job_last,
    input  wire out_tile_ready,
    output wire busy,output wire done,
    output wire config_error
);
    reg [15:0] in_h_l,in_w_l,in_c_l,out_c_l;
    reg [7:0] k_h_l,k_w_l,stride_h_l,stride_w_l,pad_h_l,pad_w_l;
    reg [15:0] out_w_l;
    reg [31:0] total_pos_l;
    reg [16:0] k_total_l;
    reg start_mm;
    reg cfg_error_r;

    wire [31:0] padded_h = {16'd0,in_h}+({24'd0,pad_h}<<1);
    wire [31:0] padded_w = {16'd0,in_w}+({24'd0,pad_w}<<1);
    wire geom_valid = in_h!=0 && in_w!=0 && in_c!=0 && out_c!=0 &&
                      k_h!=0 && k_w!=0 && stride_h!=0 && stride_w!=0 &&
                      padded_h>=k_h && padded_w>=k_w;
    wire [31:0] out_h_calc = geom_valid ? ((padded_h-k_h)/stride_h+1) : 0;
    wire [31:0] out_w_calc = geom_valid ? ((padded_w-k_w)/stride_w+1) : 0;
    // Use explicitly widened products so an oversized configuration cannot
    // wrap around and accidentally pass the <=65535 capability checks.
    wire [63:0] total_pos_calc_wide = {32'd0,out_h_calc} * {32'd0,out_w_calc};
    wire [63:0] k_total_calc_wide = {56'd0,k_h} * {56'd0,k_w} * {48'd0,in_c};
    wire [31:0] total_pos_calc = total_pos_calc_wide[31:0];
    wire [31:0] k_total_calc = k_total_calc_wide[31:0];
    wire size_valid = geom_valid && total_pos_calc_wide>0 && total_pos_calc_wide<=65535 &&
                      k_total_calc_wide>0 && k_total_calc_wide<=65535;

    wire [15:0] tile_m,tile_n;
    wire [16:0] feed_step;
    wire feed_req,feed_valid;
    wire signed [N*DATA_W-1:0] a_left,b_top;

    assign tile_pos_base=tile_m*N;
    assign tile_oc_base=tile_n*N;
    assign config_error=cfg_error_r;

    always @(posedge clk) begin
        if(rst) begin
            in_h_l<=0;in_w_l<=0;in_c_l<=0;out_c_l<=0;
            k_h_l<=0;k_w_l<=0;stride_h_l<=0;stride_w_l<=0;pad_h_l<=0;pad_w_l<=0;
            out_w_l<=0;total_pos_l<=0;k_total_l<=0;start_mm<=0;cfg_error_r<=0;
        end else begin
            start_mm<=0;
            if(start && !busy) begin
                if(size_valid) begin
                    in_h_l<=in_h;in_w_l<=in_w;in_c_l<=in_c;out_c_l<=out_c;
                    k_h_l<=k_h;k_w_l<=k_w;stride_h_l<=stride_h;stride_w_l<=stride_w;
                    pad_h_l<=pad_h;pad_w_l<=pad_w;
                    out_w_l<=out_w_calc[15:0];total_pos_l<=total_pos_calc;k_total_l<=k_total_calc[16:0];
                    cfg_error_r<=0;start_mm<=1;
                end else begin
                    cfg_error_r<=1;
                end
            end
        end
    end

    conv2d_gemm_feeder #(.N(N),.DATA_W(DATA_W)) feeder(
        .clk(clk),.rst(rst),.feed_req(feed_req),.feed_step(feed_step),.tile_m(tile_m),.tile_n(tile_n),
        .in_h(in_h_l),.in_w(in_w_l),.in_c(in_c_l),.out_c(out_c_l),
        .k_h(k_h_l),.k_w(k_w_l),.stride_h(stride_h_l),.stride_w(stride_w_l),.pad_h(pad_h_l),.pad_w(pad_w_l),
        .out_w(out_w_l),.k_total(k_total_l),.total_pos(total_pos_l),
        .act_req(act_req),.act_addr_flat(act_addr_flat),.act_data_flat(act_data_flat),.act_valid(act_valid),
        .w_req(w_req),.w_addr_flat(w_addr_flat),.w_data_flat(w_data_flat),.w_valid(w_valid),
        .a_left(a_left),.b_top(b_top),.feed_valid(feed_valid)
    );

    matmul_engine #(.N(N),.DATA_W(DATA_W),.ACC_W(ACC_W)) mm(
        .clk(clk),.rst(rst),.start(start_mm),.M(total_pos_l[15:0]),.Ndim(out_c_l),.K(k_total_l[15:0]),
        .tile_m(tile_m),.tile_n(tile_n),.feed_step(feed_step),.feed_req(feed_req),.feed_valid(feed_valid),
        .a_left(a_left),.b_top(b_top),.bias_flat(bias_flat),
        .relu_en(relu_en),.qmul(qmul),.qshift(qshift),.zero_point(zero_point),
        .out_tile(out_tile),.out_lane_valid(out_lane_valid),.out_tile_valid(out_tile_valid),
        .out_job_last(out_job_last),.out_tile_ready(out_tile_ready),.busy(busy),.done(done)
    );
endmodule
