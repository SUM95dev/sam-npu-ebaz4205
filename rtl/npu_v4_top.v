module npu_v4_top #(
    parameter N=8,
    parameter DATA_W=8,
    parameter ACC_W=32
)(
    input wire clk,input wire rst,
    input wire reg_wr,input wire [5:0] reg_waddr,input wire [31:0] reg_wdata,
    input wire reg_rd,input wire [5:0] reg_raddr,output wire [31:0] reg_rdata,

    output wire [15:0] tile_m,output wire [15:0] tile_n,output wire [16:0] feed_step,
    output wire feed_req,input wire feed_valid,
    input wire signed [N*DATA_W-1:0] a_left,
    input wire signed [N*DATA_W-1:0] b_top,
    input wire signed [N*N*ACC_W-1:0] bias_flat,
    output wire signed [N*N*DATA_W-1:0] matmul_out,
    output wire [N*N-1:0] matmul_lane_valid,
    output wire matmul_out_valid,

    input wire conv_sample_valid,
    input wire signed [DATA_W-1:0] conv_activation,
    input wire signed [DATA_W-1:0] conv_weight,
    input wire conv_last_sample,
    input wire signed [ACC_W-1:0] conv_bias,
    output wire conv_sample_ready,
    output wire signed [DATA_W-1:0] conv_out,
    output wire conv_out_valid,

    output wire busy,
    output wire done
);
    wire start_pulse,mode_conv,relu_en;
    wire [15:0] M,Ndim,K;
    wire signed [31:0] qmul;
    wire [5:0] qshift;
    wire signed [7:0] zero_point;
    wire mm_busy,mm_done,cv_busy,cv_done;
    wire any_busy;
    wire mm_start;
    wire cv_start;

    assign any_busy = mm_busy | cv_busy;
    assign busy = any_busy;
    assign done = mm_done | cv_done;
    assign mm_start = start_pulse && !mode_conv && !any_busy;
    assign cv_start = start_pulse &&  mode_conv && !any_busy;

    npu_regs regs_i(
        .clk(clk),.rst(rst),.wr_en(reg_wr),.wr_addr(reg_waddr),.wr_data(reg_wdata),.wr_strb(4'hF),
        .rd_en(reg_rd),.rd_addr(reg_raddr),.rd_data(reg_rdata),.busy(busy),.done_pulse(done),
        .start_pulse(start_pulse),.mode_conv(mode_conv),.M(M),.Ndim(Ndim),.K(K),
        .relu_en(relu_en),.qmul(qmul),.qshift(qshift),.zero_point(zero_point)
    );

    matmul_engine #(.N(N),.DATA_W(DATA_W),.ACC_W(ACC_W)) mm_i(
        .clk(clk),.rst(rst),.start(mm_start),.M(M),.Ndim(Ndim),.K(K),
        .tile_m(tile_m),.tile_n(tile_n),.feed_step(feed_step),.feed_req(feed_req),
        .feed_valid(feed_valid),.a_left(a_left),.b_top(b_top),.bias_flat(bias_flat),
        .relu_en(relu_en),.qmul(qmul),.qshift(qshift),.zero_point(zero_point),
        .out_tile(matmul_out),.out_lane_valid(matmul_lane_valid),.out_tile_valid(matmul_out_valid),.out_job_last(),.out_tile_ready(1'b1),.busy(mm_busy),.done(mm_done)
    );

    conv2d_stream_engine #(.DATA_W(DATA_W),.ACC_W(ACC_W)) cv_i(
        .clk(clk),.rst(rst),.start(cv_start),.sample_valid(conv_sample_valid),
        .activation(conv_activation),.weight(conv_weight),.last_sample(conv_last_sample),
        .bias(conv_bias),.relu_en(relu_en),.qmul(qmul),.qshift(qshift),.zero_point(zero_point),
        .sample_ready(conv_sample_ready),.out_data(conv_out),.out_valid(conv_out_valid),
        .busy(cv_busy),.done(cv_done)
    );
endmodule
