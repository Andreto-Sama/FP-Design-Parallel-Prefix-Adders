// SRT algorithm implemetation

module recip_sigcalc #(parameter sig_width = 23, pipe_stages = 0) (
    input logic [sig_width:0] d,
    input logic clk, resetn, enable,                // Clock, active low reset and enable signal
    output logic [sig_width:0] quotient,
    output logic guard_bit, round_bit, sticky_bit
);

localparam total_steps = sig_width/2 + 3 - sig_width%2; // Each step produces 2 bits of quotient, extra step for rounding (13 8 5)
localparam p3 = total_steps-2, p2 = p3 - total_steps/4 + (sig_width>10), p1 = p2 - total_steps/4 - (sig_width>10); // (Single :5 9 11 Half:2 4 6 Bfloat:1 2 3)


logic signed [sig_width+1:0] w_sum1, w_sum2, w_sum3;
logic signed [sig_width+1:0] w_carry1, w_carry2, w_carry3;
logic [sig_width:0] d1, d2, d3;
logic [2*p1+1:0] Q1, QM1;
logic [2*p2+1:0] Q2, QM2;
logic [2*p3+1:0] Q3, QM3;


logic [3:0] q [total_steps:1]; // encoded quotient (one-hot as 0:x0, 1:x1, 2:x2, -1:x4, -2:x8)
logic signed [sig_width+1:0] w_sum [total_steps-1:0]; // remainder's sum of each step
logic signed [sig_width+1:0] w_sum_shifted [total_steps-2:0]; // remainder's sum of each step shifted left by 2bits
logic signed [sig_width+1:0] w_carry [total_steps-1:0]; // remainder' carry of each step
logic signed [sig_width+1:0] w_carry_shifted [total_steps-2:0]; // remainder' carry of each step shifted left by 2bits
logic [6:0] w [total_steps-1:0]; // remainder's estimate of each step
logic signed [sig_width+1:0] qd [total_steps-2:0]; // q*d

genvar i, step;
generate
    for (i=0; i<total_steps+1; i++) begin: genStage
        logic [2*i+1:0] Q , QM;
    end

    // ---------------
    // Initial values
    // ---------------

    assign genStage[0].Q = (d[sig_width-:2]==2'b11) ? 2'b01 : 2'b10;
    assign genStage[0].QM = 2'b01;
    assign w_sum[0] =  {1'b1, {(sig_width+1){1'b0}}}-{{1'b0, d}*genStage[0].Q};
    assign w_carry[0] = 0;

    // -----------------------
    // Main calculation cycles
    // -----------------------
                   
    for (step=0; step<p1; step++) begin: nextrem_0

        assign w_sum_shifted[step] = w_sum[step] << 2;
        assign w_carry_shifted[step] = w_carry[step] << 2;

        // Instantiation of On-The-Fly-Converter
        OTFconversion #(.step(step)) OTFC( // decodes q
            .q(q[step+1]), .Q(genStage[step].Q), .QM(genStage[step].QM),
            .Qnext(genStage[step+1].Q), .QMnext(genStage[step+1].QM));

        // Instantiation of 3-2 CSA to calcuelate next W (w_sum + w_carry)
        CSA #(.width(sig_width+2)) CSA( // CSA computes next step's remainder
            .x(w_sum_shifted[step]), .y(w_carry_shifted[step]), .z(qd[step]), .u(w_sum[step+1]), .v(w_carry[step+1]));

        // Instantiation of Selection function
        selection_recip SELECT_M( // computes encoded q for next step
            .d(d[sig_width-:4]), .w(w[step]), .q(q[step+1]));

        // W's estimation
        //assign w[step] = w_sum[step][sig_width+1-:7] + w_carry[step][sig_width+1-:7];
	HCA #(.width(7)) HCA1(.A(w_sum[step][sig_width+1-:7]), .B(w_carry[step][sig_width+1-:7]), .sum(w[step]));

        // Instantiations of MUX to compute word * digit mult
        op_mux #(.d_width(sig_width+1), .qd_width(sig_width+2)) MUX41( // computes q*d
            .q(q[step+1]), .d, .qd(qd[step]));
    end 

    //------------------REGISTER 1------------------
    if(pipe_stages == 2 || pipe_stages == 3) begin: stage1
        always_ff @(posedge clk or negedge resetn) begin: stage1_ff
            if(!resetn) begin
                {d1, w_sum1, w_carry1, Q1, QM1} <= '0;
            end else if(enable) begin        
                d1 <= d;
                w_sum1 <= w_sum[p1];
                w_carry1 <= w_carry[p1];
                Q1 <= genStage[p1].Q;
                QM1 <= genStage[p1].QM;
            end else begin
                d1 <= d1;
                w_sum1 <= w_sum1;
                w_carry1 <= w_carry1;
                Q1 <= Q1;
                QM1 <= QM1;
            end
        end
    end else begin: stage1_comb
        assign d1 = d;
        assign w_sum1 = w_sum[p1];
        assign w_carry1 = w_carry[p1];
        assign Q1 = genStage[p1].Q;
        assign QM1 = genStage[p1].QM;
    end
    //----------------------------------------------  

    assign w_sum_shifted[p1] = w_sum1 << 2;
    assign w_carry_shifted[p1] = w_carry1 << 2;

    // Instantiation of On-The-Fly-Converter
    OTFconversion #(.step(p1)) OTFC1( // decodes q
        .q(q[p1+1]), .Q(Q1), .QM(QM1),
        .Qnext(genStage[p1+1].Q), .QMnext(genStage[p1+1].QM));

    // Instantiation of 3-2 CSA to calcuelate next W (w_sum + w_carry)
    CSA #(.width(sig_width+2)) CSA1( // CSA computes next step's remainder
        .x(w_sum_shifted[p1]), .y(w_carry_shifted[p1]), .z(qd[p1]), .u(w_sum[p1+1]), .v(w_carry[p1+1]));

    // Instantiation of Selection function
    selection_recip SELECT_M1( // computes encoded q for next step
        .d(d1[sig_width-:4]), .w(w[p1]), .q(q[p1+1]));

    // W's estimation
    //assign w[p1] = w_sum1[sig_width+1-:7] + w_carry1[sig_width+1-:7];
    HCA #(.width(7)) HCA2(.A(w_sum1[sig_width+1-:7]), .B(w_carry1[sig_width+1-:7]), .sum(w[p1]));

    // Instantiations of MUX to compute word * digit mult
    op_mux #(.d_width(sig_width+1), .qd_width(sig_width+2)) MUX41_1( // computes q*d
        .q(q[p1+1]), .d(d1), .qd(qd[p1]));
                   
    for (step=p1+1; step<p2; step++) begin: nextrem_1

        assign w_sum_shifted[step] = w_sum[step] << 2;
        assign w_carry_shifted[step] = w_carry[step] << 2;

        // Instantiation of On-The-Fly-Converter
        OTFconversion #(.step(step)) OTFC( // decodes q
            .q(q[step+1]), .Q(genStage[step].Q), .QM(genStage[step].QM),
            .Qnext(genStage[step+1].Q), .QMnext(genStage[step+1].QM));

        // Instantiation of 3-2 CSA to calcuelate next W (w_sum + w_carry)
        CSA #(.width(sig_width+2)) CSA( // CSA computes next step's remainder
            .x(w_sum_shifted[step]), .y(w_carry_shifted[step]), .z(qd[step]), .u(w_sum[step+1]), .v(w_carry[step+1]));

        // Instantiation of Selection function
        selection_recip SELECT_M( // computes encoded q for next step
            .d(d1[sig_width-:4]), .w(w[step]), .q(q[step+1]));

        // W's estimation
        //assign w[step] = w_sum[step][sig_width+1-:7] + w_carry[step][sig_width+1-:7];
        HCA #(.width(7)) HCA3(.A(w_sum[step][sig_width+1-:7]), .B(w_carry[step][sig_width+1-:7]), .sum(w[step]));


        // Instantiations of MUX to compute word * digit mult
        op_mux #(.d_width(sig_width+1), .qd_width(sig_width+2)) MUX41( // computes q*d
            .q(q[step+1]), .d(d1), .qd(qd[step]));
    end   

    //------------------REGISTER 2------------------
    if(pipe_stages == 1 || pipe_stages == 2 || pipe_stages == 3) begin: stage2
        always_ff @(posedge clk or negedge resetn) begin: stage2_ff
            if(!resetn) begin
                {d2, w_sum2, w_carry2, Q2, QM2} <= '0;
            end else if(enable) begin        
                d2 <= d1;
                w_sum2 <= w_sum[p2];
                w_carry2 <= w_carry[p2];
                Q2 <= genStage[p2].Q;
                QM2 <= genStage[p2].QM;
            end else begin
                d2 <= d2;
                w_sum2 <= w_sum2;
                w_carry2 <= w_carry2;
                Q2 <= Q2;
                QM2 <= QM2;
            end
        end
    end else begin: stage2_comb
        assign d2 = d1;
        assign w_sum2 = w_sum[p2];
        assign w_carry2 = w_carry[p2];
        assign Q2 = genStage[p2].Q;
        assign QM2 = genStage[p2].QM;
    end
    //----------------------------------------------  

    assign w_sum_shifted[p2] = w_sum2 << 2;
    assign w_carry_shifted[p2] = w_carry2 << 2;

    // Instantiation of On-The-Fly-Converter
    OTFconversion #(.step(p2)) OTFC2( // decodes q
        .q(q[p2+1]), .Q(Q2), .QM(QM2),
        .Qnext(genStage[p2+1].Q), .QMnext(genStage[p2+1].QM));

    // Instantiation of 3-2 CSA to calcuelate next W (w_sum + w_carry)
    CSA #(.width(sig_width+2)) CSA2( // CSA computes next step's remainder
        .x(w_sum_shifted[p2]), .y(w_carry_shifted[p2]), .z(qd[p2]), .u(w_sum[p2+1]), .v(w_carry[p2+1]));

    // Instantiation of Selection function
    selection_recip SELECT_M2( // computes encoded q for next step
        .d(d2[sig_width-:4]), .w(w[p2]), .q(q[p2+1]));

    // W's estimation
    //assign w[p2] = w_sum2[sig_width+1-:7] + w_carry2[sig_width+1-:7];
    HCA #(.width(7)) HCA4(.A(w_sum2[sig_width+1-:7]), .B(w_carry2[sig_width+1-:7]), .sum(w[p2]));

    // Instantiations of MUX to compute word * digit mult
    op_mux #(.d_width(sig_width+1), .qd_width(sig_width+2)) MUX41_2( // computes q*d
        .q(q[p2+1]), .d(d2), .qd(qd[p2]));
                   
    for (step=p2+1; step<p3; step++) begin: nextrem_2

        assign w_sum_shifted[step] = w_sum[step] << 2;
        assign w_carry_shifted[step] = w_carry[step] << 2;

        // Instantiation of On-The-Fly-Converter
        OTFconversion #(.step(step)) OTFC( // decodes q
            .q(q[step+1]), .Q(genStage[step].Q), .QM(genStage[step].QM),
            .Qnext(genStage[step+1].Q), .QMnext(genStage[step+1].QM));

        // Instantiation of 3-2 CSA to calcuelate next W (w_sum + w_carry)
        CSA #(.width(sig_width+2)) CSA( // CSA computes next step's remainder
            .x(w_sum_shifted[step]), .y(w_carry_shifted[step]), .z(qd[step]), .u(w_sum[step+1]), .v(w_carry[step+1]));

        // Instantiation of Selection function
        selection_recip SELECT_M( // computes encoded q for next step
            .d(d2[sig_width-:4]), .w(w[step]), .q(q[step+1]));

        // W's estimation
        //assign w[step] = w_sum[step][sig_width+1-:7] + w_carry[step][sig_width+1-:7];
        HCA #(.width(7)) HCA5(.A(w_sum[step][sig_width+1-:7]), .B(w_carry[step][sig_width+1-:7]), .sum(w[step]));

        // Instantiations of MUX to compute word * digit mult
        op_mux #(.d_width(sig_width+1), .qd_width(sig_width+2)) MUX41( // computes q*d
            .q(q[step+1]), .d(d2), .qd(qd[step]));
    end   

    //------------------REGISTER 3------------------
    if(pipe_stages == 3) begin: stage3
        always_ff @(posedge clk or negedge resetn) begin: stage3_ff
            if(!resetn) begin
                {d3, w_sum3, w_carry3, Q3, QM3} <= '0;
            end else if(enable) begin        
                d3 <= d2;
                w_sum3 <= w_sum[p3];
                w_carry3 <= w_carry[p3];
                Q3 <= genStage[p3].Q;
                QM3 <= genStage[p3].QM;
            end else begin
                d3 <= d3;
                w_sum3 <= w_sum3;
                w_carry3 <= w_carry3;
                Q3 <= Q3;
                QM3 <= QM3;
            end
        end
    end else begin: stage3_comb
        assign d3 = d2;
        assign w_sum3 = w_sum[p3];
        assign w_carry3 = w_carry[p3];
        assign Q3 = genStage[p3].Q;
        assign QM3 = genStage[p3].QM;
    end
    //----------------------------------------------  
    
    assign w_sum_shifted[p3] = w_sum3 << 2;
    assign w_carry_shifted[p3] = w_carry3 << 2;

    // Instantiation of On-The-Fly-Converter
    OTFconversion #(.step(p3)) OTFC3( // decodes q
        .q(q[p3+1]), .Q(Q3), .QM(QM3),
        .Qnext(genStage[p3+1].Q), .QMnext(genStage[p3+1].QM));

    // Instantiation of 3-2 CSA to calcuelate next W (w_sum + w_carry)
    CSA #(.width(sig_width+2)) CSA3( // CSA computes next step's remainder
        .x(w_sum_shifted[p3]), .y(w_carry_shifted[p3]), .z(qd[p3]), .u(w_sum[p3+1]), .v(w_carry[p3+1]));

    // Instantiation of Selection function
    selection_recip SELECT_M3( // computes encoded q for next step
        .d(d3[sig_width-:4]), .w(w[p3]), .q(q[p3+1]));

    // W's estimation
    //assign w[p3] = w_sum3[sig_width+1-:7] + w_carry3[sig_width+1-:7];
    HCA #(.width(7)) HCA6(.A(w_sum3[sig_width+1-:7]), .B(w_carry3[sig_width+1-:7]), .sum(w[p3]));

    // Instantiations of MUX to compute word * digit mult
    op_mux #(.d_width(sig_width+1), .qd_width(sig_width+2)) MUX41_3( // computes q*d
        .q(q[p3+1]), .d(d3), .qd(qd[p3]));

    for (step=p3+1; step<total_steps-1; step++) begin: nextrem_3

        assign w_sum_shifted[step] = w_sum[step] << 2;
        assign w_carry_shifted[step] = w_carry[step] << 2;

        // Instantiation of On-The-Fly-Converter
        OTFconversion #(.step(step)) OTFC( // decodes q
            .q(q[step+1]), .Q(genStage[step].Q), .QM(genStage[step].QM),
            .Qnext(genStage[step+1].Q), .QMnext(genStage[step+1].QM));

        // Instantiation of 3-2 CSA to calcuelate next W (w_sum + w_carry)
        CSA #(.width(sig_width+2)) CSA( // CSA computes next step's remainder
            .x(w_sum_shifted[step]), .y(w_carry_shifted[step]), .z(qd[step]), .u(w_sum[step+1]), .v(w_carry[step+1]));

        // Instantiation of Selection function
        selection_recip SELECT_M( // computes encoded q for next step
            .d(d2[sig_width-:4]), .w(w[step]), .q(q[step+1]));

        // W's estimation
        //assign w[step] = w_sum[step][sig_width+1-:7] + w_carry[step][sig_width+1-:7];
        HCA #(.width(7)) HCA7(.A(w_sum[step][sig_width+1-:7]), .B(w_carry[step][sig_width+1-:7]), .sum(w[step]));

        // Instantiations of MUX to compute word * digit mult
        op_mux #(.d_width(sig_width+1), .qd_width(sig_width+2)) MUX41( // computes q*d
            .q(q[step+1]), .d(d2), .qd(qd[step]));
    end

    // W's estimation
    //assign w[total_steps-1] = w_sum[total_steps-1][sig_width+1-:7] + w_carry[total_steps-1][sig_width+1-:7];
    HCA #(.width(7)) HCA8(.A(w_sum[total_steps-1][sig_width+1-:7]), .B(w_carry[total_steps-1][sig_width+1-:7]), .sum(w[total_steps-1]));

    // Instantiation of Selection function
    selection_recip SELECT_M_Final( // computes encoded q for next step
        .d(d3[sig_width-:4]), .w(w[total_steps-1]), .q(q[total_steps]));
    

    // ----------
    // Final Step
    // ----------

    logic signed [sig_width-1:0] last_w; //instead of shifting left, just skip the two MSB's 
    //assign last_w = w_sum[total_steps-1][sig_width-1:0] + w_carry[total_steps-1][sig_width-1:0];
    HCA #(.width(sig_width)) HCA9(.A(w_sum[total_steps-1][sig_width-1:0]), .B(w_carry[total_steps-1][sig_width-1:0]), .sum(last_w));

    OTFconversion #(.step(total_steps-1)) Final_OTFC( // decodes q
            .q(q[total_steps]), .Q(genStage[total_steps-1].Q), .QM(genStage[total_steps-1].QM),
            .Qnext(genStage[total_steps].Q), .QMnext(genStage[total_steps].QM));

    // decoded final quotient,  hidden bit + sig_width fraction bits + 3 rounding (grs) bits
    assign quotient = (last_w>=0) ? genStage[total_steps].Q[2*total_steps-:sig_width+1] : genStage[total_steps].QM[2*total_steps-:sig_width+1];
    assign guard_bit = (last_w>=0) ? genStage[total_steps].Q[2*total_steps+1-(sig_width+2)] : genStage[total_steps].QM[2*total_steps+1-(sig_width+2)];
    assign round_bit = (last_w>=0) ? genStage[total_steps].Q[2*total_steps+1-(sig_width+3)] : genStage[total_steps].QM[2*total_steps+1-(sig_width+3)];
    assign sticky_bit = (last_w>=0) ? genStage[total_steps].Q[2*total_steps+1-(sig_width+4):0] | (|last_w) : genStage[total_steps].QM[2*total_steps+1-(sig_width+4):0] | (|last_w);
endgenerate

endmodule
