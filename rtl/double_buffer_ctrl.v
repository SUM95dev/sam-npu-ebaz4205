module double_buffer_ctrl(
    input wire clk,
    input wire rst,
    input wire start,
    input wire load_done,
    input wire compute_done,
    input wire no_more_tiles,
    output reg load_bank,
    output reg compute_bank,
    output reg load_start,
    output reg compute_start,
    output reg busy,
    output reg done
);
    localparam S_IDLE=2'd0,S_PRIME=2'd1,S_RUN=2'd2,S_DRAIN=2'd3;
    reg [1:0] state;
    reg loaded_pending;
    reg compute_active;
    reg final_pending;

    always @(posedge clk) begin
        if (rst) begin
            state<=S_IDLE; load_bank<=0; compute_bank<=0;
            load_start<=0; compute_start<=0; busy<=0; done<=0;
            loaded_pending<=0; compute_active<=0; final_pending<=0;
        end else begin
            load_start<=0; compute_start<=0; done<=0;

            case(state)
                S_IDLE: begin
                    busy<=0;
                    if(start) begin
                        busy<=1; load_bank<=0; loaded_pending<=0;
                        compute_active<=0; final_pending<=0;
                        load_start<=1; state<=S_PRIME;
                    end
                end

                S_PRIME: begin
                    if(load_done) begin
                        compute_bank<=load_bank; compute_start<=1; compute_active<=1;
                        if(no_more_tiles) begin
                            final_pending<=1; state<=S_DRAIN;
                        end else begin
                            load_bank<=~load_bank; load_start<=1; state<=S_RUN;
                        end
                    end
                end

                S_RUN: begin
                    // Compute may finish before the next load.
                    if(compute_done)
                        compute_active<=0;

                    // A loaded bank can be consumed immediately if compute is idle,
                    // or remembered until the current compute finishes.
                    if(load_done) begin
                        if(!compute_active || compute_done) begin
                            compute_bank<=load_bank; compute_start<=1; compute_active<=1;
                            if(no_more_tiles) begin
                                final_pending<=1; state<=S_DRAIN;
                            end else begin
                                load_bank<=~load_bank; load_start<=1;
                            end
                        end else begin
                            loaded_pending<=1;
                            if(no_more_tiles) final_pending<=1;
                        end
                    end else if(compute_done && loaded_pending) begin
                        compute_bank<=load_bank; compute_start<=1; compute_active<=1;
                        loaded_pending<=0;
                        if(final_pending) begin
                            state<=S_DRAIN;
                        end else begin
                            load_bank<=~load_bank; load_start<=1;
                        end
                    end
                end

                S_DRAIN: begin
                    if(compute_done) begin
                        compute_active<=0; busy<=0; done<=1; state<=S_IDLE;
                    end
                end
                default: begin
                    state<=S_IDLE; busy<=0; loaded_pending<=0;
                    compute_active<=0; final_pending<=0;
                end
            endcase
        end
    end
endmodule
