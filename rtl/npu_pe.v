module npu_pe #(
    parameter DATA_W = 8,
    parameter ACC_W  = 32
)(
    input  wire                     clk,
    input  wire                     rst,
    input  wire                     clear_acc,
    input  wire                     en,
    input  wire signed [DATA_W-1:0] a_in,
    input  wire signed [DATA_W-1:0] b_in,
    output reg  signed [DATA_W-1:0] a_out,
    output reg  signed [DATA_W-1:0] b_out,
    output reg  signed [ACC_W-1:0]  acc
);
    (* use_dsp = "yes" *) wire signed [(2*DATA_W)-1:0] product;
    assign product = a_in * b_in;

    always @(posedge clk) begin
        if (rst) begin
            a_out <= 0;
            b_out <= 0;
            acc   <= 0;
        end else begin
            if (clear_acc) begin
                acc   <= 0;
                a_out <= 0;
                b_out <= 0;
            end else if (en) begin
                acc   <= acc + product;
                a_out <= a_in;
                b_out <= b_in;
            end
        end
    end
endmodule
