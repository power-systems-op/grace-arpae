const GENS =  64 # number of conventional generators
const PEAKERS =  80 # number of conventional generators
const STORG_UNITS = 8 # number of storage units
const N_ZONES = 2
const M_ZONES = 2
const BLOCKS = 7

const INITIAL_DAY = 1
const FINAL_DAY = 1
# Running time for the 1st Week-Ahead UC run.
# INIT_HR_FUCR=0 means the FUCR's optimal outcomes are ready at 00:00
const INIT_HR_FUCR = 6
# Running time for the 2nd WA unit commitment run.
# INIT_HR_SUCR=17 means the SUCR's optimal outcomes are ready at 17:00
const INIT_HR_SUCR = 17
# HRS_FUCR = 168-INIT_HR_FUCR, and INIT_HR_FUCR runs from 0 to 23;
# INIT_HR_FUCR=6 ==> HRS_FUCR =162
const HRS_FUCR = 162
# HRS_SUCR = 168-INIT_HR_SUCR, and INIT_HR_SUCR runs from 17 to 23;
# INIT_HR_SUCR=17 ==> HRS_FUCR =168
const HRS_SUCR = 151

const LOAD_SHED_PENALTY = 3000; # Load-Shedding Penalty
const OVERGEN_PENALTY = 4000; # Over-generation Penalty
const LOAD_SHED_MAX = 100; # Load-Shedding Penalty
const OVERGEN_MAX = 100; # Over-generation Penalty
const VIOLATION_PENALTY = 500;
const VIOLATION_MAX = 10;
#Solver's optimality gap that serves as the optimization termination criteria
const SOLVER_EPGAP =0.005;

const FILE_ACCESS_OVER = "w+";
const FILE_ACCESS_APPEND = "a+";
