// Adder module
module add #(parameter width = 74) (
    input logic [width - 1:0] in1, in2,             // Inputs
    output logic [width - 1:0] res,                 // Result
    output logic carry                              // Carry
);
    HCA #(.width(width)) HCA1(.A(in1), .B(in2), .sum({carry, res}));

    //assign {carry, res} = in1 + in2;                // Behavioral prefered because of latency and parametrization
endmodule
