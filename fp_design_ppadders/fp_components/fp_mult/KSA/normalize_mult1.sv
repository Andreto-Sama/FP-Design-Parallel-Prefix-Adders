module normalize_mult #(parameter sig_width=23, ex_width=8) (
    input logic [2*sig_width+1:0] mant_mult,
    input logic [ex_width+1:0] exp_sub,
    output logic sticky_bit, guard_bit,
    output logic [sig_width-1:0] mant_norm,
    output logic [ex_width+1:0] exp_norm 
);
    logic count; // Instead of leading zero counter result (0 and 1 are the only values possible for multiplication)
    assign count = ~(mant_mult[2*sig_width+1]); // 0 leading zeros if MSB is 1, 1 leading 0 if MSB 0 

    logic [ex_width+1:0] exp_plusone;

 
    KSA #(.width(ex_width+2)) KSA1(.A(exp_sub), .B(1'b1), .sum(exp_plusone));  
    
    always_comb begin
        exp_norm = count? exp_sub : exp_plusone;
        //exp_norm = count? exp_sub : exp_sub + 1'b1;

                               
        if (~count) begin 
            mant_norm = mant_mult[2*sig_width:sig_width+1]; 
            guard_bit = mant_mult[sig_width];
            sticky_bit = |mant_mult[sig_width-1:0];
        end
        else begin
            mant_norm = mant_mult[2*sig_width-1:sig_width];
            guard_bit = mant_mult[sig_width-1];
            sticky_bit = |mant_mult[sig_width-2:0];
        end 
    end
    
endmodule
