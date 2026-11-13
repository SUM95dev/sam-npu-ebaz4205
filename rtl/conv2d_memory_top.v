module conv2d_memory_top #(
    parameter DATA_W=8,
    parameter ACC_W=32,
    parameter ADDR_W=32
)(
    input wire clk,input wire rst,input wire start,
    input wire [15:0] in_h,in_w,in_c,out_c,
    input wire [7:0] k_h,k_w,stride_h,stride_w,pad_h,pad_w,
    input wire [ADDR_W-1:0] input_base,weight_base,bias_base,output_base,

    output wire [ADDR_W-1:0] rd_input_addr,output wire rd_input_req,
    input wire signed [DATA_W-1:0] rd_input_data,input wire rd_input_valid,
    output wire [ADDR_W-1:0] rd_weight_addr,output wire rd_weight_req,
    input wire signed [DATA_W-1:0] rd_weight_data,input wire rd_weight_valid,
    output wire [ADDR_W-1:0] rd_bias_addr,output wire rd_bias_req,
    input wire signed [ACC_W-1:0] rd_bias_data,input wire rd_bias_valid,

    output reg [ADDR_W-1:0] wr_output_addr,
    output reg signed [DATA_W-1:0] wr_output_data,
    output reg wr_output_valid,input wire wr_output_ready,

    input wire relu_en,input wire signed [31:0] qmul,input wire [5:0] qshift,
    input wire signed [DATA_W-1:0] zero_point,
    output wire busy,output reg done
);
    wire [15:0] oy,ox,oc,ic;
    wire [7:0] ky,kx;
    wire signed [31:0] iy,ix;
    wire inside,last_sample,first_sample,sched_busy,sched_done;
    // Guard output-geometry arithmetic even though the scheduler rejects invalid
    // jobs.  This prevents divide-by-zero / unsigned-underflow X propagation in
    // simulation and avoids synthesizing undefined arithmetic for bad configs.
    wire [31:0] padded_w = {16'd0,in_w} + ({24'd0,pad_w} << 1);
    wire out_w_geom_valid = (stride_w != 0) && (k_w != 0) && (padded_w >= k_w);
    wire [31:0] out_w_wide = out_w_geom_valid ? ((padded_w-k_w)/stride_w + 1) : 0;
    wire [15:0] out_w_calc = out_w_wide[15:0];

    wire [ADDR_W-1:0] input_addr_i,weight_addr_i,output_addr_i,bias_addr_i;
    reg signed [DATA_W-1:0] input_hold,weight_hold;
    reg signed [ACC_W-1:0] bias_hold;
    reg input_loaded,weight_loaded,bias_loaded;
    reg input_req_sent,weight_req_sent,bias_req_sent;
    reg sample_fire;
    reg finishing;
    reg awaiting_output;
    reg [ADDR_W-1:0] output_addr_hold;
    wire sample_ready;
    wire signed [DATA_W-1:0] conv_out;
    wire conv_out_valid,conv_busy,conv_done;

    conv2d_scheduler sched(
        .clk(clk),.rst(rst),.start(start && !busy),
        .in_h(in_h),.in_w(in_w),.in_c(in_c),.out_c(out_c),
        .k_h(k_h),.k_w(k_w),.stride_h(stride_h),.stride_w(stride_w),.pad_h(pad_h),.pad_w(pad_w),
        .sample_accepted(sample_fire),
        .oy(oy),.ox(ox),.oc(oc),.ic(ic),.ky(ky),.kx(kx),.iy(iy),.ix(ix),
        .inside(inside),.last_sample(last_sample),.output_first_sample(first_sample),
        .busy(sched_busy),.done(sched_done)
    );

    conv2d_addrgen #(.ADDR_W(ADDR_W)) ag(
        .input_base(input_base),.weight_base(weight_base),.output_base(output_base),.bias_base(bias_base),
        .in_w(in_w),.in_c(in_c),.out_w(out_w_calc),.out_c(out_c),.k_h(k_h),.k_w(k_w),
        .oy(oy),.ox(ox),.oc(oc),.ic(ic),.ky(ky),.kx(kx),.iy(iy),.ix(ix),
        .input_addr(input_addr_i),.weight_addr(weight_addr_i),.output_addr(output_addr_i),.bias_addr(bias_addr_i)
    );

    assign rd_input_addr=input_addr_i;
    assign rd_weight_addr=weight_addr_i;
    assign rd_bias_addr=bias_addr_i;
    // sample_fire is a registered one-cycle pulse.  While it is high the
    // scheduler still presents the just-consumed coordinates until the next
    // edge, while the loaded flags have already been cleared.  Suppress new
    // requests during that pulse or the old address can be requested twice and
    // a late response can be mistaken for the following sample.
    assign rd_input_req=sched_busy && !sample_fire && inside && !input_loaded && !input_req_sent;
    assign rd_weight_req=sched_busy && !sample_fire && !weight_loaded && !weight_req_sent;
    assign rd_bias_req=sched_busy && !sample_fire && first_sample && !bias_loaded && !bias_req_sent;

    conv2d_stream_engine #(.DATA_W(DATA_W),.ACC_W(ACC_W)) mac(
        .clk(clk),.rst(rst),.start(first_sample && sample_fire),
        .sample_valid(sample_fire),
        .activation(inside ? input_hold : {DATA_W{1'b0}}),
        .weight(weight_hold),.last_sample(last_sample),
        .bias(bias_hold),.relu_en(relu_en),.qmul(qmul),.qshift(qshift),.zero_point(zero_point),
        .sample_ready(sample_ready),.out_data(conv_out),.out_valid(conv_out_valid),
        .busy(conv_busy),.done(conv_done)
    );

    assign busy=sched_busy | conv_busy | wr_output_valid | finishing;

    always @(posedge clk) begin
        if(rst) begin
            input_hold<=0;weight_hold<=0;bias_hold<=0;
            input_loaded<=0;weight_loaded<=0;bias_loaded<=0;
            input_req_sent<=0;weight_req_sent<=0;bias_req_sent<=0;
            sample_fire<=0; finishing<=0; awaiting_output<=0; output_addr_hold<=0;
            wr_output_addr<=0;wr_output_data<=0;wr_output_valid<=0;done<=0;
        end else begin
            sample_fire<=0;
            done<=0;

            if(rd_input_req) input_req_sent<=1;
            if(rd_weight_req) weight_req_sent<=1;
            if(rd_bias_req) bias_req_sent<=1;

            // Only consume memory responses that correspond to an outstanding
            // request (or a zero-latency response in the request cycle).  This
            // prevents unsolicited/stale responses from being associated with
            // the current Conv sample.
            if(rd_input_valid && (input_req_sent || rd_input_req)) begin
                input_hold<=rd_input_data; input_loaded<=1; input_req_sent<=0;
            end
            if(rd_weight_valid && (weight_req_sent || rd_weight_req)) begin
                weight_hold<=rd_weight_data; weight_loaded<=1; weight_req_sent<=0;
            end
            if(rd_bias_valid && (bias_req_sent || rd_bias_req)) begin
                bias_hold<=rd_bias_data; bias_loaded<=1; bias_req_sent<=0;
            end

            if(sched_busy && !sample_fire && !awaiting_output &&
               (sample_ready || (first_sample && !conv_busy)) &&
               (!inside || input_loaded) && weight_loaded &&
               (!first_sample || bias_loaded) && !wr_output_valid) begin
                sample_fire<=1;
                input_loaded<=0; input_req_sent<=0;
                weight_loaded<=0; weight_req_sent<=0;
                if(last_sample) begin
                    awaiting_output<=1;
                    output_addr_hold<=output_addr_i;
                    bias_loaded<=0; bias_req_sent<=0;
                end
            end

            if(sched_done)
                finishing<=1;

            if(conv_out_valid && !wr_output_valid) begin
                wr_output_addr<=output_addr_hold;
                wr_output_data<=conv_out;
                wr_output_valid<=1;
            end

            if(wr_output_valid && wr_output_ready) begin
                awaiting_output<=0;
                wr_output_valid<=0;
                if(finishing && !sched_busy && !conv_busy) begin
                    finishing<=0;
                    done<=1;
                end
            end
        end
    end
endmodule
