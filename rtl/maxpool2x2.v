module maxpool2x2 #(parameter W=8)(
    input wire signed [W-1:0] a,b,c,d,
    output wire signed [W-1:0] y
);
    wire signed [W-1:0] ab,cd;
    assign ab=(a>b)?a:b;
    assign cd=(c>d)?c:d;
    assign y=(ab>cd)?ab:cd;
endmodule
