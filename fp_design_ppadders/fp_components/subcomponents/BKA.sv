module BKA #(parameter width = 16)
  (
    input [width-1:0] A, 
    input [width-1:0] B,
    output [width:0] sum
  );

  parameter depth = $clog2(width);
  parameter k = 2*depth;
  //Propagate (p) and Generate (g) signals
  wire p[2*depth-1:0][width-1:0], g[2*depth-1:0][width-1:0];

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
    for(j = 1; j <= depth; j = j + 1) begin : computation_step_h1
      for (i = 0; i < width; i = i + 1) begin : computation_bit_h1
        if((i+1) % 2**j) begin //if i+1 is not a multiple of 2^j
          assign p[j][i] = p[j-1][i];
          assign g[j][i] = g[j-1][i];
        end 
        else begin
          assign p[j][i] = p[j-1][i] & p[j-1][i-(2**j-2**(j-1))];
          assign g[j][i] = (p[j-1][i] & g[j-1][i-(2**j-2**(j-1))]) | g[j-1][i];
  	end
      end
    end
  endgenerate
  
  //Second half of p and g tree
  
  generate
    for(j = depth - 1; j > 0; j = j - 1) begin : computation_step_h2
      for (i = 0; i < 2**j; i = i + 1) begin : computation_bit_h2_1
        assign p[k-j][i] = p[k-j-1][i];
        assign g[k-j][i] = g[k-j-1][i];
      end
      
      for (i = 2**j; i < width; i = i + 1) begin : computation_bit_h2_2
        if((i+1-2**(j-1)) % 2**j) begin //if the first part not a multiple of 2^j
          assign p[k-j][i] = p[k-j-1][i];
          assign g[k-j][i] = g[k-j-1][i];
        end 
        else begin
          assign p[k-j][i] = p[k-j-1][i] & p[k-j-1][i-2**(j-1)];
          assign g[k-j][i] = (p[k-j-1][i] & g[k-j-1][i-2**(j-1)]) | g[k-j-1][i];
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
      assign sum[i] = p[0][i] ^ g[k-1][i-1];
    end
  endgenerate

  //Obviously the carry bit
  assign sum[width] = g[k-1][width-1];
  
  
endmodule
