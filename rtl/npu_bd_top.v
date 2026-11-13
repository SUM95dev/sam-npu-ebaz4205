module npu_bd_top #(
    parameter N=8,
    parameter DATA_W=8,
    parameter ACC_W=32,
    parameter AXIS_IN_W=128,
    parameter AXIS_OUT_W=32
)(
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 aclk CLK" *)
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME aclk, ASSOCIATED_BUSIF S_AXI_CTRL:S_AXIS_IN:M_AXIS_OUT, ASSOCIATED_RESET aresetn, FREQ_HZ 100000000" *)
    input  wire aclk,

    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 aresetn RST" *)
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME aresetn, POLARITY ACTIVE_LOW" *)
    input  wire aresetn,

    // AXI4-Lite control. Expose a conventional 32-bit address bus to IP Integrator;
    // the NPU register file occupies only the low 64 bytes.
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_CTRL AWADDR" *) input  wire [31:0] s_axi_ctrl_awaddr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_CTRL AWVALID" *) input  wire        s_axi_ctrl_awvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_CTRL AWREADY" *) output wire        s_axi_ctrl_awready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_CTRL WDATA" *) input  wire [31:0] s_axi_ctrl_wdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_CTRL WSTRB" *) input  wire [3:0]  s_axi_ctrl_wstrb,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_CTRL WVALID" *) input  wire        s_axi_ctrl_wvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_CTRL WREADY" *) output wire        s_axi_ctrl_wready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_CTRL BRESP" *) output wire [1:0]  s_axi_ctrl_bresp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_CTRL BVALID" *) output wire        s_axi_ctrl_bvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_CTRL BREADY" *) input  wire        s_axi_ctrl_bready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_CTRL ARADDR" *) input  wire [31:0] s_axi_ctrl_araddr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_CTRL ARVALID" *) input  wire        s_axi_ctrl_arvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_CTRL ARREADY" *) output wire        s_axi_ctrl_arready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_CTRL RDATA" *) output wire [31:0] s_axi_ctrl_rdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_CTRL RRESP" *) output wire [1:0]  s_axi_ctrl_rresp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_CTRL RVALID" *) output wire        s_axi_ctrl_rvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_CTRL RREADY" *) input  wire        s_axi_ctrl_rready,

    // DMA MM2S -> NPU
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS_IN TDATA" *)  input  wire [AXIS_IN_W-1:0] s_axis_in_tdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS_IN TKEEP" *)  input  wire [(AXIS_IN_W/8)-1:0] s_axis_in_tkeep,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS_IN TVALID" *) input  wire s_axis_in_tvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS_IN TREADY" *) output wire s_axis_in_tready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS_IN TLAST" *)  input  wire s_axis_in_tlast,

    // NPU -> DMA S2MM
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS_OUT TDATA" *)  output wire [AXIS_OUT_W-1:0] m_axis_out_tdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS_OUT TKEEP" *)  output wire [(AXIS_OUT_W/8)-1:0] m_axis_out_tkeep,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS_OUT TVALID" *) output wire m_axis_out_tvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS_OUT TREADY" *) input  wire m_axis_out_tready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS_OUT TLAST" *)  output wire m_axis_out_tlast,

    (* X_INTERFACE_INFO = "xilinx.com:signal:interrupt:1.0 irq INTERRUPT" *)
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME irq, SENSITIVITY LEVEL_HIGH" *)
    output wire irq
);
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME S_AXI_CTRL, PROTOCOL AXI4LITE, DATA_WIDTH 32, ADDR_WIDTH 32, FREQ_HZ 100000000, HAS_BURST 0, HAS_LOCK 0, HAS_CACHE 0, HAS_PROT 0, HAS_QOS 0, HAS_REGION 0" *)
    wire _axi_param_anchor = s_axi_ctrl_awvalid;

    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME S_AXIS_IN, TDATA_NUM_BYTES 16, HAS_TKEEP 1, HAS_TLAST 1, HAS_TSTRB 0, HAS_TREADY 1" *)
    wire _saxis_param_anchor = s_axis_in_tvalid;

    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME M_AXIS_OUT, TDATA_NUM_BYTES 4, HAS_TKEEP 1, HAS_TLAST 1, HAS_TSTRB 0, HAS_TREADY 1" *)
    wire _maxis_param_anchor = m_axis_out_tready;

    wire signed [N*N*ACC_W-1:0] zero_bias = {N*N*ACC_W{1'b0}};
    assign m_axis_out_tkeep = {(AXIS_OUT_W/8){1'b1}};

    // TKEEP on input is present for AXI DMA compatibility. The current packet
    // formats always use full beats, so the core intentionally ignores it.
    wire _unused_tkeep = ^s_axis_in_tkeep;

    npu_axis_system_top #(
        .N(N), .DATA_W(DATA_W), .ACC_W(ACC_W),
        .AXIS_IN_W(AXIS_IN_W), .AXIS_OUT_W(AXIS_OUT_W)
    ) core (
        .aclk(aclk), .aresetn(aresetn),
        .s_axi_awaddr(s_axi_ctrl_awaddr[5:0]),
        .s_axi_awvalid(s_axi_ctrl_awvalid), .s_axi_awready(s_axi_ctrl_awready),
        .s_axi_wdata(s_axi_ctrl_wdata), .s_axi_wstrb(s_axi_ctrl_wstrb),
        .s_axi_wvalid(s_axi_ctrl_wvalid), .s_axi_wready(s_axi_ctrl_wready),
        .s_axi_bresp(s_axi_ctrl_bresp), .s_axi_bvalid(s_axi_ctrl_bvalid), .s_axi_bready(s_axi_ctrl_bready),
        .s_axi_araddr(s_axi_ctrl_araddr[5:0]),
        .s_axi_arvalid(s_axi_ctrl_arvalid), .s_axi_arready(s_axi_ctrl_arready),
        .s_axi_rdata(s_axi_ctrl_rdata), .s_axi_rresp(s_axi_ctrl_rresp),
        .s_axi_rvalid(s_axi_ctrl_rvalid), .s_axi_rready(s_axi_ctrl_rready),
        .s_axis_tdata(s_axis_in_tdata), .s_axis_tvalid(s_axis_in_tvalid),
        .s_axis_tready(s_axis_in_tready), .s_axis_tlast(s_axis_in_tlast),
        .m_axis_tdata(m_axis_out_tdata), .m_axis_tvalid(m_axis_out_tvalid),
        .m_axis_tready(m_axis_out_tready), .m_axis_tlast(m_axis_out_tlast),
        .bias_flat(zero_bias), .irq(irq)
    );
endmodule
