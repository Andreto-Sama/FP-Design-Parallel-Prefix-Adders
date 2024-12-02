// Adder-Subtractor module (Calculates addition/subtraction of significands)
module addsub #(parameter width = 27) (
    input logic [width - 1:0] in1, in2,             // Inputs
    input logic eop,                                // Effective operation
    output logic [width - 1:0] res,                 // Result
    output logic carry, sign_sub                    // Carry & sign of subtraction
);
    
    logic [width - 1:0] sum;
    logic [width - 1:0] in3;
    assign sign_sub = (in2 > in1);
    assign in3 = (eop) ? (-in2) : (in2);
    KSA #(.width(width)) KSA1(.A(in1), .B(in3), .sum({carry, sum}));
    assign res = (eop && sign_sub) ? (-sum) : sum;
endmodule

