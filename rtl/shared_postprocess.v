module shared_postprocess #(
    parameter N=8,
    parameter DATA_W=8,
    parameter ACC_W=32
)(
    input  wire clk,
    input  wire rst,
    input  wire start,
    input  wire signed [N*N*ACC_W-1:0] acc_flat,
    input  wire signed [N*N*ACC_W-1:0] bias_flat,
    input  wire [N*N-1:0] lane_valid_in,
    input  wire relu_en,
    input  wire signed [31:0] qmul,
    input  wire [5:0] qshift,
    input  wire signed [DATA_W-1:0] zero_point,
    output wire signed [N*N*DATA_W-1:0] out_tile,
    output reg  [N*N-1:0] out_lane_valid,
    output reg  out_tile_valid,
    output wire busy,
    output wire done
);
    reg [N*N-1:0] lane_mask_latched;
    wire core_done;

    tile_postprocess #(.N(N),.DATA_W(DATA_W),.ACC_W(ACC_W)) core(
        .clk(clk),.rst(rst),.start(start),.acc_flat(acc_flat),.bias_flat(bias_flat),
        .relu_en(relu_en),.qmul(qmul),.qshift(qshift),.zero_point(zero_point),
        .out_tile(out_tile),.busy(busy),.done(core_done)
    );

    assign done = core_done;

    always @(posedge clk) begin
        if (rst) begin
            lane_mask_latched <= 0;
            out_lane_valid <= 0;
            out_tile_valid <= 0;
        end else begin
            out_tile_valid <= 0;
            if (start && !busy)
                lane_mask_latched <= lane_valid_in;
            if (core_done) begin
                out_lane_valid <= lane_mask_latched;
                out_tile_valid <= 1;
            end
        end
    end
endmodule
