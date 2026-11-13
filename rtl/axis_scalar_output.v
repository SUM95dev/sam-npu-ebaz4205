module axis_scalar_output #(
    parameter DATA_W=8,
    parameter AXIS_W=32
)(
    input  wire clk,
    input  wire rst,
    input  wire signed [DATA_W-1:0] in_data,
    input  wire in_valid,
    output wire in_ready,
    output reg  [AXIS_W-1:0] m_axis_tdata,
    output reg               m_axis_tvalid,
    input  wire              m_axis_tready,
    output reg               m_axis_tlast
);
    assign in_ready = !m_axis_tvalid || m_axis_tready;

    always @(posedge clk) begin
        if (rst) begin
            m_axis_tdata <= 0;
            m_axis_tvalid <= 0;
            m_axis_tlast <= 0;
        end else begin
            if (m_axis_tvalid && m_axis_tready)
                m_axis_tvalid <= 0;

            if (in_valid && in_ready) begin
                m_axis_tdata <= {{(AXIS_W-DATA_W){in_data[DATA_W-1]}},in_data};
                m_axis_tvalid <= 1;
                m_axis_tlast <= 1; // one scalar per packet for simple DMA mode
            end
        end
    end
endmodule
