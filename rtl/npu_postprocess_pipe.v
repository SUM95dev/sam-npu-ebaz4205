// Six-stage, one-input-per-cycle equivalent of npu_postprocess (ACC_W=32).
// Split 33x32 multiplication into DSP-sized products; register both adder levels.
module npu_postprocess_pipe #(
    parameter ACC_W=32, OUT_W=8
)(
    input wire clk, rst, in_valid,
    input wire signed [ACC_W-1:0] acc_in, bias_in,
    input wire relu_en,
    input wire signed [31:0] multiplier,
    input wire [5:0] shift,
    input wire signed [OUT_W-1:0] zero_point,
    output wire out_valid,
    output reg signed [OUT_W-1:0] out
);
    localparam BW=ACC_W+1, HW=BW-16, SW=BW+32;
    reg [5:0] valid_pipe;
    reg signed [BW-1:0] biased;
    reg signed [31:0] mul;
    reg signed [33:0] ll;
    reg signed [32:0] lh;
    reg signed [HW+16:0] hl;
    reg signed [HW+15:0] hh;
    reg signed [SW-1:0] pair_lo,pair_hi,scaled,shifted;
    reg [5:0] shifts[0:4];
    reg relus[0:4];
    reg signed [OUT_W-1:0] zps[0:4];
    wire signed [16:0] alo={1'b0,biased[15:0]};
    wire signed [HW-1:0] ahi=biased[BW-1:16];
    wire signed [16:0] blo={1'b0,mul[15:0]};
    wire signed [15:0] bhi=mul[31:16];
    wire signed [SW-1:0] ll_ext={{(SW-34){ll[33]}},ll};
    wire signed [SW-1:0] lh_ext={{(SW-33){lh[32]}},lh};
    wire signed [SW-1:0] hl_ext={{(SW-HW-17){hl[HW+16]}},hl};
    wire signed [SW-1:0] hh_ext={{(SW-HW-16){hh[HW+15]}},hh};
    wire signed [SW-1:0] activated=(relus[4] && shifted<0) ? 0 : shifted;
    wire signed [SW-1:0] result=activated+{{(SW-OUT_W){zps[4][OUT_W-1]}},zps[4]};
    localparam signed [SW-1:0] MAXV=(1 << (OUT_W-1))-1;
    localparam signed [SW-1:0] MINV=-(1 << (OUT_W-1));
    assign out_valid=valid_pipe[5];
    integer i;
    always @(posedge clk) begin
        if(rst) begin
            valid_pipe<=0;biased<=0;mul<=0;ll<=0;lh<=0;hl<=0;hh<=0;
            pair_lo<=0;pair_hi<=0;scaled<=0;shifted<=0;out<=0;
            for(i=0;i<5;i=i+1) begin shifts[i]<=0;relus[i]<=0;zps[i]<=0;end
        end else begin
            valid_pipe<={valid_pipe[4:0],in_valid};
            shifts[0]<=shift;relus[0]<=relu_en;zps[0]<=zero_point;
            for(i=1;i<5;i=i+1) begin
                shifts[i]<=shifts[i-1];relus[i]<=relus[i-1];zps[i]<=zps[i-1];
            end
            biased<=$signed({acc_in[ACC_W-1],acc_in})+$signed({bias_in[ACC_W-1],bias_in});
            mul<=multiplier;
            ll<=alo*blo;lh<=alo*bhi;hl<=ahi*blo;hh<=ahi*bhi;
            pair_lo<=ll_ext+(lh_ext <<< 16);
            pair_hi<=(hl_ext <<< 16)+(hh_ext <<< 32);
            scaled<=pair_lo+pair_hi;
            shifted<=scaled >>> shifts[3];
            if(result>MAXV) out<=MAXV[OUT_W-1:0];
            else if(result<MINV) out<=MINV[OUT_W-1:0];
            else out<=result[OUT_W-1:0];
        end
    end
endmodule
