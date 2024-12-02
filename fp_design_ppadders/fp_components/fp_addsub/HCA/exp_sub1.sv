// Exponent subtraction module
module exp_sub #(parameter ex_width = 8)(
    input logic [ex_width-1:0] Ea, Eb,          // Exponents
    output logic [ex_width:0] d,                // Absolute difference (used to align the decimal points)
    output logic [ex_width-1:0] max_exp,        // Maximum exponent (used for the representation of the result of the addition/subtraction)
    output logic sign_exp                       // Sign of Ea - Eb (0 -> positive, 1 -> negative)
);
    logic [ex_width-1:0] Ed, Ec;
    logic [ex_width:0]temp;

    always_comb begin
        sign_exp = (Eb > Ea);
        
        Ec = (sign_exp) ? (Eb) : (Ea);
        Ed = (sign_exp) ? (- Ea) : (- Eb); 

        max_exp = (sign_exp) ? Eb : Ea;          // Select maximum exponent
    end
    HCA #(.width(ex_width)) HCA1(.A(Ec), .B(Ed), .sum(temp));  // Calculate absolute difference
    assign d = {1'b0, temp[ex_width-1:0]};
endmodule
