module conv2d_stream_engine #(
    parameter DATA_W=8,
    parameter ACC_W=32
)(
    input wire clk,
    input wire rst,
    input wire start,
    input wire sample_valid,
    input wire signed [DATA_W-1:0] activation,
    input wire signed [DATA_W-1:0] weight,
    input wire last_sample,
    input wire signed [ACC_W-1:0] bias,
    input wire relu_en,
    input wire signed [31:0] qmul,
    input wire [5:0] qshift,
    input wire signed [DATA_W-1:0] zero_point,
    output wire sample_ready,
    output reg signed [DATA_W-1:0] out_data,
    output reg out_valid,
    output reg busy,
    output reg done
);
    reg signed [ACC_W-1:0] acc;
    reg signed [ACC_W-1:0] bias_latched;
    reg relu_latched;
    reg signed [31:0] qmul_latched;
    reg [5:0] qshift_latched;
    reg signed [DATA_W-1:0] zero_point_latched;
    wire signed [(2*DATA_W)-1:0] prod;
    wire signed [ACC_W-1:0] add_base;
    wire signed [ACC_W-1:0] sum_next;
    wire signed [DATA_W-1:0] post_out;
    wire start_accept;
    reg processing;
    reg pp_start;
    reg signed [ACC_W-1:0] pp_acc_hold;
    wire pp_valid;
    wire signed [ACC_W-1:0] pp_bias;
    wire pp_relu;
    wire signed [31:0] pp_qmul;
    wire [5:0] pp_qshift;
    wire signed [DATA_W-1:0] pp_zero_point;

    assign start_accept = start && !busy;
    assign prod = activation * weight;
    assign sample_ready = (busy || start_accept) && !processing;
    assign add_base = start_accept ? 0 : acc;
    assign sum_next = add_base + prod;
    assign pp_bias = start_accept ? bias : bias_latched;
    assign pp_relu = start_accept ? relu_en : relu_latched;
    assign pp_qmul = start_accept ? qmul : qmul_latched;
    assign pp_qshift = start_accept ? qshift : qshift_latched;
    assign pp_zero_point = start_accept ? zero_point : zero_point_latched;

    npu_postprocess_pipe #(.ACC_W(ACC_W),.OUT_W(DATA_W)) pp_i(
        .clk(clk),.rst(rst),.in_valid(pp_start),.out_valid(pp_valid),
        .acc_in(pp_acc_hold),.bias_in(bias_latched),.relu_en(relu_latched),
        .multiplier(qmul_latched),.shift(qshift_latched),.zero_point(zero_point_latched),.out(post_out)
    );

    always @(posedge clk) begin
        if (rst) begin
            acc<=0; out_data<=0; out_valid<=0; busy<=0; done<=0;processing<=0;pp_start<=0;pp_acc_hold<=0;
            bias_latched<=0; relu_latched<=0; qmul_latched<=1; qshift_latched<=0; zero_point_latched<=0;
        end else begin
            out_valid<=0; done<=0; pp_start<=0;
            if (start_accept) begin
                acc<=0; busy<=1;
                bias_latched<=bias;
                relu_latched<=relu_en;
                qmul_latched<=qmul;
                qshift_latched<=qshift;
                zero_point_latched<=zero_point;
            end

            if (sample_ready && sample_valid) begin
                if (last_sample) begin
                    pp_acc_hold<=sum_next;pp_start<=1;processing<=1;acc<=0;
                end else begin
                    acc<=sum_next; busy<=1;
                end
            end
            if(pp_valid && processing) begin
                out_data<=post_out;out_valid<=1;busy<=0;done<=1;processing<=0;
            end
        end
    end
endmodule
