module tile_postprocess #(
    parameter N=8,
    parameter DATA_W=8,
    parameter ACC_W=32
)(
    input  wire clk,
    input  wire rst,
    input  wire start,
    input  wire signed [N*N*ACC_W-1:0] acc_flat,
    input  wire signed [N*N*ACC_W-1:0] bias_flat,
    input  wire relu_en,
    input  wire signed [31:0] qmul,
    input  wire [5:0] qshift,
    input  wire signed [DATA_W-1:0] zero_point,
    output reg  signed [N*N*DATA_W-1:0] out_tile,
    output reg  busy,
    output reg  done
);
    localparam LANES = N*N;
    localparam IDX_W = (LANES <= 2) ? 1 : $clog2(LANES);

    reg [IDX_W-1:0] lane_idx;
    reg feeding;
    reg [IDX_W-1:0] lane_pipe[0:5];
    wire pp_valid;
    integer j;
    wire signed [ACC_W-1:0] acc_i;
    wire signed [ACC_W-1:0] bias_i;
    wire signed [DATA_W-1:0] out_i;

    assign acc_i  = acc_flat [lane_idx*ACC_W  +: ACC_W];
    assign bias_i = bias_flat[lane_idx*ACC_W  +: ACC_W];

    npu_postprocess_pipe #(.ACC_W(ACC_W),.OUT_W(DATA_W)) pp_i(
        .clk(clk),.rst(rst),.in_valid(busy && feeding),.out_valid(pp_valid),
        .acc_in(acc_i),.bias_in(bias_i),.relu_en(relu_en),
        .multiplier(qmul),.shift(qshift),.zero_point(zero_point),.out(out_i)
    );

    always @(posedge clk) begin
        if (rst) begin
            lane_idx<=0;out_tile<=0;busy<=0;done<=0;feeding<=0;
            for(j=0;j<6;j=j+1) lane_pipe[j]<=0;
        end else begin
            done<=0;
            lane_pipe[0]<=lane_idx;
            for(j=1;j<6;j=j+1) lane_pipe[j]<=lane_pipe[j-1];
            if(start && !busy) begin lane_idx<=0;feeding<=1;busy<=1;end
            else if(busy && feeding) begin
                if(lane_idx==LANES-1) feeding<=0;
                else lane_idx<=lane_idx+1'b1;
            end
            if(pp_valid && busy) begin
                out_tile[lane_pipe[5]*DATA_W +: DATA_W]<=out_i;
                if(lane_pipe[5]==LANES-1) begin busy<=0;done<=1;end
            end
        end
    end
endmodule
