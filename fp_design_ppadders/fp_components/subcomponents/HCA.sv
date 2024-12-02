module HCA #(parameter width = 16)
  (
    input [width-1:0] A, 
    input [width-1:0] B,
    output [width:0] sum
  );

  parameter depth = $clog2(width);
  //Propagate (p) and Generate (g) signals
  wire p[depth+1:0][width-1:0], g[depth+1:0][width-1:0];

  //Pre-process step (step 0)
  genvar i;
  generate
    for (i = 0; i < width; i = i + 1) begin : step_0
      assign p[0][i] = A[i] ^ B[i];
      assign g[0][i] = A[i] & B[i];
    end
  endgenerate
  
  //First half of p and g tree
  genvar j;
  generate
    for(j = 1; j < depth+1; j = j + 1) begin : computation_step
      for (i = 0; i < width; i = i + 1) begin : computation_bit
        if((i+1) % 2 == 0) begin //if i+1 is a multiple of 2
          if (i >= 2**(j-1)) begin
            assign p[j][i] = p[j-1][i] & p[j-1][i-2**(j-1)];
            assign g[j][i] = (p[j-1][i] & g[j-1][i-2**(j-1)]) | g[j-1][i];
          end
          else begin
            assign p[j][i] = p[j-1][i];
            assign g[j][i] = g[j-1][i];
          end            
  	    end
  	    else begin
            assign p[j][i] = p[j-1][i];
            assign g[j][i] = g[j-1][i];
        end 
      end
    end
  endgenerate
  
  assign p[depth+1][0] = p[depth][0];
  assign g[depth+1][0] = g[depth][0];

  generate
    for(i = 1; i < width; i = i +1) begin
      if(i % 2 == 0) begin
        assign p[depth+1][i] = p[depth][i] & p[depth][i-1];
        assign g[depth+1][i] = (p[depth][i] & g[depth][i-1]) | g[depth][i];
      end
      else begin
        assign p[depth+1][i] = p[depth][i];
        assign g[depth+1][i] = g[depth][i];
      end
    end
  endgenerate

   //Input carry is 0, so sum[0] = (propagate) p[0][0]
  assign sum[0] = p[0][0];
  
  //For every i, (carry) c[i]  = (generate) g[i][depth]
  //Calculate sum
  generate
    for (i = 1; i < width; i = i + 1) begin : calculate_sum
      assign sum[i] = p[0][i] ^ g[depth+1][i-1];
    end
  endgenerate

  //Obviously the carry bit
  assign sum[width] = g[depth+1][width-1];
  
  
endmodule
