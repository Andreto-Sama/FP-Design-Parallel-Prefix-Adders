import enum_typedefs_pkg::*; 

module fp_mult #(parameter sig_width = 23, ex_width = 8, pipe_stages = 0)(
    input logic [sig_width + ex_width:0] a, b,  // Floating-Point numbers
    input logic [2:0] round,
    input logic clk, resetn, enable,            // Clock, active low reset and enable
    output logic [sig_width + ex_width:0] z,    // a * b
    output logic [7:0] status                   // Status Flags 
);
    localparam [ex_width-1:0] bias=2**(ex_width-1)-1;

    logic [sig_width:0] Ma, Mb;                 // Mantissas including hidden bits
    logic [ex_width-1:0] Ea, Eb;                // Exponents    
    logic sa, sb;                               // Sign bits

    assign Ma = {1'b1, a[sig_width-1:0]};       // Initializations
    assign Mb = {1'b1, b[sig_width-1:0]};
    assign Ea = a[sig_width+ex_width-1:sig_width];
    assign Eb = b[sig_width+ex_width-1:sig_width];
    assign sa = a[sig_width+ex_width];
    assign sb = b[sig_width+ex_width];

// 1. Floating point number sign calculation
    logic sz;
    assign sz = sa ^ sb;

// 2. Exponent addition
    logic [ex_width+1:0] exp_sub, Eab;
    //assign exp_sub = Ea + Eb - bias;
    BKA #(.width(ex_width)) BKA1(.A(Ea), .B(Eb), .sum(Eab));
    assign exp_sub = Eab - bias;

    
// 4. Mantissa multiplication
    logic [2*sig_width+1:0] mant_mult;
    multiplier #(sig_width+1) mult(.in1(Ma),.in2(Mb),.res(mant_mult));  // assign mant_mult = Ma * Mb;

//***********************************************************************PIPELINE STAGE 1***********************************************************************
    logic [sig_width + ex_width:0] a1, b1;
    logic sz1;
    logic [ex_width+1:0] exp_sub1;
    logic [2*sig_width+1:0] mant_mult1;
    round_t round1;
    generate
        if(pipe_stages == 1 || pipe_stages == 2 || pipe_stages == 3)
            always_ff @( posedge clk or negedge resetn) begin : stage1
                if(!resetn) begin
                    {a1, b1, sz1, exp_sub1, mant_mult1, round1} <= '0;
                end else if(enable) begin
                    a1 <= a; b1 <= b;
                    sz1 <= sz;
                    exp_sub1 <= exp_sub;
                    mant_mult1 <= mant_mult;
                    round1 <= round_t'(round);
                end else begin
                    {a1, b1, sz1, exp_sub1, mant_mult1, round1} <=
                        {a1, b1, sz1, exp_sub1, mant_mult1, round1};
                end
            end
        else
            always_comb begin
                a1 = a; b1 = b;
                sz1 = sz;
                exp_sub1 = exp_sub;
                mant_mult1 = mant_mult;
                round1 = round_t'(round);
            end
    endgenerate
    
// 5. Truncation and normalization 
    logic [sig_width-1:0] mant_norm;
    logic [ex_width+1:0] exp_norm;
    logic sticky_bit, guard_bit;
    normalize_mult #(.sig_width(sig_width), .ex_width(ex_width)) norm(.exp_sub(exp_sub1), .mant_mult(mant_mult1), .sticky_bit, .guard_bit, .mant_norm, .exp_norm);

//***********************************************************************PIPELINE STAGE 2***********************************************************************
    logic [sig_width + ex_width:0] a2, b2;
    logic sz2;
    logic [sig_width-1:0] mant_norm2;
    logic [ex_width+1:0] exp_norm2;
    logic sticky_bit2, guard_bit2;
    round_t round2;
    generate
        if(pipe_stages == 2 || pipe_stages == 3)
            always_ff @( posedge clk or negedge resetn) begin : stage2
                if(!resetn) begin
                    {a2, b2, sz2, mant_norm2, exp_norm2, sticky_bit2, guard_bit2, round2} <= '0;
                end else if(enable) begin
                    a2 <= a1; b2 <= b1;
                    sz2 <= sz1;
                    mant_norm2 <= mant_norm;
                    exp_norm2 <= exp_norm;
                    sticky_bit2 <= sticky_bit; guard_bit2 <= guard_bit;
                    round2 <= round1;
                end else begin
                    {a2, b2, sz2, mant_norm2, exp_norm2, sticky_bit2, guard_bit2, round2} <=
                        {a2, b2, sz2, mant_norm2, exp_norm2, sticky_bit2, guard_bit2, round2};
                end
            end
        else
            always_comb begin
                a2 = a1; b2 = b1;
                sz2 = sz1;
                mant_norm2 = mant_norm;
                exp_norm2 = exp_norm;
                sticky_bit2 = sticky_bit; guard_bit2 = guard_bit;
                round2 = round1;
            end
    endgenerate

// 6. Rounding
    logic inexact, undf;
    logic [sig_width + 1:0] rounded_mant;
    round_mult #(.sig_width(sig_width), .ex_width(ex_width)) RND(.man_gs({1'b1, mant_norm2, guard_bit2, sticky_bit2}), .exp(exp_norm2), .sign(sz2), .round(round2), .result(rounded_mant), .inexact);

    logic [sig_width:0] post_round_mant;
    logic [ex_width + 1:0] post_round_exp;
    assign post_round_mant = (rounded_mant[sig_width + 1]) ? (rounded_mant >> 1) : rounded_mant;
    assign post_round_exp = (rounded_mant[sig_width + 1]) ? (exp_norm2 + 1'b1) : exp_norm2;
    assign undf = signed'(exp_norm2) <= 0;                                       // Underflow if final exponent <= 0

//***********************************************************************PIPELINE STAGE 3***********************************************************************
    logic [sig_width + ex_width:0] a3, b3;
    logic sz3, undf3;
    logic inexact3;
    logic [sig_width:0] post_round_mant3;
    logic [ex_width + 1:0] post_round_exp3;
    round_t round3;
    generate
        if(pipe_stages == 3)
            always_ff @( posedge clk or negedge resetn) begin : stage3
                if(!resetn) begin
                    {a3, b3, sz3, undf3, inexact3, post_round_mant3, post_round_exp3, round3} <= '0;
                end else if(enable) begin
                    a3 <= a2; b3 <= b2;
                    sz3 <= sz2;
                    undf3 <= undf;
                    inexact3 <= inexact;
                    post_round_mant3 <= post_round_mant;
                    post_round_exp3 <= post_round_exp;
                    round3 <= round2;
                end else begin
                    {a3, b3, sz3, undf3, inexact3, post_round_mant3, post_round_exp3, round3} <=
                        {a3, b3, sz3, undf3, inexact3, post_round_mant3, post_round_exp3, round3};
                end
            end
        else
            always_comb begin
                a3 = a2; b3 = b2;
                sz3 = sz2;
                undf3 = undf;
                inexact3 = inexact;
                post_round_mant3 = post_round_mant;
                post_round_exp3 = post_round_exp;
                round3 = round2;
            end
    endgenerate

// 7. Exception Handling
    logic ovf, post_undf;
    assign post_undf = signed'(post_round_exp3) <= 0;                                  // Underflow if final exponent <= 0
    assign ovf  = signed'(post_round_exp3) >= signed'({2'b0, {(ex_width){1'b1}}});     // Overflow if final exponent >= maximum exponent
    logic zero_f, inf_f, nan_f, tiny_f, huge_f, inexact_f;
    exception_mult #(.sig_width(sig_width), .ex_width(ex_width)) exc1(.a(a3[sig_width+ex_width-1:sig_width]), .b(b3[sig_width+ex_width-1:sig_width]), .z_calc({sz3, post_round_exp3[ex_width-1:0], post_round_mant3[sig_width-1:0]}), .round(round3), .ovf, .post_undf, .undf(undf3), .inexact(inexact3), .z, .zero_f, .inf_f, .nan_f, .tiny_f, .huge_f, .inexact_f);
    
// 8. Status flags Assignments
    assign status = {1'b0, 1'b0, inexact_f, huge_f, tiny_f, nan_f, inf_f, zero_f};
endmodule
