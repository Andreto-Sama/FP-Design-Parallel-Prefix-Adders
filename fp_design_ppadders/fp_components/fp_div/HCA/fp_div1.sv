import enum_typedefs_pkg::*; 

module fp_div #(parameter sig_width = 23, ex_width = 8, pipe_stages = 0)(
    input logic [sig_width + ex_width:0] a, b,  // Floating-Point numbers
    input logic [2:0] round,
    input logic clk, resetn, enable,            // Clock, active low reset and enable signal
    output logic [sig_width + ex_width:0] z,    // a / b
    output logic [7:0] status                   // Status Flags 
);
    localparam [ex_width-1:0] bias=2**(ex_width-1)-1;

    logic [sig_width:0] Ma, Mb;                 // Mantissas including hidden bits
    assign Ma = {1'b1, a[sig_width-1:0]};       // Initializations
    assign Mb = {1'b1, b[sig_width-1:0]};

// 1. Mantissa division
    logic [sig_width:0] mant_div;
    logic sticky_bit, guard_bit, round_bit,count;    
    div_sigcalc #(.sig_width(sig_width), .pipe_stages(pipe_stages)) div(
        .x(Ma), .d(Mb), .clk, .resetn, .enable, .quotient(mant_div), .sticky_bit, .round_bit, .guard_bit, .count);

    //**********************************************PIPELINE STAGE 1********************************************
    logic [sig_width + ex_width:0] a1, b1;
    round_t round1;
    generate
        if(pipe_stages == 2 || pipe_stages == 3) begin : pipe_stage_1
                always_ff @(posedge clk or negedge resetn) begin : stage1
                    if(!resetn) begin
                        {a1, b1, round1} <= '0;
                    end else if(enable) begin        
                        a1 <= a;
                        b1 <= b;
                        round1 <= round_t'(round);
                    end else begin
                        a1 <= a1;
                        b1 <= b1;
                        round1 <= round1;
                    end
                end
        end else begin
            assign a1 = a;
            assign b1 = b;
            assign round1 = round_t'(round);
        end
    endgenerate

    //**********************************************PIPELINE STAGE 2********************************************
    logic [sig_width + ex_width:0] a2, b2;
    round_t round2;
    generate
        if(pipe_stages == 1 || pipe_stages == 3) begin : pipe_stage_2
                always_ff @(posedge clk or negedge resetn) begin : stage2
                    if(!resetn) begin
                        {a2, b2, round2} <= '0;
                    end else if(enable) begin        
                        a2 <= a1;
                        b2 <= b1;
                        round2 <= round1;
                    end else begin
                        a2 <= a2;
                        b2 <= b2;
                        round2 <= round2;
                    end
                end
        end else begin
            assign a2 = a1;
            assign b2 = b1;
            assign round2 = round1;
        end
    endgenerate

    //**********************************************PIPELINE STAGE 3********************************************
    logic [sig_width + ex_width:0] a3, b3;
    round_t round3;
    generate
        if(pipe_stages == 2 || pipe_stages == 3) begin : pipe_stage_3
                always_ff @(posedge clk or negedge resetn) begin : stage3
                    if(!resetn) begin
                        {a3, b3, round3} <= '0;
                    end else if(enable) begin        
                        a3 <= a2;
                        b3 <= b2;
                        round3 <= round2;
                    end else begin
                        a3 <= a3;
                        b3 <= b3;
                        round3 <= round3;
                    end
                end
        end else begin
            assign a3 = a2;
            assign b3 = b2;
            assign round3 = round2;
        end
    endgenerate

    logic [ex_width-1:0] Ea, Eb;                // Exponents    
    logic sa, sb;                               // Sign bits
    assign Ea = a3[sig_width+ex_width-1:sig_width];
    assign Eb = b3[sig_width+ex_width-1:sig_width];
    assign sa = a3[sig_width+ex_width];
    assign sb = b3[sig_width+ex_width];

// 2. Floating point number sign calculation
    logic sign_exp;
    assign sign_exp=sa^sb;

// 3. Exponent subtraction
    logic [ex_width+1:0] exp_add, expected;
    //assign exp_add = Ea - Eb + bias - count;
    //assign expected = Ea - Eb + bias - count;
    logic [ex_width+1:0] ta, tb;
    HCA #(.width(ex_width)) HCA1(.A(Ea), .B(bias), .sum(ta));
    assign tb = ta - Eb;
    assign exp_add = tb - count;
   

    
// 4. Rounding
    logic inexact;
    logic [sig_width + 1:0] rounded_q;
    round_mac_div #(.sig_width(sig_width), .ex_width(ex_width)) rnd(
        .man_grs({mant_div,guard_bit,round_bit,sticky_bit}), .exp(exp_add), .sign(sign_exp), .round(round3), .result(rounded_q), .inexact);
        
// 5. Exception Handling
    logic ovf, undf, zero_f, inf_f, huge_f, tiny_f, inexact_f, nan_f, divz_f;
    assign ovf  = signed'(exp_add) >= signed'({2'b0, {(ex_width){1'b1}}}); // Overflow if final exponent >= maximum exponent
    assign undf = signed'(exp_add) <= 0;
    
    exception_div #(.sig_width(sig_width),.ex_width(ex_width)) exc1(
        .a(a3), .b(b3), .z_calc({sign_exp,exp_add[ex_width-1:0],rounded_q[sig_width-1:0]}),.round(round3),
        .ovf, .undf, .inexact, .inexact_f, .z, .zero_f, .tiny_f, .huge_f, .inf_f, .nan_f, .divz_f);       

// 6. Output assignments
    assign status={divz_f, 1'b0, inexact_f, huge_f, tiny_f, nan_f, inf_f, zero_f}; 
endmodule
