#!/bin/bash

module load cadence/v2024

export SYNTH_PATH_LIB=$HOME
export TOP_MODULE=$1
export SIG_WIDTH=$2
export EX_WIDTH=$3
export PIPE_STAGES=$4
export MY_TYPE=$5

if [[ $# -eq 5 ]]
then
    #time joules -no_gui -f joules_gate_rtl.tcl
    time joules -no_gui -f joules_gate.tcl
else
    echo "Wrong number of parameters specified!"
    echo "./syntesize.sh <fp_module> <sig_width> <ex_width> <pipe_stages> " 
fi
