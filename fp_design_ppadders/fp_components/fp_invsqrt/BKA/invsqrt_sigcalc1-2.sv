// SRT algorithm implemetation

module invsqrt_sigcalc #(parameter sig_width = 23, pipe_stages = 0) (
    input logic [sig_width+2:0] d,              //d is 0.sig where sig might be allready shifted by one cause of odd exp
    input logic clk, resetn, enable,            // Clock, active low reset and enable signal
    output logic [sig_width:0] quotient,
    output logic guard_bit, round_bit, sticky_bit
);
// S13 H8 B5
localparam total_steps = sig_width/2 + 3 - sig_width%2; // Each step produces 2 bits of quotient, extra step for rounding
localparam width = 2*sig_width - 3*(sig_width%2) + 10;  //official: width = 2*sig_width + sig_width%2 + 1;
                                        // S  H  B
localparam r3 = 2*(total_steps/3) + 1;  // 9  5  3
localparam r2 = r3 - total_steps/4;     // 6  3  2
localparam r1 = r2 - total_steps/4;     // 3  1  1 


logic signed [0:-signed'(width-1-2*(total_steps-1-r1))] w_sum1;
logic signed [0:-signed'(width-1-2*(total_steps-1-r2))] w_sum2;
logic signed [0:-signed'(width-1-2*(total_steps-1-r3))] w_sum3;
logic signed [0:-signed'(width-1-2*(total_steps-1-r1))] w_carry1;
logic signed [0:-signed'(width-1-2*(total_steps-1-r2))] w_carry2;
logic signed [0:-signed'(width-1-2*(total_steps-1-r3))] w_carry3;
logic signed [0:-signed'(width-1-2*(total_steps-1-r1))] D1;
logic signed [0:-signed'(width-1-2*(total_steps-1-r2))] D2;
logic signed [0:-signed'(width-1-2*(total_steps-1-r3))] D3;
logic signed [0:-signed'(width-1-2*(total_steps-1-r1))] C1;
logic signed [0:-signed'(width-1-2*(total_steps-1-r2))] C2;
logic signed [0:-signed'(width-1-2*(total_steps-1-r3))] C3;
logic [2*r1+1:0] P1, PM1;
logic [2*r2+1:0] P2, PM2;
logic [2*r3+1:0] P3, PM3;
logic [3:0] p1, p2, p3;

logic [3:0] p [total_steps:1]; // encoded quotient (one-hot as 0:x0, 1:x1, 2:x2, -1:x4, -2:x8)
logic signed [0:-9] w [total_steps-2:0]; // remainder's 7-bit estimation for select function
logic signed [0:-9] w_shifted [total_steps-2:0]; // remainder's 7-bit estimation for select function shifted left by 2 bits
logic signed [0:-10] pD_est [total_steps-2:0];
logic signed [0:-11] p2C_est [total_steps-2:0];
logic signed [0:-9] est_sum [total_steps-1:1], est_carry [total_steps-1:1];
logic signed [0:-8] w_est [total_steps-1:1];
logic signed [0:-8] D_est [total_steps-1:1];

genvar step;
generate
    for (step=0; step<total_steps+1; step++) begin: genStage_P
        logic [2*step+1:0] P , PM;
    end

    for (step=0; step<total_steps; step++) begin: genStage
        logic signed [0:-(width-1-2*(total_steps-1-step))] w_sum; // remainder of each step
        logic signed [0:-(width-1-2*(total_steps-1-step))] w_carry; // remainder of each step
        logic signed [0:-(width-1-2*(total_steps-1-step))] D; // remainder of each step
        logic signed [0:-(width-1-2*(total_steps-1-step))] C; // remainder of each step
    end
    
    for (step=0; step<total_steps-1; step++) begin: genStage_C
        logic signed [0:-(width-1-2*(total_steps-1-step))] w_sum_shifted; // remainder of each step shifted left by 2bits
        logic signed [0:-(width-1-2*(total_steps-1-step))] w_carry_shifted; // remainder of each step shifted left by 2bits
        logic signed [0:-(width-1-2*(total_steps-1-step))] pD; // p*D
        logic signed [0:-(width-1-2*(total_steps-1-step))] pC; // p*C
        logic signed [0:-(width-1-2*(total_steps-1-step))] p2C; // p^2*C
    end

    // ---------------
    // Initial values
    // ---------------

    assign genStage_P[0].P = (d[sig_width+1]) ? 2'b01 : 2'b10; // if d>=0.5 P=1 else P=2
    assign genStage_P[0].PM = 2'b01;
    assign genStage[0].w_sum = ({2'b11, {(sig_width+4){1'b0}}});
    assign genStage[0].w_carry = -({d, 3'b0} * (genStage_P[0].P**2))>>>1;
    assign genStage[0].D = {d, 3'b0} << !d[sig_width+1]; //D[0] is always 0.sig aka d * P[0]
    assign genStage[0].C = {d, 3'b0} >>> 3;

    logic [4:0] initial_D;
    assign initial_D = (genStage[0].D[-1-:5]=='h1a) ? 5'd24 : genStage[0].D[-1-:5];
    selection_inv_div SELECT_M( //computes encoded q for first step
        .d(initial_D), .w(w[0][0-:7]), .q(p[1]));

    // -----------------------
    // Main calculation cycles
    // -----------------------

    for (step=0; step<r1; step++) begin: next_rem0

        assign genStage_C[step].w_sum_shifted = genStage[step].w_sum << 2; 
        assign genStage_C[step].w_carry_shifted = genStage[step].w_carry << 2; 

        // Instatiantion of On-The-Fly-Converter
        OTFconversion #(.step(step)) OTFC( //decodes q
            .q(p[step+1]), .Q(genStage_P[step].P), .QM(genStage_P[step].PM),
            .Qnext(genStage_P[step+1].P), .QMnext(genStage_P[step+1].PM));
    
        // Instatiantion of 4-2 CSA to calcuelate next W (w_sum + w_carry)
        CSA_42_mod #(.width(width-2*(total_steps-1-step))) CSA( // next step wsum wcarry
            .in1(genStage_C[step].w_sum_shifted), .in2(genStage_C[step].w_carry_shifted),
            .in3(genStage_C[step].pD), .in4(genStage_C[step].p2C), //(-pD incorporated in mux)
            .sum(genStage[step+1].w_sum), .carry(genStage[step+1].w_carry));
        
        // Instatiantion of Ripple-Carry Adder to calculate next D
        adder_mod #(.width(width-2*(total_steps-1-step))) adder( //next step D
            .a(genStage[step].D), .b(genStage_C[step].pC),
            .s(genStage[step+1].D));

        // Next C    
        assign genStage[step+1].C = {{2{genStage[step].C[0]}}, genStage[step].C};
            
        // Instatiantions of MUXs to compute word * digit mult
        op_mux #(width-2*(total_steps-1-step), width-2*(total_steps-1-step)) MUX41_0( //computes q*D
            .q(p[step+1]), .d(genStage[step].D), .qd(genStage_C[step].pD));
        mux #(width-2*(total_steps-1-step), width-2*(total_steps-1-step)) MUX41_1( //computes q*C
            .q(p[step+1]), .d(genStage[step].C), .qd(genStage_C[step].pC));
        mux_sq #(width-2*(total_steps-1-step), width-2*(total_steps-1-step)) MUX_sq( //computes q^2*C
            .q(p[step+1]), .d(genStage[step].C), .q2d(genStage_C[step].p2C));
    end

    for (step=0; step<r1; step++) begin: next_est0

        // Instantiation of adder to calculate estimation of next step D
        adder #(.width(9)) adder_Dest (
            .a(genStage[step].D[-1-:9]), .b(genStage_C[step].pC[-1-:9]),
            .s(D_est[step+1]));
        
        // Instantiations of estimation MUXs to compute word * digit mult
        op_mux #(11, 11) MUX41_est( //computes q*D
            .q(p[step+1]), .d(genStage[step].D[0-:11]), .qd(pD_est[step]));
        mux_sq #(12, 12) MUXsq_est( //computes q^2*C
            .q(p[step+1]), .d(genStage[step].C[0-:12]), .q2d(p2C_est[step]));
        
        // W's estimation
        assign w[step] = genStage[step].w_sum[0-:10] + genStage[step].w_carry[0-:10];

        assign w_shifted[step] = w[step] << 2;

        // Instantiation of 3-2 CSA to calcuelate estimation of next W (w_sum + w_carry)
        CSA #(.width(10)) CSA_est (
            .x(w_shifted[step]), .y(pD_est[step][0-:10]), .z(p2C_est[step][0-:10]), //-pD incorporated in mux
            .u(est_sum[step+1]), .v(est_carry[step+1]));
        
        // Instantiation of adder to calculate estimation of W = sum + carry
        adder #(.width(9)) adder_west (
            .a(est_sum[step+1][0-:9]), .b(est_carry[step+1][0-:9]),
            .s(w_est[step+1]));

        // Instantiation of Selection function
        selection_inv_div SELECT_M( //computes encoded q for next step
            .d(D_est[step+1][0-:5]), .w(w_est[step+1][0-:7]), .q(p[step+2]));
    end

    //------------------REGISTER 1------------------
    if(pipe_stages == 2 || pipe_stages == 3) begin: stage1
        always_ff @(posedge clk or negedge resetn) begin: stage1_ff
            if(!resetn) begin
                {D1, C1, w_sum1, w_carry1, p1, P1, PM1} <= '0;
            end else if(enable) begin   
                D1 <= genStage[r1].D;
                C1 <= genStage[r1].C;
                w_sum1 <= genStage[r1].w_sum;
                w_carry1 <= genStage[r1].w_carry;
                p1 <= p[r1+1];
                P1 <= genStage_P[r1].P;
                PM1 <= genStage_P[r1].PM;
            end else begin
                D1 <= D1;
                C1 <= C1;
                w_sum1 <= w_sum1;
                w_carry1 <= w_carry1;
                p1 <= p1;
                P1 <= P1;
                PM1 <= PM1;
            end
        end
    end else begin: stage1_comb
        assign D1 = genStage[r1].D;
        assign C1 = genStage[r1].C;
        assign w_sum1 = genStage[r1].w_sum;
        assign w_carry1 = genStage[r1].w_carry;
        assign p1 = p[r1+1];
        assign P1 = genStage_P[r1].P;
        assign PM1 = genStage_P[r1].PM;
    end
    //----------------------------------------------
    
    assign genStage_C[r1].w_sum_shifted = w_sum1 << 2; 
    assign genStage_C[r1].w_carry_shifted = w_carry1 << 2; 

    // Instatiantion of On-The-Fly-Converter
    OTFconversion #(.step(r1)) OTFC1( //decodes q
        .q(p1), .Q(P1), .QM(PM1),
        .Qnext(genStage_P[r1+1].P), .QMnext(genStage_P[r1+1].PM));

    // Instatiantion of 4-2 CSA to calcuelate next W (w_sum + w_carry)
    CSA_42_mod #(.width(width-2*(total_steps-1-r1))) CSA1( // next step wsum wcarry
        .in1(genStage_C[r1].w_sum_shifted), .in2(genStage_C[r1].w_carry_shifted), .in3(genStage_C[r1].pD), .in4(genStage_C[r1].p2C), //(-pD incorporated in mux)
        .sum(genStage[r1+1].w_sum), .carry(genStage[r1+1].w_carry));
    
    // Instatiantion of Ripple-Carry Adder to calculate next D
    adder_mod #(.width(width-2*(total_steps-1-r1))) adder1( //next step D
        .a(D1), .b(genStage_C[r1].pC), .s(genStage[r1+1].D));

    // Next C    
    assign genStage[r1+1].C = {{2{C1[0]}}, C1}; //next step C
        
    // Instatiantions of MUXs to compute word * digit mult
    op_mux #(width-2*(total_steps-1-r1), width-2*(total_steps-1-r1)) MUX41_10( //computes q*D
        .q(p1), .d(D1), .qd(genStage_C[r1].pD));
    mux #(width-2*(total_steps-1-r1), width-2*(total_steps-1-r1)) MUX41_11( //computes q*C
        .q(p1), .d(C1), .qd(genStage_C[r1].pC));
    mux_sq #(width-2*(total_steps-1-r1), width-2*(total_steps-1-r1)) MUX_sq1( //computes q^2*C
        .q(p1), .d(C1), .q2d(genStage_C[r1].p2C));

    // Instantiation of adder to calculate estimation of next step D
    adder #(.width(9)) adder_Dest1 (
        .a(D1[-1-:9]), .b(genStage_C[r1].pC[-1-:9]),
        .s(D_est[r1+1]));
    
    // Instantiations of estimation MUXs to compute word * digit mult
    op_mux #(11, 11) MUX41_est1( //computes q*D
        .q(p1), .d(D1[0-:11]), .qd(pD_est[r1]));
    mux_sq #(12, 12) MUXsq_est1( //computes q^2*C
        .q(p1), .d(C1[0-:12]), .q2d(p2C_est[r1]));
    
    // W's estimation
    assign w[r1] = w_sum1[0-:10] + w_carry1[0-:10];

    assign w_shifted[r1] = w[r1] << 2;

    // Instantiation of 3-2 CSA to calcuelate estimation of next W (w_sum + w_carry)
    CSA #(.width(10)) CSA_est1 (
        .x(w_shifted[r1]), .y(pD_est[r1][0-:10]), .z(p2C_est[r1][0-:10]), //-pD incorporated in mux
        .u(est_sum[r1+1]), .v(est_carry[r1+1]));
    
    // Instantiation of adder to calculate estimation of W = sum + carry
    adder #(.width(9)) adder_west1 (
        .a(est_sum[r1+1][0-:9]), .b(est_carry[r1+1][0-:9]),
        .s(w_est[r1+1]));

    // Instantiation of Selection function
    selection_inv_div SELECT_M1( //computes encoded q for next step
        .d(D_est[r1+1][0-:5]), .w(w_est[r1+1][0-:7]), .q(p[r1+2]));

    for (step=r1+1; step<r2; step++) begin: next_rem1

        assign genStage_C[step].w_sum_shifted = genStage[step].w_sum << 2; 
        assign genStage_C[step].w_carry_shifted = genStage[step].w_carry << 2; 


        // Instatiantion of On-The-Fly-Converter
        OTFconversion #(.step(step)) OTFC( //decodes q
            .q(p[step+1]), .Q(genStage_P[step].P), .QM(genStage_P[step].PM),
            .Qnext(genStage_P[step+1].P), .QMnext(genStage_P[step+1].PM));
    
        // Instatiantion of 4-2 CSA to calcuelate next W (w_sum + w_carry)
        // 29 = 23+3+3 -> +2 -> ... -> 53
        CSA_42_mod #(.width(width-2*(total_steps-1-step))) CSA( // next step wsum wcarry
            .in1(genStage_C[step].w_sum_shifted), .in2(genStage_C[step].w_carry_shifted),
            .in3(genStage_C[step].pD), .in4(genStage_C[step].p2C), //(-pD incorporated in mux)
            .sum(genStage[step+1].w_sum), .carry(genStage[step+1].w_carry));
        
        // Instatiantion of Ripple-Carry Adder to calculate next D
        adder_mod #(.width(width-2*(total_steps-1-step))) adder( //next step D
            .a(genStage[step].D), .b(genStage_C[step].pC),
            .s(genStage[step+1].D));
        
        // Next C    
        assign genStage[step+1].C = {{2{genStage[step].C[0]}}, genStage[step].C}; //next step C
            
        // Instatiantions of MUXs to compute word * digit mult
        op_mux #(width-2*(total_steps-1-step), width-2*(total_steps-1-step)) MUX41_0( //computes q*D
            .q(p[step+1]), .d(genStage[step].D), .qd(genStage_C[step].pD));
        mux #(width-2*(total_steps-1-step), width-2*(total_steps-1-step)) MUX41_1( //computes q*C
            .q(p[step+1]), .d(genStage[step].C), .qd(genStage_C[step].pC));
        mux_sq #(width-2*(total_steps-1-step), width-2*(total_steps-1-step)) MUX_sq( //computes q^2*C
            .q(p[step+1]), .d(genStage[step].C), .q2d(genStage_C[step].p2C));
    end

    for (step=r1+1; step<r2; step++) begin: next_est1

        // Instantiation of adder to calculate estimation of next step D
        adder #(.width(9)) adder_Dest (
            .a(genStage[step].D[-1-:9]), .b(genStage_C[step].pC[-1-:9]),
            .s(D_est[step+1]));
        
        // Instantiations of estimation MUXs to compute word * digit mult
        op_mux #(11, 11) MUX41_est( //computes q*D
            .q(p[step+1]), .d(genStage[step].D[0-:11]), .qd(pD_est[step]));
        mux_sq #(12, 12) MUXsq_est( //computes q^2*C
            .q(p[step+1]), .d(genStage[step].C[0-:12]), .q2d(p2C_est[step]));
        
        // W's estimation
        assign w[step] = genStage[step].w_sum[0-:10] + genStage[step].w_carry[0-:10];

        assign w_shifted[step] = w[step] << 2;

        // Instantiation of 3-2 CSA to calcuelate estimation of next W (w_sum + w_carry)
        CSA #(.width(10)) CSA_est (
            .x(w_shifted[step]), .y(pD_est[step][0-:10]), .z(p2C_est[step][0-:10]), //-pD incorporated in mux
            .u(est_sum[step+1]), .v(est_carry[step+1]));
        
        // Instantiation of adder to calculate estimation of W = sum + carry
        adder #(.width(9)) adder_west (
            .a(est_sum[step+1][0-:9]), .b(est_carry[step+1][0-:9]),
            .s(w_est[step+1]));

        // Instantiation of Selection function
        selection_inv_div SELECT_M( //computes encoded q for next step
            .d(D_est[step+1][0-:5]), .w(w_est[step+1][0-:7]), .q(p[step+2]));
    end

    //------------------REGISTER 2------------------
    if(pipe_stages == 1 || pipe_stages == 3) begin: stage2
        always_ff @(posedge clk or negedge resetn) begin: stage2_ff
            if(!resetn) begin
                {D2, C2, w_sum2, w_carry2, p2, P2, PM2} <= '0;
            end else if(enable) begin   
                D2 <= genStage[r2].D;
                C2 <= genStage[r2].C;
                w_sum2 <= genStage[r2].w_sum;
                w_carry2 <= genStage[r2].w_carry;
                p2 <= p[r2+1];
                P2 <= genStage_P[r2].P;
                PM2 <= genStage_P[r2].PM;
            end else begin
                D2 <= D2;
                C2 <= C2;
                w_sum2 <= w_sum2;
                w_carry2 <= w_carry2;
                p2 <= p2;
                P2 <= P2;
                PM2 <= PM2;
            end
        end
    end else begin: stage2_comb
        assign D2 = genStage[r2].D;
        assign C2 = genStage[r2].C;
        assign w_sum2 = genStage[r2].w_sum;
        assign p2 = p[r2+1];
        assign w_carry2 = genStage[r2].w_carry;
        assign P2 = genStage_P[r2].P;
        assign PM2 = genStage_P[r2].PM;
    end
    //----------------------------------------------    
    
    assign genStage_C[r2].w_sum_shifted = w_sum2 << 2; 
    assign genStage_C[r2].w_carry_shifted = w_carry2 << 2; 


    // Instatiantion of On-The-Fly-Converter
    OTFconversion #(.step(r2)) OTFC2( //decodes q
        .q(p2), .Q(P2), .QM(PM2),
        .Qnext(genStage_P[r2+1].P), .QMnext(genStage_P[r2+1].PM));

    // Instatiantion of 4-2 CSA to calcuelate next W (w_sum + w_carry)
    CSA_42_mod #(.width(width-2*(total_steps-1-r2))) CSA2( // next step wsum wcarry
        .in1(genStage_C[r2].w_sum_shifted), .in2(genStage_C[r2].w_carry_shifted), .in3(genStage_C[r2].pD), .in4(genStage_C[r2].p2C), //(-pD incorporated in mux)
        .sum(genStage[r2+1].w_sum), .carry(genStage[r2+1].w_carry));
    
    // Instatiantion of Ripple-Carry Adder to calculate next D
    adder_mod #(.width(width-2*(total_steps-1-r2))) adder2( //next step D
        .a(D2), .b(genStage_C[r2].pC), .s(genStage[r2+1].D));

    // Next C    
    assign genStage[r2+1].C = {{2{C2[0]}}, C2}; //next step C
        
    // Instatiantions of MUXs to compute word * digit mult
    op_mux #(width-2*(total_steps-1-r2), width-2*(total_steps-1-r2)) MUX41_20( //computes q*D
        .q(p2), .d(D2), .qd(genStage_C[r2].pD));
    mux #(width-2*(total_steps-1-r2), width-2*(total_steps-1-r2)) MUX41_21( //computes q*C
        .q(p2), .d(C2), .qd(genStage_C[r2].pC));
    mux_sq #(width-2*(total_steps-1-r2), width-2*(total_steps-1-r2)) MUX_sq2( //computes q^2*C
        .q(p2), .d(C2), .q2d(genStage_C[r2].p2C));

    // Instantiation of adder to calculate estimation of next step D
    adder #(.width(9)) adder_Dest2 (
        .a(D2[-1-:9]), .b(genStage_C[r2].pC[-1-:9]),
        .s(D_est[r2+1]));
    
    // Instantiations of estimation MUXs to compute word * digit mult
    op_mux #(11, 11) MUX41_est2( //computes q*D
        .q(p2), .d(D2[0-:11]), .qd(pD_est[r2]));
    mux_sq #(12, 12) MUXsq_est2( //computes q^2*C
        .q(p2), .d(C2[0-:12]), .q2d(p2C_est[r2]));
    
    // W's estimation
    assign w[r2] = w_sum2[0-:10] + w_carry2[0-:10];

    assign w_shifted[r2] = w[r2] << 2;

    // Instantiation of 3-2 CSA to calcuelate estimation of next W (w_sum + w_carry)
    CSA #(.width(10)) CSA_est2 (
        .x(w_shifted[r2]), .y(pD_est[r2][0-:10]), .z(p2C_est[r2][0-:10]), //-pD incorporated in mux
        .u(est_sum[r2+1]), .v(est_carry[r2+1]));
    
    // Instantiation of adder to calculate estimation of W = sum + carry
    adder #(.width(9)) adder_west2 (
        .a(est_sum[r2+1][0-:9]), .b(est_carry[r2+1][0-:9]),
        .s(w_est[r2+1]));

    // Instantiation of Selection function
    selection_inv_div SELECT_M2( //computes encoded q for next step
        .d(D_est[r2+1][0-:5]), .w(w_est[r2+1][0-:7]), .q(p[r2+2]));

    for (step=r2+1; step<r3; step++) begin: next_rem2

        assign genStage_C[step].w_sum_shifted = genStage[step].w_sum << 2; 
        assign genStage_C[step].w_carry_shifted = genStage[step].w_carry << 2; 


        // Instatiantion of On-The-Fly-Converter
        OTFconversion #(.step(step)) OTFC( //decodes q
            .q(p[step+1]), .Q(genStage_P[step].P), .QM(genStage_P[step].PM),
            .Qnext(genStage_P[step+1].P), .QMnext(genStage_P[step+1].PM));
    
        // Instatiantion of 4-2 CSA to calcuelate next W (w_sum + w_carry)
        // 29 = 23+3+3 -> +2 -> ... -> 53
        CSA_42_mod #(.width(width-2*(total_steps-1-step))) CSA( // next step wsum wcarry
            .in1(genStage_C[step].w_sum_shifted), .in2(genStage_C[step].w_carry_shifted),
            .in3(genStage_C[step].pD), .in4(genStage_C[step].p2C), //(-pD incorporated in mux)
            .sum(genStage[step+1].w_sum), .carry(genStage[step+1].w_carry));
        
        // Instatiantion of Ripple-Carry Adder to calculate next D
        adder_mod #(.width(width-2*(total_steps-1-step))) adder( //next step D
            .a(genStage[step].D), .b(genStage_C[step].pC),
            .s(genStage[step+1].D));
        
        // Next C    
        assign genStage[step+1].C = {{2{genStage[step].C[0]}}, genStage[step].C}; //next step C
            
        // Instatiantions of MUXs to compute word * digit mult
        op_mux #(width-2*(total_steps-1-step), width-2*(total_steps-1-step)) MUX41_0( //computes q*D
            .q(p[step+1]), .d(genStage[step].D), .qd(genStage_C[step].pD));
        mux #(width-2*(total_steps-1-step), width-2*(total_steps-1-step)) MUX41_1( //computes q*C
            .q(p[step+1]), .d(genStage[step].C), .qd(genStage_C[step].pC));
        mux_sq #(width-2*(total_steps-1-step), width-2*(total_steps-1-step)) MUX_sq( //computes q^2*C
            .q(p[step+1]), .d(genStage[step].C), .q2d(genStage_C[step].p2C));
    end

    for (step=r2+1; step<r3; step++) begin: next_est2

        // Instantiation of adder to calculate estimation of next step D
        adder #(.width(9)) adder_Dest (
            .a(genStage[step].D[-1-:9]), .b(genStage_C[step].pC[-1-:9]),
            .s(D_est[step+1]));
        
        // Instantiations of estimation MUXs to compute word * digit mult
        op_mux #(11, 11) MUX41_est( //computes q*D
            .q(p[step+1]), .d(genStage[step].D[0-:11]), .qd(pD_est[step]));
        mux_sq #(12, 12) MUXsq_est( //computes q^2*C
            .q(p[step+1]), .d(genStage[step].C[0-:12]), .q2d(p2C_est[step]));
        
        // W's estimation
        assign w[step] = genStage[step].w_sum[0-:10] + genStage[step].w_carry[0-:10];

        assign w_shifted[step] = w[step] << 2;

        // Instantiation of 3-2 CSA to calcuelate estimation of next W (w_sum + w_carry)
        CSA #(.width(10)) CSA_est (
            .x(w_shifted[step]), .y(pD_est[step][0-:10]), .z(p2C_est[step][0-:10]), //-pD incorporated in mux
            .u(est_sum[step+1]), .v(est_carry[step+1]));
        
        // Instantiation of adder to calculate estimation of W = sum + carry
        adder #(.width(9)) adder_west (
            .a(est_sum[step+1][0-:9]), .b(est_carry[step+1][0-:9]),
            .s(w_est[step+1]));

        // Instantiation of Selection function
        selection_inv_div SELECT_M( //computes encoded q for next step
            .d(D_est[step+1][0-:5]), .w(w_est[step+1][0-:7]), .q(p[step+2]));
    end

    //------------------REGISTER 3------------------
    if(pipe_stages == 2 || pipe_stages == 3) begin: stage3
        always_ff @(posedge clk or negedge resetn) begin: stage3_ff
            if(!resetn) begin
                {D3, C3, w_sum3, w_carry3, p3, P3, PM3} <= '0;
            end else if(enable) begin   
                D3 <= genStage[r3].D;
                C3 <= genStage[r3].C;
                w_sum3 <= genStage[r3].w_sum;
                w_carry3 <= genStage[r3].w_carry;
                p3 <= p[r3+1];
                P3 <= genStage_P[r3].P;
                PM3 <= genStage_P[r3].PM;
            end else begin
                D3 <= D3;
                C3 <= C3;
                w_sum3 <= w_sum3;
                w_carry3 <= w_carry3;
                p3 <= p3;
                P3 <= P3;
                PM3 <= PM3;
            end
        end
    end else begin: stage3_comb
        assign D3 = genStage[r3].D;
        assign C3 = genStage[r3].C;
        assign w_sum3 = genStage[r3].w_sum;
        assign w_carry3 = genStage[r3].w_carry;
        assign p3 = p[r3+1];
        assign P3 = genStage_P[r3].P;
        assign PM3 = genStage_P[r3].PM;
    end
    //----------------------------------------------     
    
    assign genStage_C[r3].w_sum_shifted = w_sum3 << 2; 
    assign genStage_C[r3].w_carry_shifted = w_carry3 << 2; 


    // Instatiantion of On-The-Fly-Converter
    OTFconversion #(.step(r3)) OTFC3( //decodes q
        .q(p3), .Q(P3), .QM(PM3),
        .Qnext(genStage_P[r3+1].P), .QMnext(genStage_P[r3+1].PM));

    // Instatiantion of 4-2 CSA to calcuelate next W (w_sum + w_carry)
    CSA_42_mod #(.width(width-2*(total_steps-1-r3))) CSA3( // next step wsum wcarry
        .in1(genStage_C[r3].w_sum_shifted), .in2(genStage_C[r3].w_carry_shifted), .in3(genStage_C[r3].pD), .in4(genStage_C[r3].p2C), //(-pD incorporated in mux)
        .sum(genStage[r3+1].w_sum), .carry(genStage[r3+1].w_carry));
    
    // Instatiantion of Ripple-Carry Adder to calculate next D
    adder_mod #(.width(width-2*(total_steps-1-r3))) adder3( //next step D
        .a(D3), .b(genStage_C[r3].pC), .s(genStage[r3+1].D));

    // Next C    
    assign genStage[r3+1].C = {{2{C3[0]}}, C3}; //next step C
        
    // Instatiantions of MUXs to compute word * digit mult
    op_mux #(width-2*(total_steps-1-r3), width-2*(total_steps-1-r3)) MUX41_30( //computes q*D
        .q(p3), .d(D3), .qd(genStage_C[r3].pD));
    mux #(width-2*(total_steps-1-r3), width-2*(total_steps-1-r3)) MUX41_31( //computes q*C
        .q(p3), .d(C3), .qd(genStage_C[r3].pC));
    mux_sq #(width-2*(total_steps-1-r3), width-2*(total_steps-1-r3)) MUX_sq3( //computes q^2*C
        .q(p3), .d(C3), .q2d(genStage_C[r3].p2C));

    // Instantiation of adder to calculate estimation of next step D
    adder #(.width(9)) adder_Dest3 (
        .a(D3[-1-:9]), .b(genStage_C[r3].pC[-1-:9]),
        .s(D_est[r3+1]));
    
    // Instantiations of estimation MUXs to compute word * digit mult
    op_mux #(11, 11) MUX41_est3( //computes q*D
        .q(p3), .d(D3[0-:11]), .qd(pD_est[r3]));
    mux_sq #(12, 12) MUXsq_est( //computes q^2*C
        .q(p3), .d(C3[0-:12]), .q2d(p2C_est[r3]));
    
    // W's estimation
    assign w[r3] = w_sum3[0-:10] + w_carry3[0-:10];

    assign w_shifted[r3] = w[r3] << 2;

    // Instantiation of 3-2 CSA to calcuelate estimation of next W (w_sum + w_carry)
    CSA #(.width(10)) CSA_est3 (
        .x(w_shifted[r3]), .y(pD_est[r3][0-:10]), .z(p2C_est[r3][0-:10]), //-pD incorporated in mux
        .u(est_sum[r3+1]), .v(est_carry[r3+1]));
    
    // Instantiation of adder to calculate estimation of W = sum + carry
    adder #(.width(9)) adder_west3 (
        .a(est_sum[r3+1][0-:9]), .b(est_carry[r3+1][0-:9]),
        .s(w_est[r3+1]));

    // Instantiation of Selection function
    selection_inv_div SELECT_M3( //computes encoded q for next step
        .d(D_est[r3+1][0-:5]), .w(w_est[r3+1][0-:7]), .q(p[r3+2]));

    for (step=r3+1; step<total_steps-1; step++) begin: next_rem3

        assign genStage_C[step].w_sum_shifted = genStage[step].w_sum << 2; 
        assign genStage_C[step].w_carry_shifted = genStage[step].w_carry << 2; 

        // Instatiantion of On-The-Fly-Converter
        OTFconversion #(.step(step)) OTFC( //decodes q
            .q(p[step+1]), .Q(genStage_P[step].P), .QM(genStage_P[step].PM),
            .Qnext(genStage_P[step+1].P), .QMnext(genStage_P[step+1].PM));
    
        // Instatiantion of 4-2 CSA to calcuelate next W (w_sum + w_carry)
        // 29 = 23+3+3 -> +2 -> ... -> 53
        CSA_42_mod #(.width(width-2*(total_steps-1-step))) CSA( // next step wsum wcarry
            .in1(genStage_C[step].w_sum_shifted), .in2(genStage_C[step].w_carry_shifted),
            .in3(genStage_C[step].pD), .in4(genStage_C[step].p2C), //(-pD incorporated in mux)
            .sum(genStage[step+1].w_sum), .carry(genStage[step+1].w_carry));
        
        // Instatiantion of Ripple-Carry Adder to calculate next D
        adder_mod #(.width(width-2*(total_steps-1-step))) adder( //next step D
            .a(genStage[step].D), .b(genStage_C[step].pC),
            .s(genStage[step+1].D));
        
        // Next C    
        assign genStage[step+1].C = {{2{genStage[step].C[0]}}, genStage[step].C}; //next step C

        // Instatiantions of MUXs to compute word * digit mult
        op_mux #(width-2*(total_steps-1-step), width-2*(total_steps-1-step)) MUX41_0( //computes q*D
            .q(p[step+1]), .d(genStage[step].D), .qd(genStage_C[step].pD));
        mux #(width-2*(total_steps-1-step), width-2*(total_steps-1-step)) MUX41_1( //computes q*C
            .q(p[step+1]), .d(genStage[step].C), .qd(genStage_C[step].pC));
        mux_sq #(width-2*(total_steps-1-step), width-2*(total_steps-1-step)) MUX_sq( //computes q^2*C
            .q(p[step+1]), .d(genStage[step].C), .q2d(genStage_C[step].p2C));
    end

    for (step=r3+1; step<total_steps-1; step++) begin: next_est3

        // Instantiation of adder to calculate estimation of next step D
        adder #(.width(9)) adder_Dest (
            .a(genStage[step].D[-1-:9]), .b(genStage_C[step].pC[-1-:9]),
            .s(D_est[step+1]));
        
        // Instantiations of estimation MUXs to compute word * digit mult
        op_mux #(11, 11) MUX41_est( //computes q*D
            .q(p[step+1]), .d(genStage[step].D[0-:11]), .qd(pD_est[step]));
        mux_sq #(12, 12) MUXsq_est( //computes q^2*C
            .q(p[step+1]), .d(genStage[step].C[0-:12]), .q2d(p2C_est[step]));
        
        // W's estimation
        assign w[step] = genStage[step].w_sum[0-:10] + genStage[step].w_carry[0-:10];

        assign w_shifted[step] = w[step] << 2;

        // Instantiation of 3-2 CSA to calcuelate estimation of next W (w_sum + w_carry)
        CSA #(.width(10)) CSA_est (
            .x(w_shifted[step]), .y(pD_est[step][0-:10]), .z(p2C_est[step][0-:10]), //-pD incorporated in mux
            .u(est_sum[step+1]), .v(est_carry[step+1]));
        
        // Instantiation of adder to calculate estimation of W = sum + carry
        adder #(.width(9)) adder_west (
            .a(est_sum[step+1][0-:9]), .b(est_carry[step+1][0-:9]),
            .s(w_est[step+1]));

        // Instantiation of Selection function
        selection_inv_div SELECT_M( //computes encoded q for next step
            .d(D_est[step+1][0-:5]), .w(w_est[step+1][0-:7]), .q(p[step+2]));
    end

    // ----------
    // Final Step
    // ----------

    logic signed [width-1:0] last_w;
    logic [2*total_steps:0] correct_quotient;
    //assign last_w = (genStage[total_steps-1].w_sum) + (genStage[total_steps-1].w_carry);
    //assign w[total_steps-1] = last_w[width-1-:7];
    BKA #(.width(width)) BKA1(.A(genStage[total_steps-1].w_sum), .B(genStage[total_steps-1].w_carry), .sum(last_w));

    OTFconversion #(.step(total_steps-1)) Final_OTFC( //decodes q
        .q(p[total_steps]), .Q(genStage_P[total_steps-1].P), .QM(genStage_P[total_steps-1].PM),
        .Qnext(genStage_P[total_steps].P), .QMnext(genStage_P[total_steps].PM));

    // correct quotient based on the sign of the last remainder 
    assign correct_quotient = (!last_w[width-1]) ? genStage_P[total_steps].P[2*total_steps:0] : genStage_P[total_steps].PM[2*total_steps:0];

    // decoded final quotient w/ hidden bit + 3 rounding (grs) bits
    assign quotient = correct_quotient[2*total_steps-:sig_width+1];
    assign guard_bit = correct_quotient[2*total_steps+1-(sig_width+2)];
    assign round_bit = correct_quotient[2*total_steps+1-(sig_width+3)];
    assign sticky_bit = correct_quotient[2*total_steps+1-(sig_width+4):0] | (|last_w);

endgenerate 
endmodule
