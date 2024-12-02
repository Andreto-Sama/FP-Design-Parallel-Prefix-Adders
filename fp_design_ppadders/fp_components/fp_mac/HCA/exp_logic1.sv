// Exponent logic module
module exp_logic #(parameter sig_width  = 23, ex_width = 8) (
    input logic [ex_width - 1:0] Ea, Eb, Ec,                        // Input exponents
    output logic [ex_width + 1:0] shift,                            // Alignment shift count
    output logic [ex_width + 1:0] sd,                               // Signed Eab - Ec
    output logic [ex_width + 1:0] max_exp,                          // Output exponent
    output logic prod_undf                                          // Product underflow flag
); 
    localparam [ex_width - 1:0] bias = 2**(ex_width - 1) - 1;
    localparam shift_bias = sig_width + 4;                          // C Mantissa initially placed shift_bias = sig_width + 4 bits left of the binary point of the  ab product

    logic [ex_width - 1:0] neg_bias;
    assign neg_bias = (-bias);

    logic [ex_width + 1:0] Eab, Et;                                     // Biased product exponent
    //assign Eab = Ea + Eb - bias;
    HCA #(.width(ex_width)) HCA1(.A(Ea), .B(Eb), .sum(Et));		//Et(temp) = Ea + Eb
    assign Eab = Et - bias;						//Eab = Ea + Eb - bias
    assign prod_undf = (signed'(Eab) < 0);

    logic sign_exp;                                                 // Sign of Eab - Ec 
    assign sd = Eab - Ec;                                        // Signed (unbiased) exponent difference
    assign sign_exp = sd[ex_width + 1];
    assign max_exp = (sign_exp) ? {2'b0, Ec} : Eab;                 // Maximum exponent selection

    logic [ex_width + 1:0] signed_shift;                            // Signed shifting amount
    assign signed_shift = sd + shift_bias;
    assign shift = (signed_shift[ex_width + 1]) ? '0 : signed_shift; // C Mantissa initially placed (sig_width + 4) bits left of the binary point of the  ab product 
endmodule
