#-------------------------------------------------------------------------------
# Configurable parameters
#-------------------------------------------------------------------------------

set    design         $::env(MY_TYPE)
set    MY_TOP         $::env(TOP_MODULE)
set    TOP            fp_${MY_TOP}
set    SIG_WIDTH      $::env(SIG_WIDTH)
set    EX_WIDTH       $::env(EX_WIDTH)
set    PIPE_STAGES    $::env(PIPE_STAGES)
set    RESULTS_DIR    ../genus_reports/netlist_${TOP}_${design}_${SIG_WIDTH}_${EX_WIDTH}_${PIPE_STAGES}
#-------------------------------------------------------------------------------
# Read Library and Create Library Domains
#-------------------------------------------------------------------------------

set_db lib_search_path /mnt/apps/prebuilt/eda/designkits/GPDK/gsclib045/lan/flow/t1u1/reference_libs/GPDK045/gsclib045_svt_v4.4/gsclib045/timing
read_libs fast_vdd1v0_basicCells.lib

#-------------------------------------------------------------------------------
# Read the synthesized Netlist
#-------------------------------------------------------------------------------
read_netlist ${RESULTS_DIR}/netlist.v

#-------------------------------------------------------------------------------
# Read the constraints
#-------------------------------------------------------------------------------
read_sdc ./constraints.sdc


#-------------------------------------------------------------------------------
# Read Stimulus
#-------------------------------------------------------------------------------
eval read_stimulus -file ${TOP}_${design}_${SIG_WIDTH}_${EX_WIDTH}_${PIPE_STAGES}.vcd -format vcd -dut_instance ${MY_TOP}_TB_random_pipe.U  -frame_count 1000

gen_clock_tree

#-------------------------------------------------------------------------------
# Compute power
#-------------------------------------------------------------------------------
compute_power

#-------------------------------------------------------------------------------
# Create the reports
#-------------------------------------------------------------------------------
report_activity -out power_reports/${TOP}_${SIG_WIDTH}_${EX_WIDTH}_${PIPE_STAGES}_${design}_act1.rpt
report_power    -unit mW -format "%.3f" -out power_reports/${TOP}_${SIG_WIDTH}_${EX_WIDTH}_${PIPE_STAGES}_${design}_power1.rpt 
#report_ppa -out power_reports/${TOP}_${SIG_WIDTH}_${EX_WIDTH}_${PIPE_STAGES}_${design}_ppa1.rpt 
#report_ppa -out power_reports/${TOP}_ppa1.rpt 
exit
