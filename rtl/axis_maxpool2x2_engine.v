module axis_maxpool2x2_engine #(
    parameter DATA_W=8,
    parameter AXIS_W=128
)(
    input  wire clk,
    input  wire rst,
    input  wire start,
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
    reg [1:0] sample_idx;
    reg signed [DATA_W-1:0] max_hold;
    wire signed [DATA_W-1:0] sample = s_axis_tdata[DATA_W-1:0];
    wire signed [DATA_W-1:0] max_next = (sample > max_hold) ? sample : max_hold;

    // Keep one output word buffered. A new 2x2 group starts only after the
    // previous result has drained, which makes backpressure behavior explicit.
    assign s_axis_tready = busy && !out_valid;
    wire fire = s_axis_tvalid && s_axis_tready;

    always @(posedge clk) begin
        if (rst) begin
            sample_idx<=0; max_hold<=0; out_data<=0; out_valid<=0;
            out_last<=0; busy<=0; done<=0;
        end else begin
            done<=0;
            if (start && !busy) begin
                sample_idx<=0; max_hold<=0; out_valid<=0; out_last<=0; busy<=1;
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
                if (sample_idx == 0) begin
                    max_hold <= sample;
                    sample_idx <= 1;
                end else if (sample_idx == 3) begin
                    out_data <= max_next;
                    out_valid <= 1;
                    out_last <= s_axis_tlast;
                    sample_idx <= 0;
                    max_hold <= 0;
                end else begin
                    max_hold <= max_next;
                    sample_idx <= sample_idx + 1'b1;
                end
            end
        end
    end
endmodule
