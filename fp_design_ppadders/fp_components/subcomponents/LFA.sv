module LFA #(parameter width = 16)
  (
    input [width-1:0] A, 
    input [width-1:0] B,
    output [width:0] sum
  );

  parameter depth = $clog2(width);
  //Propagate (p) and Generate (g) signals
  wire p[depth:0][width-1:0], g[depth:0][width-1:0];

  //Pre-process step (step 0)
  genvar i;
  generate
    for (i = 0; i < width; i = i + 1) begin : step_0
      assign p[0][i] = A[i] ^ B[i];
      assign g[0][i] = A[i] & B[i];
    end
  endgenerate
  
  // Calculate p and g signals
  genvar j;
  genvar k;
  generate
    for (j = 1; j <= depth; j = j + 1) begin : computation_step
      for (i = 0; i <= 2**depth; i = i + 1) begin : computation_group
        if(((i + 1 - 2**(j-1)) % 2**j) == 0) begin //this finds the group
          for(k = 0; k < 2**(j-1); k = k + 1) begin : computation_bit
            if(i-k < width) begin //not go over width
              assign p[j][i-k] = p[j-1][i-k]; //pass the previous value
              assign g[j][i-k] = g[j-1][i-k]; //pass the previous value
            end
            if(i+k+1 < width) begin //not go over width
              assign p[j][i+k+1] = p[j-1][i+k+1] & p[j-1][i];
              assign g[j][i+k+1] = (p[j-1][i+k+1] & g[j-1][i]) | g[j-1][i+k+1];
            end
          end
        end 
      end
    end
  endgenerate
      
  //Input carry is 0, so sum[0] = (propagate) p[0][0]
  assign sum[0] = p[0][0];

  //For every i, (carry) c[i]  = (generate) g[i][depth]
  //Calculate sum
  generate
    for (i = 1; i < width; i = i + 1) begin : calculate_sum
      assign sum[i] = p[0][i] ^ g[depth][i-1];
    end
  endgenerate

  //Obviously the carry bit
  assign sum[width] = g[depth][width-1];
  
endmodule
