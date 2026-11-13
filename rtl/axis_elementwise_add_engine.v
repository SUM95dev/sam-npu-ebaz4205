module axis_elementwise_add_engine #(
    parameter DATA_W=8,
    parameter AXIS_W=128
)(
    input  wire clk,
    input  wire rst,
    input  wire start,
    input  wire relu_en,
    input  wire [AXIS_W-1:0] s_axis_tdata,
    input  wire s_axis_tvalid,
    input  wire s_axis_tlast,
    output wire s_axis_tready,
    output reg signed [DATA_W-1:0] out_data,
    output reg out_valid,
    input  wire out_ready,
    output reg out_last,
    output reg busy,
    output reg done
);
    wire signed [DATA_W-1:0] a = s_axis_tdata[DATA_W-1:0];
    wire signed [DATA_W-1:0] b = s_axis_tdata[2*DATA_W-1:DATA_W];
    wire signed [DATA_W:0] sum_wide = $signed(a) + $signed(b);
    wire signed [DATA_W:0] act_wide = (relu_en && sum_wide < 0) ? 0 : sum_wide;
    localparam signed [DATA_W:0] MAXV = (1 <<< (DATA_W-1)) - 1;
    localparam signed [DATA_W:0] MINV = -(1 <<< (DATA_W-1));
    wire signed [DATA_W-1:0] sat = (act_wide > MAXV) ? MAXV[DATA_W-1:0] :
                                   (act_wide < MINV) ? MINV[DATA_W-1:0] :
                                   act_wide[DATA_W-1:0];

    // Permit one beat/cycle when the previous output is consumed. Never accept a
    // following beat in the cycle the final output drains.
    assign s_axis_tready = busy && (!out_valid || (out_ready && !out_last));
    wire fire = s_axis_tvalid && s_axis_tready;

    always @(posedge clk) begin
        if (rst) begin
            out_data<=0; out_valid<=0; out_last<=0; busy<=0; done<=0;
        end else begin
            done<=0;
            if (start && !busy) begin
                busy<=1; out_valid<=0; out_last<=0;
            end

            if (out_valid && out_ready) begin
                if (out_last) begin
                    busy<=0;
                    done<=1;
                end
                out_valid<=0;
                out_last<=0;
            end

            if (fire) begin
                out_data<=sat;
                out_valid<=1;
                out_last<=s_axis_tlast;
            end
        end
    end
endmodule
