//Significand calculation for square root
//Uses the Non-Restoring algorithm

module sqrt_sigcalc #(parameter sig_width = 23, pipe_stages=0) (
    input logic [sig_width-1:0] a_sig,
    input logic a_exp_lsb,
    input logic clk, resetn, enable,
    output logic [sig_width+2:0] z_sig_nr
    );
                                                         // S    H    B
    localparam width = sig_width+1;                      // 24   11   8
    localparam p3 = width - width/6 - (sig_width>10);    // 19   10   7
    localparam p2 = p3 - int'($ceil(real'(width)/10));   // 17   8    6
    localparam p1 = p2 - int'($ceil(real'(width)/5));    // 12   5    4

    //helpfull nets among module
    logic [2*(width+1)-1:0] d; //expanded signidicand, to be used in the computation of quotient
    logic [width:0] q; //quotient aka sqrt result, stores the inv. of msb of the result of each adder

    //nets for pipelining
    logic [2*width-2*(p1+1)+1:0] d1in, d1out;
    logic [2*width-2*(p2+1)+1:0] d2in, d2out;
    logic [2*width-2*(p3+1)+1:0] d3in, d3out;

    logic [width:width-p1] q1in, q1out;
    logic [width:width-p2] q2in, q2out;
    logic [width:width-p3] q3in, q3out;
    logic [p1+1:0] r1in, r1out;
    logic [p2+1:0] r2in, r2out;
    logic [p3+1:0] r3in, r3out;

    // Significand Preprocessing
    //zero filling significand to 2*(sig_width+1)-bits so the result is (sig_width+1)-bits
    //where +1 represents the hidden bit 1
    //shifting significand when exponent (a_exp) is odd to make the exponent even
    assign d = {1'b1, a_sig, {(width+2){1'b0}}} >> a_exp_lsb;

    // Quotient Calculation (Square root result)
    genvar k;
    generate
        for (k=0; k<width+1; k++) begin: genStage //remainder stores the result of each adder
            logic [k+1:0] r;
        end
        //optimized first step
        //could further optimize as first and second MSBs of d are always gonna be 01 or 1x
        //meaning msb of q is always 1 (or gate bellow). So no need for normalization
        assign q1in[width] = d[2*(width+1)-1] | d[2*(width+1)-2];
        assign genStage[0].r[1:0] = {~(d[2*(width+1)-1] ^ d[2*(width+1)-2]), ~d[2*(width+1)-2]};


        //following adders start from 4+4 bits and are scaled to (width+4)+(width+4) bits.
        //LHS (of +) includes the remainder of previous step (result of pev adder).
        //RHS (of +) includes the quotient appended with the required digits (as the algorithm states),
        //subtraction for q=1 and addition for q=0.
        //tl;dr: if resulting q of prev adder is 1 then complement second input b: {1'b0, q[23:23-k], ~q[23-k], 1'b1}.
        //the resulting sum is then stored in the remainder array 
        logic temp_rem_msb; //skipping for step=1 cause always q[width]=1 (see line 43) 
        assign {temp_rem_msb, genStage[1].r} = {genStage[0].r[1:0], d[2*width-1 -: 2]} - {~q1in[width], q1in[width], ~q1in[width], q1in[width]};
        assign q1in[width-1] = !temp_rem_msb;

        for (k=2; k<p1+1; k++) begin: next_rem0
            rem_calc #(.q_width(k), .r_width(k+1)) rem_calc (
                .q_in(q1in[width:width-k+1]), .r_in(genStage[k-1].r[k:0]), .d(d[2*width-2*k+1 -: 2]),
                .q_out(q1in[width-k]), .r_out(genStage[k].r)
            );
        end

        assign d1in = d[2*width-2*(p1+1)+1:0];
        assign r1in = genStage[p1].r;

        //------------------REGISTER 1------------------
        if(pipe_stages == 2 || pipe_stages == 3) begin: stage1
            always_ff @(posedge clk or negedge resetn) begin: stage1_ff
                if(!resetn) begin
                    {r1out, q1out, d1out} <= '0;
                end else if(enable) begin        
                    d1out <= d1in;
                    q1out <= q1in;
                    r1out <= r1in;
                end else begin
                    d1out <= d1out;
                    q1out <= q1out;
                    r1out <= r1out;
                end
            end
        end else begin: stage1_comb
            assign d1out = d1in;
            assign q1out = q1in;
            assign r1out = r1in;
        end
        //----------------------------------------------
        assign q2in[width:width-p1] = q1out;

        rem_calc #(.q_width(p1+1), .r_width(p1+2)) rem_calc_1 (
                .q_in(q2in[width:width-p1]), .r_in(r1out), .d(d1out[2*width-2*(p1+1)+1 -: 2]),
                .q_out(q2in[width-(p1+1)]), .r_out(genStage[p1+1].r)
            ); 

        for (k=p1+2; k<p2+1; k++) begin: next_rem1
            rem_calc #(.q_width(k), .r_width(k+1)) rem_calc (
                .q_in(q2in[width:width-k+1]), .r_in(genStage[k-1].r[k:0]), .d(d1out[2*width-2*k+1 -: 2]),
                .q_out(q2in[width-k]), .r_out(genStage[k].r)
            );
        end

        assign d2in = d1out[2*width-2*(p2+1)+1:0];
        assign r2in = genStage[p2].r;

        //------------------REGISTER 2------------------
        if(pipe_stages == 1 || pipe_stages == 3) begin: stage2
            always_ff @(posedge clk or negedge resetn) begin : stage2_ff
                if(!resetn) begin
                    {r2out, q2out, d2out} <= '0;
                end else if(enable) begin        
                    d2out <= d2in;
                    q2out <= q2in;
                    r2out <= r2in;
                end else begin
                    d2out <= d2out;
                    q2out <= q2out;
                    r2out <= r2out;
                end
            end
        end else begin: stage2_comb
            assign d2out = d2in;
            assign q2out = q2in;
            assign r2out = r2in;
        end
        //----------------------------------------------
        assign q3in[width:width-p2] = q2out;
 
        rem_calc #(.q_width(p2+1), .r_width(p2+2)) rem_calc_2 (
                .q_in(q3in[width:width-p2]), .r_in(r2out), .d(d2out[2*width-2*(p2+1)+1 -: 2]),
                .q_out(q3in[width-(p2+1)]), .r_out(genStage[p2+1].r)
            ); 

        for (k=p2+2; k<p3+1; k++) begin: next_rem2
            rem_calc #(.q_width(k), .r_width(k+1)) rem_calc (
                .q_in(q3in[width:width-k+1]), .r_in(genStage[k-1].r[k:0]), .d(d2out[2*width-2*k+1 -: 2]),
                .q_out(q3in[width-k]), .r_out(genStage[k].r)
            );
        end

        assign d3in = d2out[2*width-2*(p3+1)+1:0];
        assign r3in = genStage[p3].r;

        //------------------REGISTER 3------------------
        if(pipe_stages == 2 || pipe_stages == 3) begin: stage3
            always_ff @(posedge clk or negedge resetn) begin : stage3_ff
                if(!resetn) begin
                    {r3out, q3out, d3out} <= '0;
                end else if(enable) begin        
                    d3out <= d3in;
                    q3out <= q3in;
                    r3out <= r3in;
                end else begin
                    d3out <= d3out;
                    q3out <= q3out;
                    r3out <= r3out;
                end
            end
        end else begin: stage3_comb
            assign d3out = d3in;
            assign q3out = q3in;
            assign r3out = r3in;
        end
        //----------------------------------------------
        assign q[width:width-p3] = q3out;

        rem_calc #(.q_width(p3+1), .r_width(p3+2)) rem_calc_3 (
                .q_in(q[width:width-p3]), .r_in(r3out), .d(d3out[2*width-2*(p3+1)+1 -: 2]),
                .q_out(q[width-(p3+1)]), .r_out(genStage[p3+1].r)
            ); 

        for (k=p3+2; k<width+1; k++) begin: next_rem3
            rem_calc #(.q_width(k), .r_width(k+1)) rem_calc (
                .q_in(q[width:width-k+1]), .r_in(genStage[k-1].r[k:0]), .d(d3out[2*width-2*k+1 -: 2]),
                .q_out(q[width-k]), .r_out(genStage[k].r)
            ); 
        end
    
        // To get the exact last remainder extra addition is needed iff last remainder is negative
        logic [width+1:0] last_r;
        //assign last_r = (q[0]) ? genStage[width].r[width+1:0] : genStage[width].r[width+1:0] + {q, 1'b1}; //or ... : ... + {q, !q[0]}
	logic [width+1:0] temp;
        KSA #(.width(width+2)) KSA1(.A(genStage[width].r[width+1:0]), .B({q, 1'b1}), .sum(temp));
        assign last_r = (q[0]) ? genStage[width].r[width+1:0] : temp; //or ... : ... + {q, !q[0]}

        //contains result w/ hidden bit and guard, sticky bit for rounding
        assign z_sig_nr = {q, |last_r};
    endgenerate
endmodule
