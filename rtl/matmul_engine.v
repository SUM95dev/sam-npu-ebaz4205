module matmul_engine #(
    parameter N=8,
    parameter DATA_W=8,
    parameter ACC_W=32
)(
    input wire clk,
    input wire rst,
    input wire start,
    input wire [15:0] M,
    input wire [15:0] Ndim,
    input wire [15:0] K,

    output wire [15:0] tile_m,
    output wire [15:0] tile_n,
    output wire [16:0] feed_step,
    output wire feed_req,
    input wire feed_valid,
    input wire signed [N*DATA_W-1:0] a_left,
    input wire signed [N*DATA_W-1:0] b_top,

    input wire signed [N*N*ACC_W-1:0] bias_flat,
    input wire relu_en,
    input wire signed [31:0] qmul,
    input wire [5:0] qshift,
    input wire signed [DATA_W-1:0] zero_point,

    output wire signed [N*N*DATA_W-1:0] out_tile,
    output wire [N*N-1:0] out_lane_valid,
    output wire out_tile_valid,
    output wire out_job_last,
    input  wire out_tile_ready,
    output wire busy,
    output wire done
);
    wire clear_acc,flush_en,post_start,post_done;
    wire array_en;
    wire signed [N*DATA_W-1:0] a_array;
    wire signed [N*DATA_W-1:0] b_array;
    wire feed_accept;
    wire signed [N*N*ACC_W-1:0] acc_flat;

    assign feed_accept = feed_req && feed_valid;
    assign array_en = feed_accept | flush_en;
    assign a_array = feed_accept ? a_left : {N*DATA_W{1'b0}};
    assign b_array = feed_accept ? b_top  : {N*DATA_W{1'b0}};

    matmul_controller #(.N(N)) ctrl(
        .clk(clk),.rst(rst),.start(start),.M(M),.Ndim(Ndim),.K(K),
        .tile_m(tile_m),.tile_n(tile_n),.feed_step(feed_step),.feed_req(feed_req),
        .feed_valid(feed_valid),.clear_acc(clear_acc),.flush_en(flush_en),
        .post_start(post_start),.post_done(post_done),.output_ready(out_tile_ready),
        .output_valid(out_tile_valid),.output_last(out_job_last),.busy(busy),.done(done)
    );

    systolic_array #(.N(N),.DATA_W(DATA_W),.ACC_W(ACC_W)) array_i(
        .clk(clk),.rst(rst),.clear_acc(clear_acc),
        .en(array_en),.a_left(a_array),.b_top(b_array),.acc_flat(acc_flat)
    );

    tile_postprocess #(.N(N),.DATA_W(DATA_W),.ACC_W(ACC_W)) post_i(
        .clk(clk),.rst(rst),.start(post_start),.acc_flat(acc_flat),.bias_flat(bias_flat),
        .relu_en(relu_en),.qmul(qmul),.qshift(qshift),.zero_point(zero_point),
        .out_tile(out_tile),.busy(),.done(post_done)
    );

    genvar i;
    generate
        for(i=0;i<N*N;i=i+1) begin : VALID_MASK
            localparam integer ROW = i / N;
            localparam integer COL = i % N;
            assign out_lane_valid[i] = (((tile_m * N) + ROW) < M) &&
                                       (((tile_n * N) + COL) < Ndim);
        end
    endgenerate
endmodule
