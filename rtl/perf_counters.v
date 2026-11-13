module perf_counters(
    input wire clk,input wire rst,input wire clear,
    input wire busy,input wire pe_active,input wire mem_stall,input wire tile_done,
    output reg [63:0] busy_cycles,active_cycles,stall_cycles,tile_count
);
    always @(posedge clk) begin
        if(rst||clear) begin busy_cycles<=0;active_cycles<=0;stall_cycles<=0;tile_count<=0; end
        else begin
            if(busy) busy_cycles<=busy_cycles+1'b1;
            if(pe_active) active_cycles<=active_cycles+1'b1;
            if(mem_stall) stall_cycles<=stall_cycles+1'b1;
            if(tile_done) tile_count<=tile_count+1'b1;
        end
    end
endmodule
