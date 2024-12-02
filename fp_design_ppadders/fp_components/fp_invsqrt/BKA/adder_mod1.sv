// Parameterizable Adder slightly modified so the output is 2 bits wider

module adder_mod #(parameter width = 2)(
    input logic [width-1:0] a,b,
    output logic [width+1:0] s
    );
    
    //assign s = {a + b, 2'b00};
    logic [width-1:0] temp;
    logic trash;
    BKA #(.width(width)) BKA1(.A(a), .B(b), .sum({trash, temp}));
    
    assign s = {temp, 2'b00};
endmodule
