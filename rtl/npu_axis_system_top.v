module npu_axis_system_top #(
    parameter N=8,
    parameter DATA_W=8,
    parameter ACC_W=32,
    parameter AXIS_IN_W=128,
    parameter AXIS_OUT_W=32
)(
    input wire aclk,
    input wire aresetn,

    // AXI4-Lite control
    input  wire [5:0]  s_axi_awaddr,
    input  wire        s_axi_awvalid,
    output wire        s_axi_awready,
    input  wire [31:0] s_axi_wdata,
    input  wire [3:0]  s_axi_wstrb,
    input  wire        s_axi_wvalid,
    output wire        s_axi_wready,
    output wire [1:0]  s_axi_bresp,
    output wire        s_axi_bvalid,
    input  wire        s_axi_bready,
    input  wire [5:0]  s_axi_araddr,
    input  wire        s_axi_arvalid,
    output wire        s_axi_arready,
    output wire [31:0] s_axi_rdata,
    output wire [1:0]  s_axi_rresp,
    output wire        s_axi_rvalid,
    input  wire        s_axi_rready,

    // DMA MM2S -> NPU
    input  wire [AXIS_IN_W-1:0] s_axis_tdata,
    input  wire                 s_axis_tvalid,
    output wire                 s_axis_tready,
    input  wire                 s_axis_tlast,

    // NPU -> DMA S2MM
    output wire [AXIS_OUT_W-1:0] m_axis_tdata,
    output wire                  m_axis_tvalid,
    input  wire                  m_axis_tready,
    output wire                  m_axis_tlast,

    // Bias tile supplied by local BRAM / DMA-side adapter for MatMul.
    input wire signed [N*N*ACC_W-1:0] bias_flat,

    // Level-high completion interrupt. It remains asserted while DONE sticky is
    // set and IRQ_EN is enabled; software acks through register 0x14 bit1.
    output wire irq
);
    wire rst = !aresetn;
    wire reg_wr,reg_rd;
    wire [5:0] reg_waddr,reg_raddr;
    wire [31:0] reg_wdata,reg_rdata;
    wire [3:0] reg_wstrb;

    wire start_pulse,mode_conv,mode_pool,mode_add,matmul_bias_en,relu_en;
    wire [15:0] M,Ndim,K;
    wire signed [31:0] qmul;
    wire [5:0] qshift;
    wire signed [7:0] zero_point;
    wire abort_pulse;

    wire mm_busy,mm_done,cv_busy,cv_done,pool_busy,pool_done,add_busy,add_done;
    wire mm_tile_ready;
    wire mm_axis_busy;
    reg  mm_done_pending;
    reg  mm_done_drained_pulse;

    wire mode_matmul = !mode_conv && !mode_pool && !mode_add;
    wire any_busy = mm_busy | cv_busy | pool_busy | add_busy | mm_axis_busy | mm_done_pending;
    wire done_pulse = mm_done_drained_pulse | cv_done | pool_done | add_done;
    wire mm_start   = start_pulse && mode_matmul && !any_busy;
    wire cv_start   = start_pulse && mode_conv   && !any_busy;
    wire pool_start = start_pulse && mode_pool   && !any_busy;
    wire add_start  = start_pulse && mode_add    && !any_busy;

    // ABORT resets datapath state but deliberately does not reset configuration,
    // counters, or the register file. Software should cancel both DMA channels too.
    wire core_rst = rst | abort_pulse;

    // A MatMul compute job is not externally complete when the controller has
    // merely handed the final tile to the serializer. Keep BUSY asserted and
    // delay DONE until the final AXI-Stream beat has actually drained.
    always @(posedge aclk) begin
        if (core_rst) begin
            mm_done_pending <= 1'b0;
            mm_done_drained_pulse <= 1'b0;
        end else begin
            mm_done_drained_pulse <= 1'b0;
            if (mm_done)
                mm_done_pending <= 1'b1;
            if (mm_done_pending && !mm_axis_busy) begin
                mm_done_pending <= 1'b0;
                mm_done_drained_pulse <= 1'b1;
            end
        end
    end

    npu_axi_lite_slave ctrl_axi(
        .aclk(aclk),.aresetn(aresetn),
        .s_axi_awaddr(s_axi_awaddr),.s_axi_awvalid(s_axi_awvalid),.s_axi_awready(s_axi_awready),
        .s_axi_wdata(s_axi_wdata),.s_axi_wstrb(s_axi_wstrb),.s_axi_wvalid(s_axi_wvalid),.s_axi_wready(s_axi_wready),
        .s_axi_bresp(s_axi_bresp),.s_axi_bvalid(s_axi_bvalid),.s_axi_bready(s_axi_bready),
        .s_axi_araddr(s_axi_araddr),.s_axi_arvalid(s_axi_arvalid),.s_axi_arready(s_axi_arready),
        .s_axi_rdata(s_axi_rdata),.s_axi_rresp(s_axi_rresp),.s_axi_rvalid(s_axi_rvalid),.s_axi_rready(s_axi_rready),
        .reg_wr(reg_wr),.reg_waddr(reg_waddr),.reg_wdata(reg_wdata),.reg_wstrb(reg_wstrb),
        .reg_rd(reg_rd),.reg_raddr(reg_raddr),.reg_rdata(reg_rdata)
    );

    npu_regs #(.ARRAY_N(N),.DATA_W(DATA_W),.ACC_W(ACC_W)) regs(
        .clk(aclk),.rst(rst),.wr_en(reg_wr),.wr_addr(reg_waddr),.wr_data(reg_wdata),.wr_strb(reg_wstrb),
        .rd_en(reg_rd),.rd_addr(reg_raddr),.rd_data(reg_rdata),
        .busy(any_busy),.done_pulse(done_pulse),
        .start_pulse(start_pulse),.mode_conv(mode_conv),.mode_pool(mode_pool),.mode_add(mode_add),.matmul_bias_en(matmul_bias_en),
        .M(M),.Ndim(Ndim),.K(K),
        .relu_en(relu_en),.qmul(qmul),.qshift(qshift),.zero_point(zero_point),
        .abort_pulse(abort_pulse),.irq(irq)
    );

    // ---------------- MatMul / Dense ----------------
    wire [15:0] tile_m,tile_n;
    wire [16:0] feed_step;
    wire feed_req,feed_valid;
    wire signed [N*DATA_W-1:0] a_left,b_top;
    wire signed [N*N*ACC_W-1:0] mm_stream_bias;
    wire mm_feed_ready;
    wire signed [N*N*DATA_W-1:0] mm_out;
    wire [N*N-1:0] mm_lane_valid;
    wire mm_out_valid,mm_job_last;

    axis_matmul_feeder #(.N(N),.DATA_W(DATA_W),.ACC_W(ACC_W),.AXIS_W(2*N*DATA_W)) mm_feed(
        .clk(aclk),.rst(core_rst),.feed_req(feed_req),.feed_step(feed_step),.K(K),
        .bias_stream_en(matmul_bias_en),.feed_valid(feed_valid),
        .a_left(a_left),.b_top(b_top),.bias_flat(mm_stream_bias),
        .s_axis_tdata(s_axis_tdata[2*N*DATA_W-1:0]),
        .s_axis_tvalid(s_axis_tvalid && mode_matmul),
        .s_axis_tready(mm_feed_ready)
    );
    wire mm_stream_ready = mode_matmul && mm_feed_ready;
    wire signed [N*N*ACC_W-1:0] mm_bias_effective = matmul_bias_en ? mm_stream_bias : bias_flat;

    matmul_engine #(.N(N),.DATA_W(DATA_W),.ACC_W(ACC_W)) mm(
        .clk(aclk),.rst(core_rst),.start(mm_start),.M(M),.Ndim(Ndim),.K(K),
        .tile_m(tile_m),.tile_n(tile_n),.feed_step(feed_step),.feed_req(feed_req),
        .feed_valid(feed_valid),.a_left(a_left),.b_top(b_top),.bias_flat(mm_bias_effective),
        .relu_en(relu_en),.qmul(qmul),.qshift(qshift),.zero_point(zero_point),
        .out_tile(mm_out),.out_lane_valid(mm_lane_valid),.out_tile_valid(mm_out_valid),
        .out_job_last(mm_job_last),.out_tile_ready(mm_tile_ready),
        .busy(mm_busy),.done(mm_done)
    );

    wire [AXIS_OUT_W-1:0] mm_axis_data;
    wire mm_axis_valid,mm_axis_last;
    axis_tile_output #(.N(N),.DATA_W(DATA_W),.AXIS_W(AXIS_OUT_W)) mm_out_axis(
        .clk(aclk),.rst(core_rst),.tile_valid(mm_out_valid),.tile_last(mm_job_last),
        .tile_ready(mm_tile_ready),.tile_data(mm_out),.lane_valid(mm_lane_valid),
        .m_axis_tdata(mm_axis_data),.m_axis_tvalid(mm_axis_valid),
        .m_axis_tready(m_axis_tready && mode_matmul),.m_axis_tlast(mm_axis_last),.busy(mm_axis_busy)
    );

    // ---------------- Conv stream ----------------
    wire conv_sample_valid,conv_ready,conv_last,conv_job_last;
    wire signed [DATA_W-1:0] conv_act,conv_w,conv_out;
    wire signed [31:0] conv_sample_bias;
    wire conv_out_valid,conv_out_last;

    axis_conv_adapter #(.DATA_W(DATA_W),.AXIS_W(AXIS_IN_W)) cv_feed(
        .clk(aclk),.rst(core_rst),.conv_ready(conv_ready),
        .s_axis_tdata(s_axis_tdata),.s_axis_tvalid(s_axis_tvalid && mode_conv),
        .s_axis_tlast(s_axis_tlast),.s_axis_tready(),
        .sample_valid(conv_sample_valid),.activation(conv_act),.weight(conv_w),
        .last_sample(conv_last),.job_last(conv_job_last),.sample_bias(conv_sample_bias)
    );

    conv_stream_job_engine #(.DATA_W(DATA_W),.ACC_W(ACC_W)) cv(
        .clk(aclk),.rst(core_rst),.start(cv_start),.sample_valid(conv_sample_valid),
        .activation(conv_act),.weight(conv_w),.last_sample(conv_last),.job_last(conv_job_last),
        .sample_bias(conv_sample_bias),.relu_en(relu_en),.qmul(qmul),.qshift(qshift),.zero_point(zero_point),
        .sample_ready(conv_ready),.out_data(conv_out),.out_valid(conv_out_valid),
        .out_ready(m_axis_tready && mode_conv),.out_last(conv_out_last),
        .busy(cv_busy),.done(cv_done)
    );

    // ---------------- MaxPool2x2 ----------------
    wire pool_ready,pool_out_valid,pool_out_last;
    wire signed [DATA_W-1:0] pool_out;
    axis_maxpool2x2_engine #(.DATA_W(DATA_W),.AXIS_W(AXIS_IN_W)) pool_i(
        .clk(aclk),.rst(core_rst),.start(pool_start),
        .s_axis_tdata(s_axis_tdata),.s_axis_tvalid(s_axis_tvalid && mode_pool),
        .s_axis_tlast(s_axis_tlast),.s_axis_tready(pool_ready),
        .out_data(pool_out),.out_valid(pool_out_valid),.out_ready(m_axis_tready && mode_pool),
        .out_last(pool_out_last),.busy(pool_busy),.done(pool_done)
    );

    // ---------------- Elementwise INT8 Add / residual ----------------
    wire add_ready,add_out_valid,add_out_last;
    wire signed [DATA_W-1:0] add_out;
    axis_elementwise_add_engine #(.DATA_W(DATA_W),.AXIS_W(AXIS_IN_W)) add_i(
        .clk(aclk),.rst(core_rst),.start(add_start),.relu_en(relu_en),
        .s_axis_tdata(s_axis_tdata),.s_axis_tvalid(s_axis_tvalid && mode_add),
        .s_axis_tlast(s_axis_tlast),.s_axis_tready(add_ready),
        .out_data(add_out),.out_valid(add_out_valid),.out_ready(m_axis_tready && mode_add),
        .out_last(add_out_last),.busy(add_busy),.done(add_done)
    );

    // ---------------- Shared stream mux ----------------
    assign s_axis_tready = mode_conv ? conv_ready :
                           mode_pool ? pool_ready :
                           mode_add  ? add_ready  : mm_stream_ready;

    wire [AXIS_OUT_W-1:0] cv_axis_data   = {{(AXIS_OUT_W-DATA_W){conv_out[DATA_W-1]}},conv_out};
    wire [AXIS_OUT_W-1:0] pool_axis_data = {{(AXIS_OUT_W-DATA_W){pool_out[DATA_W-1]}},pool_out};
    wire [AXIS_OUT_W-1:0] add_axis_data  = {{(AXIS_OUT_W-DATA_W){add_out[DATA_W-1]}},add_out};

    assign m_axis_tdata  = mode_conv ? cv_axis_data :
                           mode_pool ? pool_axis_data :
                           mode_add  ? add_axis_data : mm_axis_data;
    assign m_axis_tvalid = mode_conv ? conv_out_valid :
                           mode_pool ? pool_out_valid :
                           mode_add  ? add_out_valid : mm_axis_valid;
    assign m_axis_tlast  = mode_conv ? conv_out_last :
                           mode_pool ? pool_out_last :
                           mode_add  ? add_out_last : mm_axis_last;
endmodule
