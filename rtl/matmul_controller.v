module matmul_controller #(
    parameter N = 8
)(
    input  wire clk,
    input  wire rst,
    input  wire start,
    input  wire [15:0] M,
    input  wire [15:0] Ndim,
    input  wire [15:0] K,

    output reg  [15:0] tile_m,
    output reg  [15:0] tile_n,
    output reg  [16:0] feed_step,
    output reg         feed_req,
    input  wire        feed_valid,

    output reg  clear_acc,
    output reg  flush_en,
    output reg  post_start,
    input  wire post_done,
    input  wire output_ready,
    output reg  output_valid,
    output reg  output_last,
    output reg  busy,
    output reg  done
);
    localparam S_IDLE   = 3'd0;
    localparam S_CLEAR  = 3'd1;
    localparam S_FEED   = 3'd2;
    localparam S_FLUSH  = 3'd3;
    localparam S_POST   = 3'd4;
    localparam S_OUTPUT = 3'd5;
    localparam S_NEXT   = 3'd6;

    reg [2:0] state;
    reg [16:0] accepted;
    reg [15:0] flush_count;
    reg [15:0] m_tiles_latched;
    reg [15:0] n_tiles_latched;
    reg [16:0] feed_cycles_latched;

    wire [31:0] m_ceil_wide = {16'd0,M} + N - 1;
    wire [31:0] n_ceil_wide = {16'd0,Ndim} + N - 1;
    wire [15:0] m_tiles_calc = m_ceil_wide / N;
    wire [15:0] n_tiles_calc = n_ceil_wide / N;
    wire [16:0] feed_cycles_calc = {1'b0,K} + N - 1;
    wire feed_accept = feed_req && feed_valid;

    always @(posedge clk) begin
        if (rst) begin
            state<=S_IDLE; tile_m<=0; tile_n<=0; feed_step<=0;
            feed_req<=0; clear_acc<=0; flush_en<=0; post_start<=0;
            output_valid<=0; output_last<=0; busy<=0; done<=0; accepted<=0; flush_count<=0;
            m_tiles_latched<=0; n_tiles_latched<=0; feed_cycles_latched<=0;
        end else begin
            feed_req<=0; clear_acc<=0; post_start<=0; output_valid<=0; output_last<=0; done<=0;

            case (state)
                S_IDLE: begin
                    flush_en<=0; busy<=0;
                    if (start && M!=0 && Ndim!=0 && K!=0) begin
                        busy<=1; tile_m<=0; tile_n<=0;
                        m_tiles_latched<=m_tiles_calc;
                        n_tiles_latched<=n_tiles_calc;
                        feed_cycles_latched<=feed_cycles_calc;
                        state<=S_CLEAR;
                    end
                end

                S_CLEAR: begin
                    clear_acc<=1; flush_en<=0;
                    accepted<=0; flush_count<=0; feed_step<=0;
                    state<=S_FEED;
                end

                S_FEED: begin
                    flush_en<=0;
                    feed_req<=1;
                    if (feed_accept) begin
                        if (accepted + 1 >= feed_cycles_latched) begin
                            accepted<=accepted+1'b1;
                            feed_req<=0;
                            flush_count<=0;
                            // Pre-assert flush_en so the array sees the first
                            // zero-flush on the very next clock edge.  Without
                            // this, a registered flush_en loses one drain cycle.
                            if (N > 1)
                                flush_en<=1;
                            state<=S_FLUSH;
                        end else begin
                            accepted<=accepted+1'b1;
                            feed_step<=accepted+1'b1;
                        end
                    end
                end

                S_FLUSH: begin
                    if (N <= 1) begin
                        flush_en<=0;
                        post_start<=1;
                        state<=S_POST;
                    end else if (flush_count + 1 >= N-1) begin
                        // flush_en is still high *before* this edge, so the
                        // systolic array consumes the final required zero beat.
                        flush_en<=0;
                        post_start<=1;
                        state<=S_POST;
                    end else begin
                        flush_en<=1;
                        flush_count<=flush_count+1'b1;
                    end
                end

                S_POST: begin
                    flush_en<=0;
                    if (post_done)
                        state<=S_OUTPUT;
                end

                S_OUTPUT: begin
                    output_valid<=1;
                    output_last<=((tile_m + 1 >= m_tiles_latched) && (tile_n + 1 >= n_tiles_latched));
                    if (output_ready)
                        state<=S_NEXT;
                end

                S_NEXT: begin
                    if (tile_n + 1 < n_tiles_latched) begin
                        tile_n<=tile_n+1'b1;
                        state<=S_CLEAR;
                    end else if (tile_m + 1 < m_tiles_latched) begin
                        tile_n<=0;
                        tile_m<=tile_m+1'b1;
                        state<=S_CLEAR;
                    end else begin
                        busy<=0; done<=1; state<=S_IDLE;
                    end
                end
                default: begin
                    state<=S_IDLE; busy<=0; flush_en<=0; feed_req<=0;
                    clear_acc<=0; post_start<=0; output_valid<=0;
                end
            endcase
        end
    end
endmodule
