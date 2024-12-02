//Square root component using operator + for the addsubs of the significand's calculation

import enum_typedefs_pkg::*;

module fp_sqrt #(parameter sig_width = 23, ex_width = 8, pipe_stages = 0) (
    input logic [sig_width + ex_width:0] a,
    input logic [2:0] round,
    input logic clk, resetn, enable,            // Clock, active low reset and enable
    output logic [sig_width + ex_width:0] z,
    output logic [7:0] status    
);

    localparam [ex_width-1:0] half_bias = (2**(ex_width-2)-1);

    logic [sig_width-1:0] a_sig;
    assign a_sig = a[sig_width-1:0];

    logic [sig_width+2:0] z_sig_nr; //z_sig not rounded
    


    // 2.Significand Calculation
    sqrt_sigcalc #(.sig_width(sig_width), .pipe_stages(pipe_stages)) sigcalcU (
        .a_sig, .a_exp_lsb(a[sig_width]), .clk, .resetn, .enable, .z_sig_nr);

    //**********************************************PIPELINE STAGE 1********************************************
    logic [ex_width:0] a1;
    round_t round1;
    generate
        if(pipe_stages == 2 || pipe_stages == 3) begin: stage1
                always_ff @(posedge clk or negedge resetn) begin : stage1_ff
                    if(!resetn) begin
                        {a1, round1} <= '0;
                    end else if(enable) begin        
                        a1 <= a[sig_width+ex_width:sig_width];
                        round1 <= round_t'(round);
                    end else begin
                        a1 <= a1;
                        round1 <= round1;
                    end
                end
        end else begin: stage1_comb
            assign a1 = a[sig_width+ex_width:sig_width];
            assign round1 = round_t'(round);
        end
    endgenerate

    //**********************************************PIPELINE STAGE 2********************************************
    logic [ex_width:0] a2;
    round_t round2;
    generate
        if(pipe_stages == 1 || pipe_stages == 3) begin: stage2
                always_ff @(posedge clk or negedge resetn) begin : stage2_ff
                    if(!resetn) begin
                        {a2, round2} <= '0;
                    end else if(enable) begin        
                        a2 <= a1;
                        round2 <= round1;
                    end else begin
                        a2 <= a2;
                        round2 <= round2;
                    end
                end
        end else begin: stage2_comb
            assign a2 = a1;
            assign round2 = round1;
        end
    endgenerate

    //**********************************************PIPELINE STAGE 3********************************************
    logic [ex_width:0] a3;
    round_t round3;
    generate
        if(pipe_stages == 2 || pipe_stages == 3) begin: stage3
                always_ff @(posedge clk or negedge resetn) begin : stage3_ff
                    if(!resetn) begin
                        {a3, round3} <= '0;
                    end else if(enable) begin        
                        a3 <= a2;
                        round3 <= round2;
                    end else begin
                        a3 <= a3;
                        round3 <= round3;
                    end
                end
        end else begin: stage3_comb
            assign a3 = a2;
            assign round3 = round2;
        end
    endgenerate

    // 4.Normalization & Rounding
    // In square root the msb of the result is always going to be 1
    // so it is already normalized
    
    logic inexact;
    logic [sig_width+1:0] z_sig_r; //z_sig rounded
    round_gs #(.sig_width(sig_width)) roundU (
        .man_gs(z_sig_nr), .sign(a3[ex_width]), .round(round3), .inexact, .result(z_sig_r));

    // 1.Exponent Calculation
    logic [ex_width-1:0] a_exp;
    logic [ex_width:0] temp_exp;
    logic [ex_width+1:0] z_exp_ov;
    assign a_exp = a3[ex_width-1:0];
    //assign temp_exp = a_exp[ex_width-1:1] + half_bias + a_exp[0]; // z_exp = a_exp/2 + bias/2 + a_exp%2.
    logic [ex_width:0] temp;
    logic trash;
    LFA #(.width(ex_width)) LFA1(.A(a_exp[ex_width-1:1]), .B(half_bias), .sum(temp));
    LFA #(.width(ex_width+1)) LFA2(.A(temp), .B(a_exp[0]), .sum({trash, temp_exp}));



    // 5.PostNormalization
    logic [sig_width-1:0] z_sig;
    assign z_sig = (z_sig_r[sig_width+1]) ? z_sig_r[sig_width:1] : z_sig_r[sig_width-1:0];
    assign z_exp_ov = (z_sig_r[sig_width+1]) ? (temp_exp+1'b1) : temp_exp;

    // 6.Exception Handling & Final Output
    // here is the check for negative input as well as the other exception checks (0s, infs etc.)
    logic zero_f, inf_f, nan_f, inexact_f;
    exception_sqrt #(.sig_width(sig_width), .ex_width(ex_width)) exceptionU (
     .a_sign(a3[ex_width]), .a_exp, .z_calc({a3[ex_width], z_exp_ov[ex_width-1:0], z_sig}), .inexact,
     .z, .zero_f(status[0]), .inf_f(status[1]), .nan_f(status[2]), .inexact_f(status[5]));

    assign status[4:3] = 2'b0; //overflow & undeflow cant happen
    assign status[7:6] = 2'b00;//reserved to zero
 endmodule
