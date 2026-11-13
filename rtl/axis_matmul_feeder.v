module axis_matmul_feeder #(
    parameter N      = 8,
    parameter DATA_W = 8,
    parameter ACC_W  = 32,
    parameter AXIS_W = 2*N*DATA_W
)(
    input  wire clk,
    input  wire rst,

    input  wire feed_req,
    input  wire [16:0] feed_step,
    input  wire [15:0] K,
    input  wire bias_stream_en,
    output wire feed_valid,
    output wire signed [N*DATA_W-1:0] a_left,
    output wire signed [N*DATA_W-1:0] b_top,
    output wire signed [N*N*ACC_W-1:0] bias_flat,

    input  wire [AXIS_W-1:0] s_axis_tdata,
    input  wire              s_axis_tvalid,
    output wire              s_axis_tready
);
    localparam integer BIAS_PER_BEAT = AXIS_W/32;
    localparam integer BIAS_BEATS = (N + BIAS_PER_BEAT - 1) / BIAS_PER_BEAT;

    reg data_phase;
    reg [7:0] bias_beat;
    reg signed [N*32-1:0] bias_cols;
    integer i;

    assign s_axis_tready = feed_req;
    // Without streamed bias this is exactly the legacy direct feeder contract.
    assign feed_valid = s_axis_tvalid && s_axis_tready && (!bias_stream_en || data_phase);
    assign a_left = s_axis_tdata[N*DATA_W-1:0];
    assign b_top  = s_axis_tdata[2*N*DATA_W-1:N*DATA_W];

    genvar r,c;
    generate
        for (r=0; r<N; r=r+1) begin : BIAS_ROWS
            for (c=0; c<N; c=c+1) begin : BIAS_COLS
                wire signed [31:0] bias_col = bias_cols[c*32 +: 32];
                if (ACC_W > 32) begin : EXT
                    assign bias_flat[(r*N+c)*ACC_W +: ACC_W] = {{(ACC_W-32){bias_col[31]}},bias_col};
                end else if (ACC_W == 32) begin : SAME
                    assign bias_flat[(r*N+c)*ACC_W +: ACC_W] = bias_col;
                end else begin : TRUNC
                    assign bias_flat[(r*N+c)*ACC_W +: ACC_W] = bias_col[ACC_W-1:0];
                end
            end
        end
    endgenerate

    wire [16:0] last_feed_step = {1'b0,K} + N - 2;
    wire fire = s_axis_tvalid && s_axis_tready;

    always @(posedge clk) begin
        if (rst) begin
            data_phase <= 0;
            bias_beat <= 0;
            bias_cols <= 0;
        end else if (fire) begin
            if (bias_stream_en && !data_phase) begin
                for (i=0; i<BIAS_PER_BEAT; i=i+1) begin
                    if ((bias_beat*BIAS_PER_BEAT + i) < N)
                        bias_cols[(bias_beat*BIAS_PER_BEAT+i)*32 +: 32] <= s_axis_tdata[i*32 +: 32];
                end
                if (bias_beat + 1 >= BIAS_BEATS) begin
                    bias_beat <= 0;
                    data_phase <= 1;
                end else begin
                    bias_beat <= bias_beat + 1'b1;
                end
            end else if (feed_valid && feed_step == last_feed_step) begin
                // Next controller tile starts with a fresh bias preamble.
                data_phase <= 0;
                bias_beat <= 0;
            end
        end
    end
endmodule
