module npu_regs #(
    parameter integer ARRAY_N = 8,
    parameter integer DATA_W = 8,
    parameter integer ACC_W = 32
)(
    input  wire clk,
    input  wire rst,
    input  wire wr_en,
    input  wire [5:0] wr_addr,
    input  wire [31:0] wr_data,
    input  wire [3:0] wr_strb,
    input  wire rd_en,
    input  wire [5:0] rd_addr,
    output reg  [31:0] rd_data,
    input  wire busy,
    input  wire done_pulse,
    output reg  start_pulse,
    output reg  mode_conv,
    output reg  mode_pool,
    output reg  mode_add,
    output reg  matmul_bias_en,
    output reg  [15:0] M,
    output reg  [15:0] Ndim,
    output reg  [15:0] K,
    output reg  relu_en,
    output reg  signed [31:0] qmul,
    output reg  [5:0] qshift,
    output reg  signed [7:0] zero_point,
    output reg  abort_pulse,
    output wire irq
);
    // Register map (32-bit words, 64-byte aperture):
    // 0x00 CONTROL/STATUS: W bit0=start, bits[3:1]={add,pool,conv}, bit4=MatMul bias stream;
    //                      R bit0=busy, bit1=done, bit2=cfg_error, bit3=irq
    // 0x04 M, 0x08 N, 0x0C K, 0x10 RELU
    // 0x14 COMMAND/IRQ: bit0 irq_en, W1C bit1 done, W1C bit2 cfg_error,
    //                   pulse bit3 perf_clear, pulse bit4 abort
    // 0x18 QMUL, 0x1C QSHIFT, 0x20 ZERO_POINT
    // 0x24 VERSION, 0x28 CAPABILITIES
    // 0x2C TOTAL_CYCLES, 0x30 BUSY_CYCLES, 0x34 JOB_COUNT,
    // 0x38 ERROR_COUNT, 0x3C LAST_JOB_CYCLES
    localparam [31:0] VERSION = 32'h0002_0000; // v2.0 register/API revision

    reg done_sticky;
    reg config_error_sticky;
    reg irq_en;
    reg [31:0] total_cycles;
    reg [31:0] busy_cycles;
    reg [31:0] job_count;
    reg [31:0] error_count;
    reg [31:0] current_job_cycles;
    reg [31:0] last_job_cycles;

    function [31:0] merge_wstrb;
        input [31:0] oldv;
        input [31:0] newv;
        input [3:0] strb;
        integer bi;
        begin
            merge_wstrb = oldv;
            for (bi=0; bi<4; bi=bi+1)
                if (strb[bi]) merge_wstrb[bi*8 +: 8] = newv[bi*8 +: 8];
        end
    endfunction

    wire [31:0] m_merged = merge_wstrb({16'd0,M},wr_data,wr_strb);
    wire [31:0] n_merged = merge_wstrb({16'd0,Ndim},wr_data,wr_strb);
    wire [31:0] k_merged = merge_wstrb({16'd0,K},wr_data,wr_strb);
    wire [31:0] qmul_merged = merge_wstrb(qmul,wr_data,wr_strb);

    // Lock configuration immediately after a START is accepted. The engine's
    // busy signal rises one clock later, so busy alone leaves a one-cycle race.
    wire cfg_locked = busy || start_pulse;
    wire control_write = wr_en && wr_strb[0] && !cfg_locked && (wr_addr[5:2] == 4'h0);
    wire command_write = wr_en && wr_strb[0] && (wr_addr[5:2] == 4'h5);
    wire start_requested = control_write && wr_data[0];
    wire requested_conv = wr_data[1];
    wire requested_pool = wr_data[2];
    wire requested_add  = wr_data[3];
    wire mode_invalid = (requested_conv && requested_pool) ||
                        (requested_conv && requested_add)  ||
                        (requested_pool && requested_add);
    wire non_matmul_mode = requested_conv || requested_pool || requested_add;
    wire matmul_dims_valid = (M != 0) && (Ndim != 0) && (K != 0);
    wire start_valid = start_requested && !mode_invalid && (non_matmul_mode || matmul_dims_valid);
    wire start_invalid = start_requested && (mode_invalid || (!non_matmul_mode && !matmul_dims_valid));
    wire perf_clear_cmd = command_write && wr_data[3];
    wire abort_cmd = command_write && wr_data[4];

    assign irq = irq_en && done_sticky;

    always @(posedge clk) begin
        if (rst) begin
            start_pulse<=0; mode_conv<=0; mode_pool<=0; mode_add<=0; matmul_bias_en<=0;
            M<=0; Ndim<=0; K<=0;
            relu_en<=1; qmul<=1; qshift<=0; zero_point<=0;
            done_sticky<=0; config_error_sticky<=0; irq_en<=0; abort_pulse<=0;
            total_cycles<=0; busy_cycles<=0; job_count<=0; error_count<=0;
            current_job_cycles<=0; last_job_cycles<=0;
        end else begin
            start_pulse<=0;
            abort_pulse<=0;

            // Performance accounting. Clear is intentionally accepted even while
            // busy so software can delimit measurements without resetting the core.
            if (perf_clear_cmd) begin
                total_cycles<=0; busy_cycles<=0; job_count<=0; error_count<=0;
                current_job_cycles<=0; last_job_cycles<=0;
            end else begin
                total_cycles <= total_cycles + 1'b1;
                if (busy) begin
                    busy_cycles <= busy_cycles + 1'b1;
                    current_job_cycles <= current_job_cycles + 1'b1;
                end
                if (done_pulse) begin
                    job_count <= job_count + 1'b1;
                    last_job_cycles <= current_job_cycles + (busy ? 1'b1 : 1'b0);
                    current_job_cycles <= 0;
                end
                if (start_valid)
                    current_job_cycles <= 0;
                if (start_invalid)
                    error_count <= error_count + 1'b1;
                if (abort_cmd)
                    current_job_cycles <= 0;
            end

            if (done_pulse)
                done_sticky<=1;

            if (start_valid) begin
                done_sticky<=0;
                config_error_sticky<=0;
            end else if (start_invalid) begin
                config_error_sticky<=1;
            end

            // Command register is deliberately writable while BUSY so a stalled
            // DMA/job can be aborted and the sticky completion/error flags acked.
            if (command_write) begin
                irq_en <= wr_data[0];
                if (wr_data[1]) done_sticky <= 0;
                if (wr_data[2]) config_error_sticky <= 0;
                if (wr_data[4]) begin
                    abort_pulse <= 1;
                    done_sticky <= 0;
                end
            end

            if (wr_en && !cfg_locked) begin
                case (wr_addr[5:2])
                    4'h0: if (wr_strb[0]) begin
                        mode_conv<=wr_data[1];
                        mode_pool<=wr_data[2];
                        mode_add<=wr_data[3];
                        matmul_bias_en<=wr_data[4];
                        start_pulse<=start_valid;
                    end
                    4'h1: M<=m_merged[15:0];
                    4'h2: Ndim<=n_merged[15:0];
                    4'h3: K<=k_merged[15:0];
                    4'h4: if (wr_strb[0]) relu_en<=wr_data[0];
                    4'h6: qmul<=qmul_merged;
                    4'h7: if (wr_strb[0]) qshift<=wr_data[5:0];
                    4'h8: if (wr_strb[0]) zero_point<=wr_data[7:0];
                    default: ;
                endcase
            end
        end
    end

    localparam [7:0] ARRAY_N_U8 = ARRAY_N;
    localparam [7:0] DATA_W_U8 = DATA_W;
    localparam [7:0] ACC_W_U8 = ACC_W;
    wire [31:0] capabilities = {ACC_W_U8, DATA_W_U8, ARRAY_N_U8, 8'hFF};

    always @* begin
        rd_data=0;
        if (rd_en) begin
            case (rd_addr[5:2])
                4'h0: rd_data={28'd0,irq,config_error_sticky,done_sticky,busy};
                4'h1: rd_data={16'd0,M};
                4'h2: rd_data={16'd0,Ndim};
                4'h3: rd_data={16'd0,K};
                4'h4: rd_data={31'd0,relu_en};
                4'h5: rd_data={31'd0,irq_en};
                4'h6: rd_data=qmul;
                4'h7: rd_data={26'd0,qshift};
                4'h8: rd_data={{24{zero_point[7]}},zero_point};
                4'h9: rd_data=VERSION;
                4'hA: rd_data=capabilities;
                4'hB: rd_data=total_cycles;
                4'hC: rd_data=busy_cycles;
                4'hD: rd_data=job_count;
                4'hE: rd_data=error_count;
                4'hF: rd_data=last_job_cycles;
                default: rd_data=0;
            endcase
        end
    end
endmodule
