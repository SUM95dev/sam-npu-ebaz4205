module npu_axi_lite_slave #(
    parameter ADDR_W = 6
)(
    input  wire                 aclk,
    input  wire                 aresetn,
    input  wire [ADDR_W-1:0]    s_axi_awaddr,
    input  wire                 s_axi_awvalid,
    output reg                  s_axi_awready,
    input  wire [31:0]          s_axi_wdata,
    input  wire [3:0]           s_axi_wstrb,
    input  wire                 s_axi_wvalid,
    output reg                  s_axi_wready,
    output reg  [1:0]           s_axi_bresp,
    output reg                  s_axi_bvalid,
    input  wire                 s_axi_bready,
    input  wire [ADDR_W-1:0]    s_axi_araddr,
    input  wire                 s_axi_arvalid,
    output reg                  s_axi_arready,
    output reg  [31:0]          s_axi_rdata,
    output reg  [1:0]           s_axi_rresp,
    output reg                  s_axi_rvalid,
    input  wire                 s_axi_rready,
    output reg                  reg_wr,
    output reg  [ADDR_W-1:0]    reg_waddr,
    output reg  [31:0]          reg_wdata,
    output reg  [3:0]           reg_wstrb,
    output reg                  reg_rd,
    output reg  [ADDR_W-1:0]    reg_raddr,
    input  wire [31:0]          reg_rdata
);
    reg [ADDR_W-1:0] awaddr_hold;
    reg aw_hold_valid;
    reg [31:0] wdata_hold;
    reg [3:0] wstrb_hold;
    reg w_hold_valid;
    reg read_pending;
    integer i;

    always @(posedge aclk) begin
        if (!aresetn) begin
            s_axi_awready<=0; s_axi_wready<=0; s_axi_bresp<=0; s_axi_bvalid<=0;
            s_axi_arready<=0; s_axi_rdata<=0; s_axi_rresp<=0; s_axi_rvalid<=0;
            awaddr_hold<=0; aw_hold_valid<=0; wdata_hold<=0; wstrb_hold<=0; w_hold_valid<=0;
            read_pending<=0; reg_wr<=0; reg_waddr<=0; reg_wdata<=0; reg_wstrb<=0; reg_rd<=0; reg_raddr<=0;
        end else begin
            s_axi_awready<=0; s_axi_wready<=0; s_axi_arready<=0; reg_wr<=0; reg_wstrb<=0; reg_rd<=0;

            if (!aw_hold_valid && s_axi_awvalid && !s_axi_bvalid) begin
                s_axi_awready<=1;
                awaddr_hold<=s_axi_awaddr;
                aw_hold_valid<=1;
            end
            if (!w_hold_valid && s_axi_wvalid && !s_axi_bvalid) begin
                s_axi_wready<=1;
                wdata_hold<=s_axi_wdata;
                wstrb_hold<=s_axi_wstrb;
                w_hold_valid<=1;
            end
            if (aw_hold_valid && w_hold_valid && !s_axi_bvalid) begin
                reg_waddr<=awaddr_hold;
                reg_wdata<=wdata_hold;
                reg_wstrb<=wstrb_hold;
                reg_wr<=1;
                aw_hold_valid<=0;
                w_hold_valid<=0;
                s_axi_bresp<=2'b00;
                s_axi_bvalid<=1;
            end
            if (s_axi_bvalid && s_axi_bready)
                s_axi_bvalid<=0;

            // Two-step read: latch address/request first, capture combinational
            // register data on the following clock. This avoids returning the old address.
            if (!s_axi_rvalid && !read_pending && s_axi_arvalid) begin
                s_axi_arready<=1;
                reg_raddr<=s_axi_araddr;
                reg_rd<=1;
                read_pending<=1;
            end else if (read_pending) begin
                reg_rd<=1;
                s_axi_rdata<=reg_rdata;
                s_axi_rresp<=2'b00;
                s_axi_rvalid<=1;
                read_pending<=0;
            end
            if (s_axi_rvalid && s_axi_rready)
                s_axi_rvalid<=0;
        end
    end
endmodule
