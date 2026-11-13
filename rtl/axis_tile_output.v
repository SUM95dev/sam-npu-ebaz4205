module axis_tile_output #(
    parameter N=8,
    parameter DATA_W=8,
    parameter AXIS_W=32
)(
    input  wire clk,
    input  wire rst,
    input  wire tile_valid,
    input  wire tile_last,
    output wire tile_ready,
    input  wire signed [N*N*DATA_W-1:0] tile_data,
    input  wire [N*N-1:0] lane_valid,
    output reg  [AXIS_W-1:0] m_axis_tdata,
    output reg  m_axis_tvalid,
    input  wire m_axis_tready,
    output reg  m_axis_tlast,
    output reg  busy
);
    localparam LANES=N*N;
    localparam IDX_W=(LANES<=2)?1:$clog2(LANES);
    reg [IDX_W-1:0] idx;
    reg [IDX_W-1:0] last_valid_idx;
    reg signed [N*N*DATA_W-1:0] tile_hold;
    reg [N*N-1:0] mask_hold;
    reg tile_last_hold;
    integer k;

    assign tile_ready = !busy;

    function [IDX_W-1:0] find_last_valid;
        input [LANES-1:0] mask;
        integer j;
        begin
            find_last_valid=0;
            for(j=0;j<LANES;j=j+1)
                if(mask[j]) find_last_valid=j[IDX_W-1:0];
        end
    endfunction

    task load_lane;
        input [IDX_W-1:0] lane;
        begin
            m_axis_tdata <= {{(AXIS_W-DATA_W){tile_hold[lane*DATA_W+DATA_W-1]}},
                              tile_hold[lane*DATA_W +: DATA_W]};
            m_axis_tvalid <= 1'b1;
            m_axis_tlast <= tile_last_hold && (lane==last_valid_idx);
        end
    endtask

    always @(posedge clk) begin
        if(rst) begin
            idx<=0; last_valid_idx<=0; tile_hold<=0; mask_hold<=0; tile_last_hold<=0;
            m_axis_tdata<=0; m_axis_tvalid<=0; m_axis_tlast<=0; busy<=0;
        end else begin
            if(tile_valid && tile_ready) begin
                tile_hold<=tile_data;
                mask_hold<=lane_valid;
                tile_last_hold<=tile_last;
                last_valid_idx<=find_last_valid(lane_valid);
                idx<=0;
                busy<=|lane_valid;
                m_axis_tvalid<=0;
                m_axis_tlast<=0;
            end else if(busy) begin
                if(m_axis_tvalid) begin
                    if(m_axis_tready) begin
                        if(idx==last_valid_idx) begin
                            m_axis_tvalid<=0;
                            m_axis_tlast<=0;
                            busy<=0;
                        end else begin
                            idx<=idx+1'b1;
                            m_axis_tvalid<=0;
                            m_axis_tlast<=0;
                        end
                    end
                end else begin
                    if(mask_hold[idx]) begin
                        load_lane(idx);
                    end else if(idx==last_valid_idx) begin
                        busy<=0;
                    end else begin
                        idx<=idx+1'b1;
                    end
                end
            end
        end
    end
endmodule
