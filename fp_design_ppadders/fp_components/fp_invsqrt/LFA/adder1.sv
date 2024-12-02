// Parameterizable Adder

module adder #(parameter width = 2)(
    input logic [width-1:0] a,b,
    output logic [width-1:0] s
    );
    

    //assign s = a + b;
    logic trash;
    LFA #(.width(width)) LFA1(.A(a), .B(b), .sum({trash, s}));
endmodule
