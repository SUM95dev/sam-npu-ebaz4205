module systolic_array #(
    parameter N      = 8,
    parameter DATA_W = 8,
    parameter ACC_W  = 32
)(
    input  wire clk,
    input  wire rst,
    input  wire clear_acc,
    input  wire en,
    input  wire signed [N*DATA_W-1:0] a_left,
    input  wire signed [N*DATA_W-1:0] b_top,
    output wire signed [N*N*ACC_W-1:0] acc_flat
);
    wire signed [N*(N+1)*DATA_W-1:0] a_pipe;
    wire signed [(N+1)*N*DATA_W-1:0] b_pipe;

    genvar r,c;
    generate
        for (r=0; r<N; r=r+1) begin : GEN_A_IN
            assign a_pipe[((r*(N+1))+1)*DATA_W-1 -: DATA_W]
                 = a_left[(r+1)*DATA_W-1 -: DATA_W];
        end
        for (c=0; c<N; c=c+1) begin : GEN_B_IN
            assign b_pipe[(c+1)*DATA_W-1 -: DATA_W]
                 = b_top[(c+1)*DATA_W-1 -: DATA_W];
        end

        for (r=0; r<N; r=r+1) begin : GEN_ROW
            for (c=0; c<N; c=c+1) begin : GEN_COL
                wire signed [DATA_W-1:0] a_i,b_i,a_o,b_o;
                wire signed [ACC_W-1:0] acc_i;
                assign a_i = a_pipe[((r*(N+1)+c)+1)*DATA_W-1 -: DATA_W];
                assign b_i = b_pipe[((r*N+c)+1)*DATA_W-1 -: DATA_W];

                npu_pe #(.DATA_W(DATA_W),.ACC_W(ACC_W)) u_pe(
                    .clk(clk),.rst(rst),.clear_acc(clear_acc),.en(en),
                    .a_in(a_i),.b_in(b_i),.a_out(a_o),.b_out(b_o),.acc(acc_i)
                );

                assign a_pipe[((r*(N+1)+c+1)+1)*DATA_W-1 -: DATA_W] = a_o;
                assign b_pipe[((((r+1)*N)+c)+1)*DATA_W-1 -: DATA_W] = b_o;
                assign acc_flat[((r*N+c)+1)*ACC_W-1 -: ACC_W] = acc_i;
            end
        end
    endgenerate
endmodule
