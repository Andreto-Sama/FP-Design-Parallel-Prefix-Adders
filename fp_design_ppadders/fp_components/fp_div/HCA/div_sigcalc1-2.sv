module div_sigcalc #(parameter sig_width = 23, pipe_stages = 0) (
    input logic [sig_width:0] x, d,
    input logic clk, resetn, enable,            // Clock, active low reset and enable signal
    output logic [sig_width:0] quotient,
    output logic sticky_bit, guard_bit, round_bit, count
);
    localparam total_steps = sig_width/2 + 3 + sig_width%2; // Each step produces 2 bits of quotient, extra step for rounding //15 8 7
    localparam width = 2*(sig_width+1) + (sig_width+1)%2 - 3 - 3*(sig_width>7);        
    localparam r3 = total_steps - int'($ceil(real'(total_steps)/5)); // 12 6 5
    localparam r2 = r3 - int'($ceil(real'(total_steps)/4));          // 8  4 3
    localparam r1 = r2 - int'($ceil(real'(total_steps)/4));          // 4  2 1

    logic [width-1:0] w_sum1, w_sum2, w_sum3;
    logic [width-1:0] w_carry1, w_carry2, w_carry3;
    logic [width-1:0] D1, D2, D3;
    logic [2*r1+1:0] P1, PM1;
    logic [2*r2+1:0] P2, PM2;
    logic [2*r3+1:0] P3, PM3;

    logic [2*total_steps-2:0] med_quotient;
    logic [6:0] w [total_steps-1:0]; // remainder's 7-bit estimation for select function
    logic [3:0] p [total_steps:1]; // encoded quotient (one-hot as 0:x0, 1:x1, 2:x2, -1:x4, -2:x8)
    logic [width-1:0] w_sum [total_steps-1:0]; // remainder of each step
    logic [width-1:0] w_carry [total_steps-1:0]; // remainder of each step
    logic [width-1:0] D;
    logic [width-1:0] pD [total_steps-2:0]; // p*D

    genvar step;
    generate
        for (step=0; step<total_steps+1; step++) begin: genStage
            logic [2*step+1:0] P , PM;
        end

        assign genStage[0].P =  2'b00; // if d>=0.5 P=1 else P=2
        assign genStage[0].PM = 2'b00;
        assign w_sum[0] = {x, {(width-sig_width-1){1'b0}}}>>3 ;
        assign w_carry[0] = '0;
        assign D = {d, {(width-sig_width-1){1'b0}}}>>1;

        for (step=0; step<r1; step++) begin : next_rem1

            // Instatiation of On-The-Fly-Converter
            OTFconversion #(.step(step)) OTFC( //decodes q
                .q(p[step+1]), .Q(genStage[step].P), .QM(genStage[step].PM),
                .Qnext(genStage[step+1].P), .QMnext(genStage[step+1].PM));
        
            // Instatiation of 4-2 CSA to calculate next W (w_sum + w_carry)
            CSA #(.width(width)) CSA(
                .x(w_sum[step]<<2), .y(w_carry[step]<<2), .z(pD[step]), .u(w_sum[step+1]), .v(w_carry[step+1]));
            
            // Instatiantion of Selection function
            selection_inv_div SELECTMOD( //computes encoded q for next step
                .d(D[width-2-:5]), .w(w[step]), .q(p[step+1]));

            // Instatiantions of MUXs to compute word * digit mult
            op_mux #(width,width) MUX41_0( //computes q*D
                .q(p[step+1]), .d(D), .qd(pD[step]));
            
            // W's estimation
            assign w[step] = w_sum[step][width-1-:7] + w_carry[step][width-1-:7];
        end

        //------------------REGISTER 1------------------
        if(pipe_stages == 2 || pipe_stages == 3) begin : pipestage1
            always_ff @(posedge clk or negedge resetn) begin : stage1
                if(!resetn) begin
                    {D1, w_sum1, w_carry1, P1, PM1} <= '0;
                end else if(enable) begin   
                    D1 <= D;
                    w_sum1 <= w_sum[r1];
                    w_carry1 <= w_carry[r1];
                    P1 <= genStage[r1].P;
                    PM1 <= genStage[r1].PM;
                end else begin
                    D1 <= D1;
                    w_sum1 <= w_sum1;
                    w_carry1 <= w_carry1;
                    P1 <= P1;
                    PM1 <= PM1;
                end
            end
        end else begin
            assign D1 = D;
            assign w_sum1 = w_sum[r1];
            assign w_carry1 = w_carry[r1];
            assign P1 = genStage[r1].P;
            assign PM1 = genStage[r1].PM;
        end
        //----------------------------------------------

        // Instantiation of On-The-Fly-Converter
        OTFconversion #(.step(r1)) OTFC1( //decodes q
            .q(p[r1+1]), .Q(P1), .QM(PM1),
            .Qnext(genStage[r1+1].P), .QMnext(genStage[r1+1].PM));
    
        // Instantiation of 4-2 CSA to calcuelate next W (w_sum + w_carry)
        CSA #(.width(width)) CSA1(
            .x(w_sum1<<2), .y(w_carry1<<2), .z(pD[r1]), .u(w_sum[r1+1]), .v(w_carry[r1+1]));
        
        // Instantiation of Selection function
        selection_inv_div SELECT1( //computes encoded q for next step
            .d(D1[width-2-:5]), .w(w[r1]), .q(p[r1+1]));

        // Instantiations of MUXs to compute word * digit mult
        op_mux #(width,width) MUX41_1( //computes q*D
            .q(p[r1+1]), .d(D1), .qd(pD[r1]));
        
        // W's estimation
        assign w[r1] = w_sum1[width-1-:7] + w_carry1[width-1-:7];

        for (step=r1+1; step<r2; step++) begin : next_rem2

            // Instatiation of On-The-Fly-Converter
            OTFconversion #(.step(step)) OTFC( //decodes q
                .q(p[step+1]), .Q(genStage[step].P), .QM(genStage[step].PM),
                .Qnext(genStage[step+1].P), .QMnext(genStage[step+1].PM));
        
            // Instatiation of 4-2 CSA to calculate next W (w_sum + w_carry)
            CSA #(.width(width)) CSA(
                .x(w_sum[step]<<2), .y(w_carry[step]<<2), .z(pD[step]), .u(w_sum[step+1]), .v(w_carry[step+1]));
            
            // Instatiantion of Selection function
            selection_inv_div SELECTMOD( //computes encoded q for next step
                .d(D1[width-2-:5]), .w(w[step]), .q(p[step+1]));

            // Instatiantions of MUXs to compute word * digit mult
            op_mux #(width,width) MUX41_0( //computes q*D
                .q(p[step+1]), .d(D1), .qd(pD[step]));
            
            // W's estimation
            assign w[step] = w_sum[step][width-1-:7] + w_carry[step][width-1-:7];
        end

        //------------------REGISTER 2------------------
        if(pipe_stages == 1 || pipe_stages == 3) begin : pipestage2
            always_ff @(posedge clk or negedge resetn) begin : stage2
                if(!resetn) begin
                    {D2, w_sum2, w_carry2, P2, PM2} <= '0;
                end else if(enable) begin   
                    D2 <= D1;
                    w_sum2 <= w_sum[r2];
                    w_carry2 <= w_carry[r2];
                    P2 <= genStage[r2].P;
                    PM2 <= genStage[r2].PM;
                end else begin
                    D2 <= D2;
                    w_sum2 <= w_sum2;
                    w_carry2 <= w_carry2;
                    P2 <= P2;
                    PM2 <= PM2;
                end
            end
        end else begin
            assign D2 = D1;
            assign w_sum2 = w_sum[r2];
            assign w_carry2 = w_carry[r2];
            assign P2 = genStage[r2].P;
            assign PM2 = genStage[r2].PM;
        end
        //----------------------------------------------

        // Instantiation of On-The-Fly-Converter
        OTFconversion #(.step(r2)) OTFC2( //decodes q
            .q(p[r2+1]), .Q(P2), .QM(PM2),
            .Qnext(genStage[r2+1].P), .QMnext(genStage[r2+1].PM));
    
        // Instantiation of 4-2 CSA to calcuelate next W (w_sum + w_carry)
        CSA #(.width(width)) CSA2(
            .x(w_sum2<<2), .y(w_carry2<<2), .z(pD[r2]), .u(w_sum[r2+1]), .v(w_carry[r2+1]));
        
        // Instantiation of Selection function
        selection_inv_div SELECT2( //computes encoded q for next step
            .d(D2[width-2-:5]), .w(w[r2]), .q(p[r2+1]));

        // Instantiations of MUXs to compute word * digit mult
        op_mux #(width,width) MUX41_2( //computes q*D
            .q(p[r2+1]), .d(D2), .qd(pD[r2]));
        
        // W's estimation
        assign w[r2] = w_sum2[width-1-:7] + w_carry2[width-1-:7];

        for (step=r2+1; step<r3; step++) begin : next_rem3

            // Instatiation of On-The-Fly-Converter
            OTFconversion #(.step(step)) OTFC( //decodes q
                .q(p[step+1]), .Q(genStage[step].P), .QM(genStage[step].PM),
                .Qnext(genStage[step+1].P), .QMnext(genStage[step+1].PM));
        
            // Instatiation of 4-2 CSA to calculate next W (w_sum + w_carry)
            CSA #(.width(width)) CSA(
                .x(w_sum[step]<<2), .y(w_carry[step]<<2), .z(pD[step]), .u(w_sum[step+1]), .v(w_carry[step+1]));
            
            // Instatiantion of Selection function
            selection_inv_div SELECTMOD( //computes encoded q for next step
                .d(D2[width-2-:5]), .w(w[step]), .q(p[step+1]));

            // Instatiantions of MUXs to compute word * digit mult
            op_mux #(width,width) MUX41_0( //computes q*D
                .q(p[step+1]), .d(D2), .qd(pD[step]));
            
            // W's estimation
            assign w[step] = w_sum[step][width-1-:7] + w_carry[step][width-1-:7];
        end

        //------------------REGISTER 3------------------
        if(pipe_stages == 2 || pipe_stages == 3) begin : pipestage3
            always_ff @(posedge clk or negedge resetn) begin : stage3
                if(!resetn) begin
                    {D3, w_sum3, w_carry3, P3, PM3} <= '0;
                end else if(enable) begin   
                    D3 <= D2;
                    w_sum3 <= w_sum[r3];
                    w_carry3 <= w_carry[r3];
                    P3 <= genStage[r3].P;
                    PM3 <= genStage[r3].PM;
                end else begin
                    D3 <= D3;
                    w_sum3 <= w_sum3;
                    w_carry3 <= w_carry3;
                    P3 <= P3;
                    PM3 <= PM3;
                end
            end
        end else begin
            assign D3 = D2;
            assign w_sum3 = w_sum[r3];
            assign w_carry3 = w_carry[r3];
            assign P3 = genStage[r3].P;
            assign PM3 = genStage[r3].PM;
        end
        //----------------------------------------------

        // Instantiation of On-The-Fly-Converter
        OTFconversion #(.step(r3)) OTFC3( //decodes q
            .q(p[r3+1]), .Q(P3), .QM(PM3),
            .Qnext(genStage[r3+1].P), .QMnext(genStage[r3+1].PM));
    
        // Instantiation of 4-2 CSA to calcuelate next W (w_sum + w_carry)
        CSA #(.width(width)) CSA3(
            .x(w_sum3<<2), .y(w_carry3<<2), .z(pD[r3]), .u(w_sum[r3+1]), .v(w_carry[r3+1]));
        
        // Instantiation of Selection function
        selection_inv_div SELECT3( //computes encoded q for next step
            .d(D3[width-2-:5]), .w(w[r3]), .q(p[r3+1]));

        // Instantiations of MUXs to compute word * digit mult
        op_mux #(width,width) MUX41_3( //computes q*D
            .q(p[r3+1]), .d(D3), .qd(pD[r3]));
        
        // W's estimation
        assign w[r3] = w_sum3[width-1-:7] + w_carry3[width-1-:7];

        for (step=r3+1; step<total_steps-1; step++) begin: next_rem4

            // Instatiation of On-The-Fly-Converter
            OTFconversion #(.step(step)) OTFC( //decodes q
                .q(p[step+1]), .Q(genStage[step].P), .QM(genStage[step].PM),
                .Qnext(genStage[step+1].P), .QMnext(genStage[step+1].PM));
        
            // Instatiation of 4-2 CSA to calculate next W (w_sum + w_carry)
            CSA #(.width(width)) CSA(
                .x(w_sum[step]<<2), .y(w_carry[step]<<2), .z(pD[step]), .u(w_sum[step+1]), .v(w_carry[step+1]));
            
            // Instatiantion of Selection function
            selection_inv_div SELECTMOD( //computes encoded q for next step
                .d(D3[width-2-:5]), .w(w[step]), .q(p[step+1]));

            // Instatiantions of MUXs to compute word * digit mult
            op_mux #(width,width) MUX41_0( //computes q*D
                .q(p[step+1]), .d(D3), .qd(pD[step]));
            
            // W's estimation
            assign w[step] = w_sum[step][width-1-:7] + w_carry[step][width-1-:7];
        end

        // Instantiation of Selection function
        selection_inv_div SELECTMOD( //computes encoded q for next step
            .d(D3[width-2-:5]), .w(w[total_steps-1]), .q(p[total_steps]));

        logic signed [width-1:0] last_w;
        //assign last_w = (w_sum[total_steps-1]) + (w_carry[total_steps-1]);
        HCA #(.width(width)) HCA1(.A(w_sum[total_steps-1]), .B(w_carry[total_steps-1]), .sum(last_w));
        assign w[total_steps-1] = last_w[width-1-:7];

        OTFconversion #(.step(total_steps-1)) Final_OTFC( //decodes q
            .q(p[total_steps]), .Q(genStage[total_steps-1].P), .QM(genStage[total_steps-1].PM),
            .Qnext(genStage[total_steps].P), .QMnext(genStage[total_steps].PM));

        assign med_quotient = (last_w>=0) ? genStage[total_steps].P[2*total_steps-2:0] : genStage[total_steps].PM[2*total_steps-2:0];
        assign count=!med_quotient[2*total_steps-2];
        assign quotient   = (med_quotient[2*total_steps-2]) ? med_quotient[2*total_steps-2-:sig_width+1]:med_quotient[2*total_steps-3-:sig_width+1]; 
        assign guard_bit  = (med_quotient[2*total_steps-2]) ? med_quotient[2*total_steps-2-(sig_width+1)]:med_quotient[2*total_steps-3-(sig_width+1)];
        assign round_bit  = (med_quotient[2*total_steps-2]) ? med_quotient[2*total_steps-2-(sig_width+2)]:med_quotient[2*total_steps-3-(sig_width+2)];
        assign sticky_bit = (med_quotient[2*total_steps-2]) ? |(med_quotient[2*total_steps-2-(sig_width+3):0])|(|last_w):|(med_quotient[2*total_steps-3-(sig_width+3):0])|(|last_w);   
    endgenerate

endmodule
