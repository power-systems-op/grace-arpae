#using Queryverse
using CpuId
using DataFrames
using Dates
using DelimitedFiles
using JuMP
using Logging
using CPLEX
using CSV

# Parameters

const N_Gens =  62 # number of conventional generators
const N_Peakers =  70 # number of conventional generators
const N_StorgUs = 8 # number of storage units
const N_Zones = 2
const M_Zones = 2
const N_Blocks =7
const INITIAL_DAY = 1
const FINAL_DAY = 10

#TODO: check if constant INITIAL_HR_BUCR should exist
const INITIAL_HR_FUCR = 6 # represents the running time for the first WA unit commitment run. INITIAL_HR_FUCR=0 means the FUCR's optimal outcomes are ready at 00:00
const INITIAL_HR_SUCR = 17 #  represents the running time for the second WA unit commitment run. INITIAL_HR_SUCR=17 means the SUCR's optimal outcomes are ready at 17:00
const N_Hrs_FUCR = 162 # N_Hrs_FUCR = 168-INITIAL_HR_FUCR, and INITIAL_HR_FUCR runs from 0 to 23; INITIAL_HR_FUCR=6 ==> N_Hrs_FUCR =162
const N_Hrs_SUCR = 151  # N_Hrs_SUCR = 168-INITIAL_HR_SUCR, and INITIAL_HR_SUCR runs from 17 to 23; INITIAL_HR_SUCR=17 ==> N_Hrs_FUCR =168

const DemandCurt_C = 3000; # Load-Shedding Penalty
const OverGen_C = 4000; # Over-generation Penalty
const DemandCurt_Max = 100; # Load-Shedding Penalty
const OverGen_Max = 100; # Over-generation Penalty

const ViolPenalty = 500;
const ViolMax = 10;

const Solver_EPGAP =0.01; #Solver's optimality gap that serves as the optimization termination criteria

const FILE_ACCESS_OVER = "w+"
const FILE_ACCESS_APPEND = "a+"
##
#Enabling debugging code, use ENV["JULIA_DEBUG"] = "" to desable Debugging code
ENV["JULIA_DEBUG"] = "all"

# Logging file
io_log = open(
    string(
        "UC_BAU_",
        Dates.format(now(), "yyyy-mm-dd_HH-MM-SS"),
        ".txt",
    ),
    FILE_ACCESS_APPEND,
)

#log document
logger = SimpleLogger(io_log)
flush(io_log)
global_logger(logger)

t1 = time_ns()

write(io_log, "Running model from day $INITIAL_DAY to day $FINAL_DAY with the following parameters:\n")
write(io_log, "Load-Shedding Penalty: $DemandCurt_C, Over-generation Penalty: $OverGen_C\n")
write(io_log, "Max Load-Shedding Penalty $DemandCurt_Max, Max Over-generation Penalty: $OverGen_Max\n")
write(io_log, "MaxGenLimit Viol Penalty: $ViolPenalty, OptimalityGap: $OverGen_C\n")

@info "Hardware Features: " cpuinfo()

t2 = time_ns()
elapsedTime = (t2 -t1)/1.0e9;

@info "Whole Program solved in (s):" elapsedTime;
close(io_log);
