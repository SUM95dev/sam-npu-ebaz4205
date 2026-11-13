module conv_stream_job_engine #(
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
    input wire job_last,
    input wire signed [ACC_W-1:0] sample_bias,
    input wire relu_en,
    input wire signed [31:0] qmul,
    input wire [5:0] qshift,
    input wire signed [DATA_W-1:0] zero_point,
    output wire sample_ready,
    output reg signed [DATA_W-1:0] out_data,
    output reg out_valid,
    input wire out_ready,
    output reg out_last,
    output reg busy,
    output reg done
);
    reg job_active;
    reg final_output_pending;
    reg relu_latched;
    reg signed [31:0] qmul_latched;
    reg [5:0] qshift_latched;
    reg signed [DATA_W-1:0] zero_point_latched;

    wire core_busy,core_done,core_ready;
    wire signed [DATA_W-1:0] core_out;
    wire core_out_valid;
    wire output_space = !out_valid || out_ready;

    // Do not accept a new sample during the cycle in which the previous
    // output arrives. This gives the one-entry output buffer an unambiguous handoff.
    // The final input ends the job even while its result is still in flight.
    // Fence following input until completion and a fresh START.
    wire job_accept_enable = job_active && !final_output_pending && !(out_valid && out_last) &&
                             !core_out_valid && (!last_sample || output_space);
    assign sample_ready = job_accept_enable && (!core_busy || core_ready);
    wire fire = sample_valid && sample_ready;
    // When idle, the core starts directly from the offered sample and available
    // output slot. Do not derive START from READY: core READY itself depends on
    // START for its first sample, which otherwise creates a combinational loop.
    wire core_start = sample_valid && job_accept_enable && !core_busy;

    conv2d_stream_engine #(.DATA_W(DATA_W),.ACC_W(ACC_W)) core(
        .clk(clk),.rst(rst),.start(core_start),.sample_valid(fire),
        .activation(activation),.weight(weight),.last_sample(last_sample),
        .bias(sample_bias),.relu_en(relu_latched),.qmul(qmul_latched),
        .qshift(qshift_latched),.zero_point(zero_point_latched),
        .sample_ready(core_ready),.out_data(core_out),.out_valid(core_out_valid),
        .busy(core_busy),.done(core_done)
    );

    always @(posedge clk) begin
        if (rst) begin
            job_active<=0; final_output_pending<=0; busy<=0; done<=0;
            out_data<=0; out_valid<=0; out_last<=0;
            relu_latched<=0; qmul_latched<=1;
            qshift_latched<=0; zero_point_latched<=0;
        end else begin
            done<=0;

            if (out_valid && out_ready) begin
                if (out_last) begin
                    job_active<=0;
                    busy<=0;
                    done<=1;
                end
                out_valid<=0;
                out_last<=0;
            end

            if (start && !job_active) begin
                job_active<=1;
                busy<=1;
                final_output_pending<=0;
                relu_latched<=relu_en;
                qmul_latched<=qmul;
                qshift_latched<=qshift;
                zero_point_latched<=zero_point;
            end

            if (fire && last_sample && job_last)
                final_output_pending<=1;

            if (core_out_valid) begin
                out_data<=core_out;
                out_valid<=1;
                out_last<=final_output_pending;
                final_output_pending<=0;
            end
        end
    end
endmodule
