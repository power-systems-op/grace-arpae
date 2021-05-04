#  Copyright 2021, Author: Ali Daraeepour (a.daraeepour@duke.edu)
#                  Contributors: Mauricio Hernandez (mmh54@duke.edu)
#  This Source Code Form is subject to the terms of the MIT  License. If a copy of the MIT was
# not distributed with this file, You can obtain one at https://mit-license.org/.
#############################################################################
# GRACE BAU UC
# This program solves the Business as Usual Unit Commitment problem of
# Duke Energy Power Sytem
# See https://github.com/power-systems-op/grace-arpae/
#############################################################################

"""
File: BAU_OPM.jl
Version: 7
...
# Arguments: None
# Outputs: dataframe
# Examples: N/A
"""

#NOTES: This file was originally labeled as BAU_OPM_V5_Nuc_Cogen_Imp_Exp_MustRun_DCC
# Changes in this version: Nuclear data was included
#= Changes
1. Specify data type of data of the vectors that containd the data read from CSV input files.
2. Eliminate several rounding operations that have an data type specified
3. Replace several global variables by local ones
4. Replace auxiliary variables representing the initial values for commitment/dispatch schedules fed to different Models by structures.


=#

#using Queryverse
using CPLEX
using CpuId
using CSV
using DataFrames
using Dates
using DelimitedFiles
using JuMP
using Logging

t1 = time_ns()
include("constants.jl")
include("data_structure.jl")
t1_read_data = time_ns()
include("import_data.jl")
t2_read_data = time_ns()
time_read_data = (t2_read_data -t1_read_data)/1.0e9;
#=
const M_ZONES = 2
const BLOCKS = 7
const INITIAL_DAY = 1
const FINAL_DAY = 1

const INIT_HR_FUCR = 6 # represents the running time for the first WA unit commitment run. INIT_HR_FUCR=0 means the FUCR's optimal outcomes are ready at 00:00
const INIT_HR_SUCR = 17 #  represents the running time for the second WA unit commitment run. INIT_HR_SUCR=17 means the SUCR's optimal outcomes are ready at 17:00
const HRS_FUCR = 162 # HRS_FUCR = 168-INIT_HR_FUCR, and INIT_HR_FUCR runs from 0 to 23; INIT_HR_FUCR=6 ==> HRS_FUCR =162
const HRS_SUCR = 151  # HRS_SUCR = 168-INIT_HR_SUCR, and INIT_HR_SUCR runs from 17 to 23; INIT_HR_SUCR=17 ==> HRS_FUCR =168

const LOAD_SHED_PENALTY = 3000; # Load-Shedding Penalty
const OVERGEN_PENALTY = 4000; # Over-generation Penalty
const LOAD_SHED_MAX = 100; # Load-Shedding Penalty
const OVERGEN_MAX = 100; # Over-generation Penalty

const VIOLATION_PENALTY = 500;
const VIOLATION_MAX = 10;

const SOLVER_EPGAP =0.005; #Solver's optimality gap that serves as the optimization termination criteria

const FILE_ACCESS_OVER = "w+"
const FILE_ACCESS_APPEND = "a+" =#
##
#Enabling debugging code, use ENV["JULIA_DEBUG"] = "" to desable ging code
ENV["JULIA_DEBUG"] = "all"

# Log file
io_log = open( string(".//outputs//logs//UC_BAU_",
        Dates.format(now(), "yyyy-mm-dd_HH-MM-SS"), ".txt",), FILE_ACCESS_APPEND)

logger = SimpleLogger(io_log)
flush(io_log)
global_logger(logger)

@info "Hardware Features: " cpuinfo()

write(io_log, "Running model from day $INITIAL_DAY to day $FINAL_DAY with the following parameters:\n")
write(io_log, "Load-Shedding Penalty: $LOAD_SHED_PENALTY, Over-generation Penalty: $OVERGEN_PENALTY\n")
write(io_log, "Max Load-Shedding Penalty $LOAD_SHED_MAX, Max Over-generation Penalty: $OVERGEN_MAX\n")
write(io_log, "MaxGenLimit Viol Penalty: $VIOLATION_PENALTY, OptimalityGap: $OVERGEN_PENALTY\n")

time_performance_header    = ["Section", "Time", "Note1", "Note2", "Note3", "Note4"]
open(".//outputs//csv//time_performance.csv", FILE_ACCESS_OVER) do io
    writedlm(io, permutedims(time_performance_header), ',')
end; # closes file

@info "Time to read input data (s): $time_read_data";
open(".//outputs//csv//time_performance.csv", FILE_ACCESS_APPEND) do io
        writedlm(io, hcat("Read Input Data", time_read_data, "",
                "", "", "Read CSV files"), ',')
end;

##
#=generators = SysGenerator(DF_Generators.UNIT_ID,
            DF_Generators.StatusInit,
            DF_Generators.PowerInit,
            DF_Generators.UpTimeInit,
            DF_Generators.DownTimeInit,
            DF_Generators.IHRC_B1_HR,
            DF_Generators.IHRC_B2_HR,
            DF_Generators.IHRC_B3_HR,
            DF_Generators.IHRC_B4_HR,
            DF_Generators.IHRC_B5_HR,
            DF_Generators.IHRC_B6_HR,
            DF_Generators.IHRC_B7_HR,
            DF_Generators.IHRC_B1_Q,
            DF_Generators.IHRC_B2_Q,
            DF_Generators.IHRC_B3_Q,
            DF_Generators.IHRC_B4_Q,
            DF_Generators.IHRC_B5_Q,
            DF_Generators.IHRC_B6_Q,
            DF_Generators.IHRC_B7_Q,
            DF_Generators.NoLoadHR,
            DF_Generators.ShutdownCost,
            DF_Generators.HotStartU_FixedCost,
            DF_Generators.HotStartU_HeatRate ,
            DF_Generators.MinDownTime,
            DF_Generators.MinUpTime,
            DF_Generators.MaxPowerOut,
            DF_Generators.MinPowerOut,
            DF_Generators.SpinningRes_Limit,
            DF_Generators.RampUpLimit,
            DF_Generators.RampShutDownLimit,
            DF_Generators.Nuclear,
            DF_Generators.Cogen,
            DF_Generators.NaturalGasFired,
)
=#

# Setting initial values
fucr_gens = UnitsResults(
	copy(DF_Generators.StatusInit),
	copy(DF_Generators.PowerInit),
	copy(DF_Generators.UpTimeInit),
	copy(DF_Generators.DownTimeInit))

fucr_peakers = UnitsResults(
	copy(DF_Peakers.StatusInit),
	copy(DF_Peakers.PowerInit),
	copy(DF_Peakers.UpTimeInit),
	copy(DF_Peakers.DownTimeInit))

FUCR = UC_Results(fucr_gens, fucr_peakers, copy(DF_Storage.SOCInit))

sucr_gens = UnitsResults(
	copy(DF_Generators.StatusInit),
	copy(DF_Generators.PowerInit),
	copy(DF_Generators.UpTimeInit),
	copy(DF_Generators.DownTimeInit))

sucr_peakers = UnitsResults(
	copy(DF_Peakers.StatusInit),
	copy(DF_Peakers.PowerInit),
	copy(DF_Peakers.UpTimeInit),
	copy(DF_Peakers.DownTimeInit))

SUCR = UC_Results(sucr_gens, sucr_peakers, copy(DF_Storage.SOCInit))

bucr1_gens = UnitsResults(copy(DF_Generators.StatusInit),
	copy(DF_Generators.PowerInit),
	copy(DF_Generators.UpTimeInit),
	copy(DF_Generators.DownTimeInit))

bucr1_peakers = UnitsResults(copy(DF_Peakers.StatusInit),
	copy(DF_Peakers.PowerInit),
	copy(DF_Peakers.UpTimeInit),
	copy(DF_Peakers.DownTimeInit))

BUCR1 = UC_Results(bucr1_gens, bucr1_peakers, copy(DF_Storage.SOCInit))

bucr2_gens = UnitsResults(zeros(Int64, GENS), zeros(Float64, GENS),
	zeros(Int64, GENS), zeros(Int64, GENS))

bucr2_peakers = UnitsResults(zeros(Int64, PEAKERS), zeros(Float64, PEAKERS),
	zeros(Int64, PEAKERS), zeros(Int64, PEAKERS))

BUCR2 = UC_Results(bucr2_gens, bucr2_peakers, zeros(Float64, STORG_UNITS))

## Headers of output files
@time begin
FUCR_GenOutputs_header      = ["Day", "Hour", "GeneratorID", "UNIT_NAME", "MinPowerOut", "MaxPowerOut", "Output", "On/off", "ShutDown", "Startup", "UpSpinRes", "Non_SpinRes", "DownSpinRes", "TotalGenPosV", "TotalGenNegV", "MaxGenVio", "MinGenVio"]
FUCR_PeakerOutputs_header   = ["Day", "Hour", "PeakerID", "UNIT_NAME", "MinPowerOut", "MaxPowerOut", "Output", "On/off", "ShutDown", "Startup", "UpSpinRes", "Non_SpinRes", "DownSpinRes", "TotalGenPosV", "TotalGenNegV", "MaxGenVio", "MinGenVio"]
FUCR_StorageOutputs_header  = ["Day", "Hour", "StorageUniID", "Power", "EnergyLimit", "Charge_St", "Discharge_St", "Idle_St", "storgChrgPwr", "storgDiscPwr", "storgSOC", "storgResUp", "storgResDn"]
FUCR_TranFlowOutputs_header = ["Day", "Time period", "Source", "Sink", "Flow", "TransCap"]
FUCR_Curtail_header         = ["Day", "Hour", "Zone", "OverGeneration", "DemandCurtailment", "WindCrtailment", "SolarCurtailment", "HydroSpillage"]
SUCR_GenOutputs_header      = ["Day", "Hour", "GeneratorID", "UNIT_NAME", "MinPowerOut", "MaxPowerOut", "Output", "On/off", "ShutDown", "Startup", "UpSpinRes", "Non_SpinRes", "DownSpinRes", "TotalGenPosV", "TotalGenNegV", "MaxGenVio", "MinGenVio"]
SUCR_PeakerOutputs_header   = ["Day", "Hour", "GeneratorID", "UNIT_NAME", "MinPowerOut", "MaxPowerOut", "Output", "On/off", "ShutDown", "Startup", "UpSpinRes", "Non_SpinRes", "DownSpinRes", "TotalGenPosV", "TotalGenNegV", "MaxGenVio", "MinGenVio"]
SUCR_StorageOutputs_header  = ["Day", "Hour", "StorageUniID", "Power", "EnergyLimit", "Charge_St", "Discharge_St", "Idle_St", "storgChrgPwr", "storgDiscPwr", "storgSOC", "storgResUp", "storgResDn"]
SUCR_TranFlowOutputs_header = ["Day", "Time period", "Source", "Sink", "Flow", "TransCap"]
SUCR_Curtail_header         = ["Day", "Hour", "Zone", "OverGeneration", "DemandCurtailment", "WindCrtailment", "SolarCurtailment", "HydroSpillage"]
BUCR_GenOutputs_header      = ["Day", "Hour", "GeneratorID", "UNIT_NAME", "MinPowerOut", "MaxPowerOut", "Output", "On/off", "ShutDown", "Startup", "TotalGenPosV", "TotalGenNegV", "MaxGenVio", "MinGenVio"]
BUCR_PeakerOutputs_header   = ["Day", "Hour", "GeneratorID", "UNIT_NAME", "MinPowerOut", "MaxPowerOut", "Output", "On/off", "ShutDown", "Startup", "TotalGenPosV", "TotalGenNegV", "MaxGenVio", "MinGenVio"]
BUCR_StorageOutputs_header  = ["Day", "Hour", "StorageUniID", "Power", "EnergyLimit", "Charge_St", "Discharge_St", "Idle_St", "storgChrgPwr", "storgDiscPwr", "storgSOC", "storgResUp", "storgResDn"]
BUCR_TranFlowOutputs_header = ["Day", "Time period", "Source", "Sink", "Flow", "TransCap"]
BUCR_Curtail_header         = ["Day", "Hour", "Zone", "OverGeneration", "DemandCurtailment", "WindCrtailment", "SolarCurtailment", "HydroSpillage"]

end #timer

##
# Spreadsheets for the first unit commitment run
# Creating Conventional generating units' schedules in the first unit commitment run
open(".//outputs//csv//FUCR_GenOutputs.csv", FILE_ACCESS_OVER) do io
    writedlm(io, permutedims(FUCR_GenOutputs_header), ',')
end; # closes file

open(".//outputs//csv//FUCR_PeakerOutputs.csv", FILE_ACCESS_OVER) do io
    writedlm(io, permutedims(FUCR_PeakerOutputs_header), ',')
end; # closes file

open(".//outputs//csv//FUCR_StorageOutputs.csv", FILE_ACCESS_OVER) do io
    writedlm(io, permutedims(FUCR_StorageOutputs_header), ',')
end;

open(".//outputs//csv//FUCR_TranFlowOutputs.csv", FILE_ACCESS_OVER) do io
    writedlm(io, permutedims(FUCR_TranFlowOutputs_header), ',')
end; # closes file

open(".//outputs//csv//FUCR_Curtail.csv", FILE_ACCESS_OVER) do io
    writedlm(io, permutedims(FUCR_Curtail_header), ',')
end; # closes file

# Spreadsheets for the second unit commitment run
# Creating Conventional generating units' schedules in the second unit commitment run
open(".//outputs//csv//SUCR_GenOutputs.csv", FILE_ACCESS_OVER) do io
    writedlm(io, permutedims(SUCR_GenOutputs_header), ',')
end; # closes file

open(".//outputs//csv//SUCR_PeakerOutputs.csv", FILE_ACCESS_OVER) do io
    writedlm(io, permutedims(SUCR_PeakerOutputs_header), ',')
end; # closes file

open(".//outputs//csv//SUCR_StorageOutputs.csv", FILE_ACCESS_OVER) do io
    writedlm(io, permutedims(SUCR_StorageOutputs_header), ',')
end; # closes file

open(".//outputs//csv//SUCR_TranFlowOutputs.csv", FILE_ACCESS_OVER) do io
    writedlm(io, permutedims(SUCR_TranFlowOutputs_header), ',')
end; # closes file

open(".//outputs//csv//SUCR_Curtail.csv", FILE_ACCESS_OVER) do io
    writedlm(io, permutedims(SUCR_Curtail_header), ',')
end; # closes file

# Spreadsheets for the balancing unit commitment run
# Write the conventional generators' schedules
open(".//outputs//csv//BUCR_GenOutputs.csv", FILE_ACCESS_OVER) do io
    writedlm(io, permutedims(BUCR_GenOutputs_header), ',')
end; # closes file

open(".//outputs//csv//BUCR_PeakerOutputs.csv", FILE_ACCESS_OVER) do io
    writedlm(io, permutedims(BUCR_PeakerOutputs_header), ',')
end; # closes file

# Writing storage units' optimal schedules into CSV file
open(".//outputs//csv//BUCR_StorageOutputs.csv", FILE_ACCESS_OVER) do io
    writedlm(io, permutedims(BUCR_StorageOutputs_header), ',')
end; # closes file

# Writing the transmission flow schedules in CSV file
open(".//outputs//csv//BUCR_TranFlowOutputs.csv", FILE_ACCESS_OVER) do io
    writedlm(io, permutedims(BUCR_TranFlowOutputs_header), ',')
end; # closes file

open(".//outputs//csv//BUCR_Curtail.csv", FILE_ACCESS_OVER) do io
    writedlm(io, permutedims(BUCR_Curtail_header), ',')
end; # closes file

## Creating the output spreadsheet that save the optimal outcomes as reported by WA and RT UC Models
######## Spreadsheets for the first unit commitment run
# Creating Conventional generating units' schedules in the first unit commitment run

## Creating variables that transfer optimal schedules between the Models

#### Some of the below variables may be unneccsary and can be deletetd. Check at the end
FUCRtoBUCR1_genOnOff = zeros(Int64, GENS,INIT_HR_SUCR-INIT_HR_FUCR)
FUCRtoBUCR1_genOut = zeros(Float64, GENS,INIT_HR_SUCR-INIT_HR_FUCR)
FUCRtoBUCR1_genOut_Block = zeros(Float64, GENS,BLOCKS,INIT_HR_SUCR-INIT_HR_FUCR)
FUCRtoBUCR1_genStartUp = zeros(Int64, GENS,INIT_HR_SUCR-INIT_HR_FUCR)
FUCRtoBUCR1_genShutDown= zeros(Int64, GENS,INIT_HR_SUCR-INIT_HR_FUCR)

FUCRtoBUCR1_peakerOnOff = zeros(Int64, PEAKERS,INIT_HR_SUCR-INIT_HR_FUCR)
FUCRtoBUCR1_peakerOut = zeros(Float64, PEAKERS,INIT_HR_SUCR-INIT_HR_FUCR)
FUCRtoBUCR1_peakerOut_Block = zeros(Float64, PEAKERS,BLOCKS,INIT_HR_SUCR-INIT_HR_FUCR)
FUCRtoBUCR1_peakerStartUp = zeros(Int64, PEAKERS,INIT_HR_SUCR-INIT_HR_FUCR)
FUCRtoBUCR1_peakerShutDown= zeros(Int64, PEAKERS,INIT_HR_SUCR-INIT_HR_FUCR)

FUCRtoBUCR1_storgChrg = zeros(Int64, STORG_UNITS, INIT_HR_SUCR-INIT_HR_FUCR)
FUCRtoBUCR1_storgDisc = zeros(Int64, STORG_UNITS, INIT_HR_SUCR-INIT_HR_FUCR)
FUCRtoBUCR1_storgIdle = zeros(Int64, STORG_UNITS, INIT_HR_SUCR-INIT_HR_FUCR)
FUCRtoBUCR1_storgChrgPwr = zeros(Float64, STORG_UNITS, INIT_HR_SUCR-INIT_HR_FUCR)
FUCRtoBUCR1_storgDiscPwr = zeros(Float64, STORG_UNITS, INIT_HR_SUCR-INIT_HR_FUCR)
FUCRtoBUCR1_storgSOC = zeros(Float64, STORG_UNITS, INIT_HR_SUCR-INIT_HR_FUCR)

SUCRtoBUCR2_genOnOff = zeros(Int64, GENS,24-INIT_HR_SUCR+INIT_HR_FUCR)
SUCRtoBUCR2_genOut = zeros(Float64, GENS,24-INIT_HR_SUCR+INIT_HR_FUCR)
SUCRtoBUCR2_genOut_Block = zeros(Float64, GENS,BLOCKS,24-INIT_HR_SUCR+INIT_HR_FUCR)
SUCRtoBUCR2_genStartUp = zeros(Int64, GENS,24-INIT_HR_SUCR+INIT_HR_FUCR)
SUCRtoBUCR2_genShutDown= zeros(Int64, GENS,24-INIT_HR_SUCR+INIT_HR_FUCR)

SUCRtoBUCR2_peakerOnOff = zeros(Int64, PEAKERS,24-INIT_HR_SUCR+INIT_HR_FUCR)
SUCRtoBUCR2_peakerOut = zeros(Float64, PEAKERS,24-INIT_HR_SUCR+INIT_HR_FUCR)
SUCRtoBUCR2_peakerOut_Block = zeros(Float64, PEAKERS,BLOCKS,24-INIT_HR_SUCR+INIT_HR_FUCR)
SUCRtoBUCR2_peakerStartUp = zeros(Int64, PEAKERS,24-INIT_HR_SUCR+INIT_HR_FUCR)
SUCRtoBUCR2_peakerShutDown= zeros(Int64, PEAKERS,24-INIT_HR_SUCR+INIT_HR_FUCR)

SUCRtoBUCR2_storgChrg = zeros(Int64, STORG_UNITS, 24-INIT_HR_SUCR+INIT_HR_FUCR)
SUCRtoBUCR2_storgDisc = zeros(Int64, STORG_UNITS, 24-INIT_HR_SUCR+INIT_HR_FUCR)
SUCRtoBUCR2_storgIdle = zeros(Int64, STORG_UNITS, 24-INIT_HR_SUCR+INIT_HR_FUCR)
SUCRtoBUCR2_storgChrgPwr = zeros(Float64, STORG_UNITS, 24-INIT_HR_SUCR+INIT_HR_FUCR)
SUCRtoBUCR2_storgDiscPwr = zeros(Float64, STORG_UNITS, 24-INIT_HR_SUCR+INIT_HR_FUCR)
SUCRtoBUCR2_storgSOC = zeros(Float64, STORG_UNITS, 24-INIT_HR_SUCR+INIT_HR_FUCR)

## Auxiliary variables for enforcing commitment of slow and fast-start units in BUCRs
BUCR1_Commit_LB = zeros(Int64, GENS)
BUCR1_Commit_UB = zeros(Int64, GENS)
BUCR2_Commit_LB = zeros(Int64, GENS)
BUCR2_Commit_UB = zeros(Int64, GENS)

BUCR1_Commit_Peaker_LB = zeros(Int64, PEAKERS)
BUCR1_Commit_Peaker_UB = zeros(Int64, PEAKERS)
BUCR2_Commit_Peaker_LB = zeros(Int64, PEAKERS)
BUCR2_Commit_Peaker_UB = zeros(Int64, PEAKERS)

## Pre-processing the data to calculate the model inputs:
# The time range lower-bound for min up constrain using the alternative approach

# Function to replace values below 1 by 1
replace_lower_limit(x::Int64) = x < 1 ? 1 : x

# LB for slow-start conventional generators
lb_MUT=zeros(Int64, GENS,HRS_FUCR);
lb_MDT=zeros(Int64, GENS,HRS_FUCR)
for g in 1:GENS, t in 1:HRS_FUCR
    lb_MUT[g,t] =  replace_lower_limit(t-DF_Generators.MinUpTime[g]+1);
    lb_MDT[g,t] =  replace_lower_limit(t-DF_Generators.MinDownTime[g]+1);
end

# LB for peakers
lb_MUT_Peaker=zeros(Int64, PEAKERS,HRS_FUCR)
lb_MDT_Peaker=zeros(Int64, PEAKERS, HRS_FUCR)
for k in 1:PEAKERS , t in 1:HRS_FUCR
    lb_MUT_Peaker[k,t] =  replace_lower_limit(t-DF_Peakers.MinUpTime[k]+1);
    lb_MDT_Peaker[k,t] =  replace_lower_limit(t-DF_Peakers.MinDownTime[k]+1);
end
## TODO: We need two more loops for calculating the lb_MUT abd lb_MDT for the second UC runs
#************************************************************************************
## The foor loop runs two WAUC models and the RTUC models every day
for day = INITIAL_DAY:FINAL_DAY
   t1_day_execution = time_ns()

   # Bottom and upper cells of the demand data needed for running the first
   # WA-UC run at 6 am with 7-day look-ahead horizon
   D_Rng_Dn_FUCR = ((day-1)*(INIT_HR_FUCR+HRS_FUCR)) + INIT_HR_FUCR + 1;
   D_Rng_Up_FUCR = day*(INIT_HR_FUCR+HRS_FUCR);
   #rngdn_fucr
   R_Rng_Dn_FUCR = ((day-1)*(24))+INIT_HR_FUCR+1
   R_Rng_Up_FUCR = ((day+6)*(24))
   # Demand Data Pre-Processing for FUCR and SUCR
   fucr_prep_demand = DemandPreprocGens(
   	copy(FUCR_Demands[D_Rng_Dn_FUCR:D_Rng_Up_FUCR, :]),
    	copy(FUCR_SolarGs[R_Rng_Dn_FUCR:R_Rng_Up_FUCR, :]),
        copy(FUCR_WindGs[R_Rng_Dn_FUCR:R_Rng_Up_FUCR, :]),
        copy(FUCR_HydroGs[R_Rng_Dn_FUCR:R_Rng_Up_FUCR, :]),
        copy(FUCR_NuclearGs[R_Rng_Dn_FUCR:R_Rng_Up_FUCR, :]),
        copy(FUCR_CogenGs[R_Rng_Dn_FUCR:R_Rng_Up_FUCR, :])
    )

    # Bottom and upper cells of the demand data needed for running the second
    # WA-UC run at 5 pm with 7-day look-ahead horizon
    D_Rng_Dn_SUCR = ((day-1)*(INIT_HR_FUCR+HRS_FUCR))+INIT_HR_SUCR+1;
    D_Rng_Up_SUCR = day*(INIT_HR_FUCR+HRS_FUCR);

    R_Rng_Dn_SUCR = ((day-1)*(24))+INIT_HR_SUCR+1;
    R_Rng_Up_SUCR = ((day+6)*(24));

    sucr_prep_demand = DemandPreprocGens(
    	copy(SUCR_Demands[D_Rng_Dn_SUCR:D_Rng_Up_SUCR, :]),
    	copy(SUCR_SolarGs[R_Rng_Dn_SUCR:R_Rng_Up_SUCR, :]),
    	copy(SUCR_WindGs[R_Rng_Dn_SUCR:R_Rng_Up_SUCR, :]),
    	copy(SUCR_HydroGs[R_Rng_Dn_SUCR:R_Rng_Up_SUCR, :]),
    	copy(SUCR_NuclearGs[R_Rng_Dn_SUCR:R_Rng_Up_SUCR, :]),
    	copy(SUCR_CogenGs[R_Rng_Dn_SUCR:R_Rng_Up_SUCR, :])
    )

## This block models the first UC optimization that is run in the morning
    t1_FUCRmodel = time_ns()
    FUCRmodel = direct_model(CPLEX.Optimizer())
    #set_optimizer_attribute(FUCRmodel, "CPX_PARAM_EPINT", 1e-5)
    # Enable Benders strategy
    #MOI.set(FUCRmodel, MOI.RawParameter("CPXPARAM_Benders_Strategy"), 3)
    set_optimizer_attribute(FUCRmodel, "CPX_PARAM_EPGAP", SOLVER_EPGAP)

# Declaring the decision variables for conventional generators
    @variable(FUCRmodel, FUCR_genOnOff[1:GENS, 0:HRS_FUCR], Bin) #Bin
    @variable(FUCRmodel, FUCR_genStartUp[1:GENS, 1:HRS_FUCR], Bin) # startup variable
    @variable(FUCRmodel, FUCR_genShutDown[1:GENS, 1:HRS_FUCR], Bin) # shutdown variable
    @variable(FUCRmodel, FUCR_genOut[1:GENS, 0:HRS_FUCR]>=0) # Generator's output schedule
    @variable(FUCRmodel, FUCR_genOut_Block[1:GENS, 1:BLOCKS, 1:HRS_FUCR]>=0) # Generator's output schedule from each block (block rfers to IHR curve blocks/segments)
    @variable(FUCRmodel, FUCR_genResUp[1:GENS, 1:HRS_FUCR]>=0) # Generators' up reserve schedule
    @variable(FUCRmodel, FUCR_genResNonSpin[1:GENS, 1:HRS_FUCR]>=0) # Scheduled up reserve on offline fast-start peakers
    @variable(FUCRmodel, FUCR_genResDn[1:GENS, 1:HRS_FUCR]>=0) # Generator's down rserve schedule
    @variable(FUCRmodel, FUCR_TotGenVioP[g=1:GENS, 1:HRS_FUCR]>=0)
    @variable(FUCRmodel, FUCR_TotGenVioN[g=1:GENS, 1:HRS_FUCR]>=0)
    @variable(FUCRmodel, FUCR_MaxGenVioP[g=1:GENS, 1:HRS_FUCR]>=0)
    @variable(FUCRmodel, FUCR_MinGenVioP[g=1:GENS, 1:HRS_FUCR]>=0)

	# Declaring the decision variables for peaker units
    @variable(FUCRmodel, 0<=FUCR_peakerOnOff[1:PEAKERS, 0:HRS_FUCR]<=1)
    @variable(FUCRmodel, 0<=FUCR_peakerStartUp[1:PEAKERS, 1:HRS_FUCR]<=1)
    @variable(FUCRmodel, 0<=FUCR_peakerShutDown[1:PEAKERS, 1:HRS_FUCR]<=1)
    @variable(FUCRmodel, FUCR_peakerOut[1:PEAKERS, 0:HRS_FUCR]>=0) # Generator's output schedule
    @variable(FUCRmodel, FUCR_peakerOut_Block[1:PEAKERS, 1:BLOCKS, 1:HRS_FUCR]>=0) # Generator's output schedule from each block (block rfers to IHR curve blocks/segments)
    @variable(FUCRmodel, FUCR_peakerResUp[1:PEAKERS, 1:HRS_FUCR]>=0) # Generators' up reserve schedule
    @variable(FUCRmodel, FUCR_peakerResNonSpin[1:PEAKERS, 1:HRS_FUCR]>=0) # Scheduled up reserve on offline fast-start peakers
    @variable(FUCRmodel, FUCR_peakerResDn[1:PEAKERS, 1:HRS_FUCR]>=0) # Generator's down rserve schedule

    # declaring decision variables for storage Units
    @variable(FUCRmodel, FUCR_storgChrg[1:STORG_UNITS, 1:HRS_FUCR], Bin) #Bin variable equal to 1 if unit runs in the charging mode
    @variable(FUCRmodel, FUCR_storgDisc[1:STORG_UNITS, 1:HRS_FUCR], Bin) #Bin variable equal to 1 if unit runs in the discharging mode
    @variable(FUCRmodel, FUCR_storgIdle[1:STORG_UNITS, 1:HRS_FUCR], Bin) ##Bin variable equal to 1 if unit runs in the idle mode
    @variable(FUCRmodel, FUCR_storgChrgPwr[1:STORG_UNITS, 0:HRS_FUCR]>=0) #Chargung power
    @variable(FUCRmodel, FUCR_storgDiscPwr[1:STORG_UNITS, 0:HRS_FUCR]>=0) # Discharging Power
    @variable(FUCRmodel, FUCR_storgSOC[1:STORG_UNITS, 0:HRS_FUCR]>=0) # state of charge (stored energy level for storage unit at time t)
    @variable(FUCRmodel, FUCR_storgResUp[1:STORG_UNITS, 0:HRS_FUCR]>=0) # Scheduled up reserve
    @variable(FUCRmodel, FUCR_storgResDn[1:STORG_UNITS, 0:HRS_FUCR]>=0) # Scheduled down reserve

    # declaring decision variables for renewable generation
    @variable(FUCRmodel, FUCR_solarG[1:N_ZONES, 1:HRS_FUCR]>=0) # solar energy schedules
    @variable(FUCRmodel, FUCR_windG[1:N_ZONES, 1:HRS_FUCR]>=0) # wind energy schedules
    @variable(FUCRmodel, FUCR_hydroG[1:N_ZONES, 1:HRS_FUCR]>=0) # hydro energy schedules
    @variable(FUCRmodel, FUCR_solarGSpil[1:N_ZONES, 1:HRS_FUCR]>=0) # solar energy schedules
    @variable(FUCRmodel, FUCR_windGSpil[1:N_ZONES, 1:HRS_FUCR]>=0) # wind energy schedules
    @variable(FUCRmodel, FUCR_hydroGSpil[1:N_ZONES, 1:HRS_FUCR]>=0) # hydro energy schedules

    # Declaring decision variables for hourly dispatched and curtailed demand
    @variable(FUCRmodel, FUCR_Demand[1:N_ZONES, 1:HRS_FUCR]>=0) # Hourly scheduled demand
    @variable(FUCRmodel, FUCR_Demand_Curt[1:N_ZONES, 1:HRS_FUCR]>=0) # Hourly schedule demand

    # Declaring variables for transmission system
    @variable(FUCRmodel, FUCR_voltAngle[1:N_ZONES, 1:HRS_FUCR]) #voltage angle at zone/bus n in t//
    @variable(FUCRmodel, FUCR_powerFlow[1:N_ZONES, 1:M_ZONES, 1:HRS_FUCR]) #transmission Flow from zone n to zone m//

    # Declaring over and undergeneration decision variable
    @variable(FUCRmodel, FUCR_OverGen[1:N_ZONES, 1:HRS_FUCR]>=0) #overgeneration at zone n and time t//

    # Defining the objective function that minimizes the overal cost of supplying electricity (=total variable, no-load, startup, and shutdown costs)
    @objective(FUCRmodel, Min, sum(sum(DF_Generators.IHRC_B1_HR[g]*FuelPrice[g,day]*FUCR_genOut_Block[g,1,t]
                                       +DF_Generators.IHRC_B2_HR[g]*FuelPrice[g,day]*FUCR_genOut_Block[g,2,t]
                                       +DF_Generators.IHRC_B3_HR[g]*FuelPrice[g,day]*FUCR_genOut_Block[g,3,t]
                                       +DF_Generators.IHRC_B4_HR[g]*FuelPrice[g,day]*FUCR_genOut_Block[g,4,t]
                                       +DF_Generators.IHRC_B5_HR[g]*FuelPrice[g,day]*FUCR_genOut_Block[g,5,t]
                                       +DF_Generators.IHRC_B6_HR[g]*FuelPrice[g,day]*FUCR_genOut_Block[g,6,t]
                                       +DF_Generators.IHRC_B7_HR[g]*FuelPrice[g,day]*FUCR_genOut_Block[g,7,t]
                                       +DF_Generators.NoLoadHR[g]*FuelPrice[g,day]*FUCR_genOnOff[g,t]
                                       +((DF_Generators.HotStartU_FixedCost[g]
                                       +(DF_Generators.HotStartU_HeatRate[g]*FuelPrice[g,day]))*FUCR_genStartUp[g,t])
                                       +DF_Generators.ShutdownCost[g]*FUCR_genShutDown[g, t]
                                       +(FUCR_TotGenVioP[g,t]*VIOLATION_PENALTY)
                                       +(FUCR_TotGenVioN[g,t]*VIOLATION_PENALTY)
                                       +(FUCR_MaxGenVioP[g,t]*VIOLATION_PENALTY)
                                       +(FUCR_MinGenVioP[g,t]*VIOLATION_PENALTY) for g in 1:GENS)
                                       +sum(DF_Peakers.IHRC_B1_HR[k]*FuelPricePeakers[k,day]*FUCR_peakerOut_Block[k,1,t]
                                       +DF_Peakers.IHRC_B2_HR[k]*FuelPricePeakers[k,day]*FUCR_peakerOut_Block[k,2,t]
                                       +DF_Peakers.IHRC_B3_HR[k]*FuelPricePeakers[k,day]*FUCR_peakerOut_Block[k,3,t]
                                       +DF_Peakers.IHRC_B4_HR[k]*FuelPricePeakers[k,day]*FUCR_peakerOut_Block[k,4,t]
                                       +DF_Peakers.IHRC_B5_HR[k]*FuelPricePeakers[k,day]*FUCR_peakerOut_Block[k,5,t]
                                       +DF_Peakers.IHRC_B6_HR[k]*FuelPricePeakers[k,day]*FUCR_peakerOut_Block[k,6,t]
                                       +DF_Peakers.IHRC_B7_HR[k]*FuelPricePeakers[k,day]*FUCR_peakerOut_Block[k,7,t]
                                       +DF_Peakers.NoLoadHR[k]*FuelPricePeakers[k,day]*FUCR_peakerOnOff[k,t]
                                       +((DF_Peakers.HotStartU_FixedCost[k]
                                       +(DF_Peakers.HotStartU_HeatRate[k]*FuelPricePeakers[k,day]))*FUCR_peakerStartUp[k,t])
                                       +DF_Peakers.ShutdownCost[k]*FUCR_peakerShutDown[k, t] for k in 1:PEAKERS) for t in 1:HRS_FUCR)
                                       +sum(sum((FUCR_Demand_Curt[n,t]*LOAD_SHED_PENALTY)
                                       +(FUCR_OverGen[n,t]*OVERGEN_PENALTY) for n=1:N_ZONES) for t=1:HRS_FUCR))

#Initialization of commitment and dispatch variables for convnentioal generatoes at t=0 (representing the last hour of previous scheduling horizon day=day-1 and t=24)
    @constraint(FUCRmodel, conInitGenOnOff[g=1:GENS], FUCR_genOnOff[g,0]==FUCR.gens.onoff_init[g]) # initial generation level for generator g at t=0
    @constraint(FUCRmodel, conInitGenOut[g=1:GENS], FUCR_genOut[g,0]==FUCR.gens.power_out[g]) # initial on/off status for generators g at t=0
#Initialization of commitment and dispatch variables for peakers  at t=0 (representing the last hour of previous scheduling horizon day=day-1 and t=24)
    @constraint(FUCRmodel, conInitGenOnOff_Peakers[k=1:PEAKERS], FUCR_peakerOnOff[k,0]==FUCR.peakers.onoff_init[k]) # initial generation level for peaker k at t=0
    @constraint(FUCRmodel, conInitGenOut_Peakers[k=1:PEAKERS], FUCR_peakerOut[k,0]==FUCR.peakers.power_out[k]) # initial on/off status for peaker k at t=0
#Initialization of SOC variables for storage units at t=0 (representing the last hour of previous scheduling horizon day=day-1 and t=24)
    @constraint(FUCRmodel, conInitSOC[p=1:STORG_UNITS], FUCR_storgSOC[p,0]==FUCR.soc_init[p]) # SOC for storage unit p at t=0

#Base-Load Operation of nuclear Generators
    @constraint(FUCRmodel, conNuckBaseLoad[t=1:HRS_FUCR, g=1:GENS], FUCR_genOnOff[g,t]>=DF_Generators.Nuclear[g]) #
    @constraint(FUCRmodel, conNuclearTotGenZone[t=1:HRS_FUCR, n=1:N_ZONES], sum((FUCR_genOut[g,t]*Map_Gens[g,n]*DF_Generators.Nuclear[g]) for g=1:GENS) -fucr_prep_demand.nuclear_wa[t,n] ==0)

#Limits on generation of cogen units
    @constraint(FUCRmodel, conCoGenBaseLoad[t=1:HRS_FUCR, g=1:GENS], FUCR_genOnOff[g,t]>=DF_Generators.Cogen[g]) #
    @constraint(FUCRmodel, conCoGenTotGenZone[t=1:HRS_FUCR, n=1:N_ZONES], sum((FUCR_genOut[g,t]*Map_Gens[g,n]*DF_Generators.Cogen[g]) for g=1:GENS) -fucr_prep_demand.cogen_wa[t,n] ==0)

# Constraints representing technical limits of conventional generators
#Status transition trajectory of
    @constraint(FUCRmodel, conStartUpAndDn[t=1:HRS_FUCR, g=1:GENS], (FUCR_genOnOff[g,t] - FUCR_genOnOff[g,t-1] - FUCR_genStartUp[g,t] + FUCR_genShutDown[g,t])==0)
# Max Power generation limit in Block 1
    @constraint(FUCRmodel, conMaxPowBlock1[t=1:HRS_FUCR, g=1:GENS],  FUCR_genOut_Block[g,1,t] <= DF_Generators.IHRC_B1_Q[g]*FUCR_genOnOff[g,t] )
# Max Power generation limit in Block 2
    @constraint(FUCRmodel, conMaxPowBlock2[t=1:HRS_FUCR, g=1:GENS],  FUCR_genOut_Block[g,2,t] <= DF_Generators.IHRC_B2_Q[g]*FUCR_genOnOff[g,t] )
# Max Power generation limit in Block 3
    @constraint(FUCRmodel, conMaxPowBlock3[t=1:HRS_FUCR, g=1:GENS],  FUCR_genOut_Block[g,3,t] <= DF_Generators.IHRC_B3_Q[g]*FUCR_genOnOff[g,t] )
# Max Power generation limit in Block 4
    @constraint(FUCRmodel, conMaxPowBlock4[t=1:HRS_FUCR, g=1:GENS],  FUCR_genOut_Block[g,4,t] <= DF_Generators.IHRC_B4_Q[g]*FUCR_genOnOff[g,t] )
# Max Power generation limit in Block 5
    @constraint(FUCRmodel, conMaxPowBlock5[t=1:HRS_FUCR, g=1:GENS],  FUCR_genOut_Block[g,5,t] <= DF_Generators.IHRC_B5_Q[g]*FUCR_genOnOff[g,t] )
# Max Power generation limit in Block 6
    @constraint(FUCRmodel, conMaxPowBlock6[t=1:HRS_FUCR, g=1:GENS],  FUCR_genOut_Block[g,6,t] <= DF_Generators.IHRC_B6_Q[g]*FUCR_genOnOff[g,t] )
# Max Power generation limit in Block 7
    @constraint(FUCRmodel, conMaxPowBlock7[t=1:HRS_FUCR, g=1:GENS],  FUCR_genOut_Block[g,7,t] <= DF_Generators.IHRC_B7_Q[g]*FUCR_genOnOff[g,t] )
# Total Production of each generation equals the sum of generation from its all blocks
    @constraint(FUCRmodel, conTotalGen[t=1:HRS_FUCR, g=1:GENS],  sum(FUCR_genOut_Block[g,b,t] for b=1:BLOCKS) + FUCR_TotGenVioP[g,t] - FUCR_TotGenVioN[g,t] ==FUCR_genOut[g,t])
#Max power generation limit
    @constraint(FUCRmodel, conMaxPow[t=1:HRS_FUCR, g=1:GENS],  FUCR_genOut[g,t]+FUCR_genResUp[g,t] - FUCR_MaxGenVioP[g,t] <= DF_Generators.MaxPowerOut[g]*FUCR_genOnOff[g,t] )
# Min power generation limit
    @constraint(FUCRmodel, conMinPow[t=1:HRS_FUCR, g=1:GENS],  FUCR_genOut[g,t]-FUCR_genResDn[g,t] + FUCR_MinGenVioP[g,t] >= DF_Generators.MinPowerOut[g]*FUCR_genOnOff[g,t] )
# Up reserve provision limit
    @constraint(FUCRmodel, conMaxResUp[t=1:HRS_FUCR, g=1:GENS], FUCR_genResUp[g,t] <= DF_Generators.SpinningRes_Limit[g]*FUCR_genOnOff[g,t] )
# Non-Spinning Reserve Limit
#    @constraint(FUCRmodel, conMaxNonSpinResUp[t=1:HRS_SUCR, g=1:GENS], FUCR_genResNonSpin[g,t] <= (DF_Generators.NonSpinningRes_Limit[g]*(1-FUCR_genOnOff[g,t])*DF_Generators.FastStart[g]))
    @constraint(FUCRmodel, conMaxNonSpinResUp[t=1:HRS_SUCR, g=1:GENS], FUCR_genResNonSpin[g,t] <= 0)
#Down reserve provision limit
    @constraint(FUCRmodel, conMaxResDown[t=1:HRS_FUCR, g=1:GENS],  FUCR_genResDn[g,t] <= DF_Generators.SpinningRes_Limit[g]*FUCR_genOnOff[g,t] )
#Up ramp rate limit
    @constraint(FUCRmodel, conRampRateUp[t=1:HRS_FUCR, g=1:GENS], (FUCR_genOut[g,t] - FUCR_genOut[g,t-1] <=(DF_Generators.RampUpLimit[g]*FUCR_genOnOff[g, t-1]) + (DF_Generators.RampStartUpLimit[g]*FUCR_genStartUp[g,t])))
# Down ramp rate limit
    @constraint(FUCRmodel, conRampRateDown[t=1:HRS_FUCR, g=1:GENS], (FUCR_genOut[g,t-1] - FUCR_genOut[g,t] <=(DF_Generators.RampDownLimit[g]*FUCR_genOnOff[g,t]) + (DF_Generators.RampShutDownLimit[g]*FUCR_genShutDown[g,t])))
# Min Up Time limit with alternative formulation
    @constraint(FUCRmodel, conUpTime[t=1:HRS_FUCR, g=1:GENS], (sum(FUCR_genStartUp[g,r] for r=lb_MUT[g,t]:t)<=FUCR_genOnOff[g,t]))
# Min down Time limit with alternative formulation
    @constraint(FUCRmodel, conDownTime[t=1:HRS_FUCR, g=1:GENS], (1-sum(FUCR_genShutDown[g,s] for s=lb_MDT[g,t]:t)>=FUCR_genOnOff[g,t]))

# Peaker Units' constraints
#Status transition trajectory of
    @constraint(FUCRmodel, conStartUpAndDn_Peaker[t=1:HRS_FUCR, k=1:PEAKERS], (FUCR_peakerOnOff[k,t] - FUCR_peakerOnOff[k,t-1] - FUCR_peakerStartUp[k,t] + FUCR_peakerShutDown[k,t])==0)
# Max Power generation limit in Block 1
    @constraint(FUCRmodel, conMaxPowBlock1_Peaker[t=1:HRS_FUCR, k=1:PEAKERS],  FUCR_peakerOut_Block[k,1,t] <= DF_Peakers.IHRC_B1_Q[k]*FUCR_peakerOnOff[k,t] )
# Max Power generation limit in Block 2
    @constraint(FUCRmodel, conMaxPowBlock2_Peaker[t=1:HRS_FUCR, k=1:PEAKERS],  FUCR_peakerOut_Block[k,2,t] <= DF_Peakers.IHRC_B2_Q[k]*FUCR_peakerOnOff[k,t] )
# Max Power generation limit in Block 3
    @constraint(FUCRmodel, conMaxPowBlock3_Peaker[t=1:HRS_FUCR, k=1:PEAKERS],  FUCR_peakerOut_Block[k,3,t] <= DF_Peakers.IHRC_B3_Q[k]*FUCR_peakerOnOff[k,t] )
# Max Power generation limit in Block 4
    @constraint(FUCRmodel, conMaxPowBlock4_Peaker[t=1:HRS_FUCR, k=1:PEAKERS],  FUCR_peakerOut_Block[k,4,t] <= DF_Peakers.IHRC_B4_Q[k]*FUCR_peakerOnOff[k,t] )
# Max Power generation limit in Block 5
    @constraint(FUCRmodel, conMaxPowBlock5_Peaker[t=1:HRS_FUCR, k=1:PEAKERS],  FUCR_peakerOut_Block[k,5,t] <= DF_Peakers.IHRC_B5_Q[k]*FUCR_peakerOnOff[k,t] )
# Max Power generation limit in Block 6
    @constraint(FUCRmodel, conMaxPowBlock6_Peaker[t=1:HRS_FUCR, k=1:PEAKERS],  FUCR_peakerOut_Block[k,6,t] <= DF_Peakers.IHRC_B6_Q[k]*FUCR_peakerOnOff[k,t] )
# Max Power generation limit in Block 7
    @constraint(FUCRmodel, conMaxPowBlock7_Peaker[t=1:HRS_FUCR, k=1:PEAKERS],  FUCR_peakerOut_Block[k,7,t] <= DF_Peakers.IHRC_B7_Q[k]*FUCR_peakerOnOff[k,t] )
# Total Production of each generation equals the sum of generation from its all blocks
    @constraint(FUCRmodel, conTotalGen_Peaker[t=1:HRS_FUCR, k=1:PEAKERS],  sum(FUCR_peakerOut_Block[k,b,t] for b=1:BLOCKS)>=FUCR_peakerOut[k,t])
#Max power generation limit
    @constraint(FUCRmodel, conMaxPow_Peaker[t=1:HRS_FUCR, k=1:PEAKERS],  FUCR_peakerOut[k,t]+FUCR_peakerResUp[k,t] <= DF_Peakers.MaxPowerOut[k]*FUCR_peakerOnOff[k,t] )
# Min power generation limit
    @constraint(FUCRmodel, conMinPow_Peaker[t=1:HRS_FUCR, k=1:PEAKERS],  FUCR_peakerOut[k,t]-FUCR_peakerResDn[k,t] >= DF_Peakers.MinPowerOut[k]*FUCR_peakerOnOff[k,t] )
# Up reserve provision limit
    @constraint(FUCRmodel, conMaxResUp_Peaker[t=1:HRS_FUCR, k=1:PEAKERS], FUCR_peakerResUp[k,t] <= DF_Peakers.SpinningRes_Limit[k]*FUCR_peakerOnOff[k,t] )
# Non-Spinning Reserve Limit
    @constraint(FUCRmodel, conMaxNonSpinResUp_Peaker[t=1:HRS_SUCR, k=1:PEAKERS], FUCR_peakerResNonSpin[k,t] <= (DF_Peakers.NonSpinningRes_Limit[k]*(1-FUCR_peakerOnOff[k,t])))
#Down reserve provision limit
    @constraint(FUCRmodel, conMaxResDown_Peaker[t=1:HRS_FUCR, k=1:PEAKERS],  FUCR_peakerResDn[k,t] <= DF_Peakers.SpinningRes_Limit[k]*FUCR_peakerOnOff[k,t] )
#Up ramp rate limit
    @constraint(FUCRmodel, conRampRateUp_Peaker[t=1:HRS_FUCR, k=1:PEAKERS], (FUCR_peakerOut[k,t] - FUCR_peakerOut[k,t-1] <=(DF_Peakers.RampUpLimit[k]*FUCR_peakerOnOff[k, t-1]) + (DF_Peakers.RampStartUpLimit[k]*FUCR_peakerStartUp[k,t])))
# Down ramp rate limit
    @constraint(FUCRmodel, conRampRateDown_Peaker[t=1:HRS_FUCR, k=1:PEAKERS], (FUCR_peakerOut[k,t-1] - FUCR_peakerOut[k,t] <=(DF_Peakers.RampDownLimit[k]*FUCR_peakerOnOff[k,t]) + (DF_Peakers.RampShutDownLimit[k]*FUCR_peakerShutDown[k,t])))
# Min Up Time limit with alternative formulation
    @constraint(FUCRmodel, conUpTime_Peaker[t=1:HRS_FUCR, k=1:PEAKERS], (sum(FUCR_peakerStartUp[k,r] for r=lb_MUT_Peaker[k,t]:t)<=FUCR_peakerOnOff[k,t]))
# Min down Time limit with alternative formulation
    @constraint(FUCRmodel, conDownTime_Peaker[t=1:HRS_FUCR, k=1:PEAKERS], (1-sum(FUCR_peakerShutDown[k,s] for s=lb_MDT_Peaker[k,t]:t)>=FUCR_peakerOnOff[k,t]))

    # Renewable generation constraints
    @constraint(FUCRmodel, conSolarLimit[t=1:HRS_FUCR, n=1:N_ZONES], FUCR_solarG[n, t] + FUCR_solarGSpil[n,t]<=fucr_prep_demand.solar_wa[t,n])
    @constraint(FUCRmodel, conWindLimit[t=1:HRS_FUCR, n=1:N_ZONES], FUCR_windG[n, t] + FUCR_windGSpil[n,t]<=fucr_prep_demand.wind_wa[t,n])
    @constraint(FUCRmodel, conHydroLimit[t=1:HRS_FUCR, n=1:N_ZONES], FUCR_hydroG[n, t] + FUCR_hydroGSpil[n,t]<=fucr_prep_demand.hydro_wa[t,n])

   #=
   @constraint(FUCRmodel, conSolarLimit[t=1:HRS_FUCR, n=1:N_ZONES], FUCR_solarG[n, t] + FUCR_solarGSpil[n,t]<=0)
   @constraint(FUCRmodel, conWindLimit[t=1:HRS_FUCR, n=1:N_ZONES], FUCR_windG[n, t] + FUCR_windGSpil[n,t]<=0)
   @constraint(FUCRmodel, conHydroLimit[t=1:HRS_FUCR, n=1:N_ZONES], FUCR_hydroG[n, t] + FUCR_hydroGSpil[n,t]<=0)
   =#

    # Constraints representing technical characteristics of storage units
    # status transition of storage units between charging, discharging, and idle modes
    @constraint(FUCRmodel, conStorgStatusTransition[t=1:HRS_FUCR, p=1:STORG_UNITS], (FUCR_storgChrg[p,t]+FUCR_storgDisc[p,t]+FUCR_storgIdle[p,t])==1)
# charging power limit
    @constraint(FUCRmodel, conStrgChargPowerLimit[t=1:HRS_FUCR, p=1:STORG_UNITS], (FUCR_storgChrgPwr[p,t] - FUCR_storgResDn[p,t])<=DF_Storage.Power[p]*FUCR_storgChrg[p,t])
# Discharging power limit
    @constraint(FUCRmodel, conStrgDisChgPowerLimit[t=1:HRS_FUCR, p=1:STORG_UNITS], (FUCR_storgDiscPwr[p,t] + FUCR_storgResUp[p,t])<=DF_Storage.Power[p]*FUCR_storgDisc[p,t])
# Down reserve provision limit
    @constraint(FUCRmodel, conStrgDownResrvMax[t=1:HRS_FUCR, p=1:STORG_UNITS], FUCR_storgResDn[p,t]<=DF_Storage.Power[p]*FUCR_storgChrg[p,t])
# Up reserve provision limit`
    @constraint(FUCRmodel, conStrgUpResrvMax[t=1:HRS_FUCR, p=1:STORG_UNITS], FUCR_storgResUp[p,t]<=DF_Storage.Power[p]*FUCR_storgDisc[p,t])
# State of charge at t
    @constraint(FUCRmodel, conStorgSOC[t=1:HRS_FUCR, p=1:STORG_UNITS], FUCR_storgSOC[p,t]==FUCR_storgSOC[p,t-1]-(FUCR_storgDiscPwr[p,t]/DF_Storage.TripEfficDown[p])+(FUCR_storgChrgPwr[p,t]*DF_Storage.TripEfficUp[p])-(FUCR_storgSOC[p,t]*DF_Storage.SelfDischarge[p]))
# minimum energy limit
    @constraint(FUCRmodel, conMinEnrgStorgLimi[t=1:HRS_FUCR, p=1:STORG_UNITS], FUCR_storgSOC[p,t]-(FUCR_storgResUp[p,t]/DF_Storage.TripEfficDown[p])+(FUCR_storgResDn[p,t]/DF_Storage.TripEfficUp[p])>=0)
# Maximum energy limit
    @constraint(FUCRmodel, conMaxEnrgStorgLimi[t=1:HRS_FUCR, p=1:STORG_UNITS], FUCR_storgSOC[p,t]-(FUCR_storgResUp[p,t]/DF_Storage.TripEfficDown[p])+(FUCR_storgResDn[p,t]/DF_Storage.TripEfficUp[p])<=(DF_Storage.Power[p]/DF_Storage.PowerToEnergRatio[p]))
# Constraints representing transmission grid capacity constraints
# DC Power Flow Calculation
    #@constraint(FUCRmodel, conDCPowerFlowPos[t=1:HRS_FUCR, n=1:N_ZONES, m=1:N_ZONES], FUCR_powerFlow[n,m,t]-(TranS[n,m]*(FUCR_voltAngle[n,t]-FUCR_voltAngle[m,t])) ==0)
    @constraint(FUCRmodel, conDCPowerFlowNeg[t=1:HRS_FUCR, n=1:N_ZONES, m=1:N_ZONES], FUCR_powerFlow[n,m,t]+FUCR_powerFlow[m,n,t]==0)
# Tranmission flow bounds (from n to m and from m to n)
    @constraint(FUCRmodel, conPosFlowLimit[t=1:HRS_FUCR, n=1:N_ZONES, m=1:N_ZONES], FUCR_powerFlow[n,m,t]<=TranC[n,m])
    @constraint(FUCRmodel, conNegFlowLimit[t=1:HRS_FUCR, n=1:N_ZONES, m=1:N_ZONES], FUCR_powerFlow[n,m,t]>=-TranC[n,m])
# Voltage Angle bounds and reference point
    #@constraint(FUCRmodel, conVoltAnglUB[t=1:HRS_FUCR, n=1:N_ZONES], FUCR_voltAngle[n,t]<=π)
    #@constraint(FUCRmodel, conVoltAnglLB[t=1:HRS_FUCR, n=1:N_ZONES], FUCR_voltAngle[n,t]>=-π)
    #@constraint(FUCRmodel, conVoltAngRef[t=1:HRS_FUCR], FUCR_voltAngle[1,t]==0)

    # Demand-side Constraints
    @constraint(FUCRmodel, conDemandLimit[t=1:HRS_FUCR, n=1:N_ZONES], FUCR_Demand[n,t]+ FUCR_Demand_Curt[n,t] == fucr_prep_demand.wk_ahead[t,n])

    # Demand Curtailment and wind generation limits
    @constraint(FUCRmodel, conDemandCurtLimit[t=1:HRS_FUCR, n=1:N_ZONES], FUCR_Demand_Curt[n,t] <= LOAD_SHED_MAX);
    @constraint(FUCRmodel, conOverGenLimit[t=1:HRS_FUCR, n=1:N_ZONES], FUCR_OverGen[n,t] <= OVERGEN_MAX);

    # System-wide Constraints
    #nodal balance constraint
    @constraint(FUCRmodel, conNodBalanc[t=1:HRS_FUCR, n=1:N_ZONES], sum((FUCR_genOut[g,t]*Map_Gens[g,n]) for g=1:GENS) +sum((FUCR_peakerOut[k,t]*Map_Peakers[k,n]) for k=1:PEAKERS)  + sum((FUCR_storgDiscPwr[p,t]*Map_Storage[p,n]) for p=1:STORG_UNITS) - sum((FUCR_storgChrgPwr[p,t]*Map_Storage[p,n]) for p=1:STORG_UNITS) +FUCR_solarG[n, t] +FUCR_windG[n, t] +FUCR_hydroG[n, t] - FUCR_Demand[n,t] - FUCR_OverGen[n,t]== sum(FUCR_powerFlow[n,m,t] for m=1:M_ZONES))

     #@constraint(FUCRmodel, conNodBalanc[t=1:HRS_FUCR], sum(FUCR_genOut[g,t] for g=1:GENS) + sum((FUCR_storgDiscPwr[p,t]) for p=1:STORG_UNITS) - sum((FUCR_storgChrgPwr[p,t]) for p=1:STORG_UNITS) +sum(FUCR_solarG[n, t] for n=1:N_ZONES) + sum(FUCR_windG[n, t] for n=1:N_ZONES)+ sum(FUCR_hydroG[n, t] for n=1:N_ZONES) - sum(fucr_prep_demand.wk_ahead[t,n] for n=1:N_ZONES) == 0)

    # @constraint(FUCRmodel, conNodBalanc[t=1:HRS_FUCR], sum((FUCR_genOut[g,t]) for g=1:GENS) + sum((FUCR_storgDiscPwr[p,t]) for p=1:STORG_UNITS) - sum((FUCR_storgChrgPwr[p,t]) for p=1:STORG_UNITS) +sum((FUCR_solarG[n, t]) for n=1:N_ZONES) +sum((FUCR_windG[n, t]) for n=1:N_ZONES) +sum((FUCR_hydroG[n, t]) for n=1:N_ZONES) - sum((fucr_prep_demand.wk_ahead[t,n]) for n=1:N_ZONES) == 0)
# Minimum zonal up reserve requirement, if there are more than two zones, we should  define reserve regions for DEC and DEP
     #@constraint(FUCRmodel, conMinUpReserveReq[t=1:HRS_FUCR, n=1:N_ZONES], sum((FUCR_genResUp[g,t]*Map_Gens[g,n]) for g=1:GENS) + sum((FUCR_storgResUp[p,t]*Map_Storage[p,n]) for p=1:STORG_UNITS) >= Reserve_Req_Up[n] )
     #@constraint(FUCRmodel, conMinUpReserveReq[t=1:HRS_FUCR], sum((FUCR_genResUp[g,t]+FUCR_genResNonSpin[g,t]) for g=1:GENS) + sum((FUCR_storgResUp[p,t]) for p=1:STORG_UNITS) >= sum(Reserve_Req_Up[n] for n=1:N_ZONES))
     @constraint(FUCRmodel, conMinUpReserveReq[t=1:HRS_FUCR], sum((FUCR_genResUp[g,t]) for g=1:GENS) + sum((FUCR_peakerResUp[k,t]+FUCR_peakerResNonSpin[k,t]) for k=1:PEAKERS)+ sum((FUCR_storgResUp[p,t]) for p=1:STORG_UNITS) >= sum(Reserve_Req_Up[n] for n=1:N_ZONES))


# Minimum down reserve requirement
#    @constraint(FUCRmodel, conMinDnReserveReq[t=1:HRS_FUCR], sum(genResDn[g,t] for g=1:GENS) + sum(storgResDn[p,t] for p=1:STORG_UNITS) >= Reserve_Req_Dn[t] )

    t2_FUCRmodel = time_ns()
    time_FUCRmodel = (t2_FUCRmodel -t1_FUCRmodel)/1.0e9;
    @info "FUCRmodel for day: $day setup executed in (s): $time_FUCRmodel";

    open(".//outputs//csv//time_performance.csv", FILE_ACCESS_APPEND) do io
            writedlm(io, hcat("FUCRmodel", time_FUCRmodel, "day: $day",
                    "", "", "Model Setup"), ',')
    end; # closes file

# solve the First WAUC model (FUCR)
    JuMP.optimize!(FUCRmodel)

# Pricing general results in the terminal window
    println("Objective value: ", JuMP.objective_value(FUCRmodel))

    println("------------------------------------")
    println("------- FUCR OBJECTIVE VALUE -------")
    println("Objective value for day ", day, " is ", JuMP.objective_value(FUCRmodel))
    println("------------------------------------")
    println("-------FUCR PRIMAL STATUS -------")
    println(primal_status(FUCRmodel))
    println("------------------------------------")
    println("------- FUCR DUAL STATUS -------")
    println(JuMP.dual_status(FUCRmodel))
    println("Day: ", day, " solved")
    println("---------------------------")
    println("FUCRmodel Number of variables: ", JuMP.num_variables(FUCRmodel))
    @info "FUCRmodel Number of variables: " JuMP.num_variables(FUCRmodel)

    open(".//outputs//csv//time_performance.csv", FILE_ACCESS_APPEND) do io
            writedlm(io, hcat("FUCRmodel", JuMP.num_variables(FUCRmodel), "day: $day",
                    "", "", "Variables"), ',')
    end;

    @debug "FUCRmodel for day: $day optimized executed in (s):  $(solve_time(FUCRmodel))";

    open(".//outputs//csv//time_performance.csv", FILE_ACCESS_APPEND) do io
            writedlm(io, hcat("FUCRmodel", solve_time(FUCRmodel), "day: $day",
                    "", "", "Model Optimization"), ',')
    end; # closes file

# Write the conventional generators' schedules in CSV file
    t1_write_FUCRmodel_results = time_ns()
    open(".//outputs//csv//FUCR_GenOutputs.csv", FILE_ACCESS_APPEND) do io
        for t in 1:HRS_FUCR, g=1:GENS
            writedlm(io, hcat(day, t+INIT_HR_FUCR, g, DF_Generators.UNIT_NAME[g],
                DF_Generators.MinPowerOut[g], DF_Generators.MaxPowerOut[g],
                JuMP.value.(FUCR_genOut[g,t]), JuMP.value.(FUCR_genOnOff[g,t]),
                JuMP.value.(FUCR_genShutDown[g,t]), JuMP.value.(FUCR_genStartUp[g,t]),
                JuMP.value.(FUCR_genResUp[g,t]), JuMP.value.(FUCR_genResNonSpin[g,t]),
                JuMP.value.(FUCR_genResDn[g,t]), JuMP.value.(FUCR_TotGenVioP[g,t]),
                JuMP.value.(FUCR_TotGenVioN[g,t]), JuMP.value.(FUCR_MaxGenVioP[g,t]),
                JuMP.value.(FUCR_MinGenVioP[g,t]) ), ',')
        end # ends the loop
    end; # closes file
# Write the peakers' schedules in CSV file
    open(".//outputs//csv//FUCR_PeakerOutputs.csv", FILE_ACCESS_APPEND) do io
        for t in 1:HRS_FUCR, k=1:PEAKERS
            writedlm(io, hcat(day, t+INIT_HR_FUCR, k, DF_Peakers.UNIT_NAME[k],
               DF_Peakers.MinPowerOut[k], DF_Peakers.MaxPowerOut[k],
               JuMP.value.(FUCR_peakerOut[k,t]), JuMP.value.(FUCR_peakerOnOff[k,t]),
               JuMP.value.(FUCR_peakerShutDown[k,t]), JuMP.value.(FUCR_peakerStartUp[k,t]),
               JuMP.value.(FUCR_peakerResUp[k,t]), JuMP.value.(FUCR_peakerResNonSpin[k,t]),
               JuMP.value.(FUCR_peakerResDn[k,t]) ), ',')
        end # ends the loop
    end; # closes file

    # Writing storage units' optimal schedules in CSV file
    open(".//outputs//csv//FUCR_StorageOutputs.csv", FILE_ACCESS_APPEND) do io
         for t in 1:HRS_FUCR, p=1:STORG_UNITS
            writedlm(io, hcat(day, t+INIT_HR_FUCR, p, DF_Storage.Name[p],
                DF_Storage.Power[p], DF_Storage.Power[p]/DF_Storage.PowerToEnergRatio[p],
                JuMP.value.(FUCR_storgChrg[p,t]), JuMP.value.(FUCR_storgDisc[p,t]),
                JuMP.value.(FUCR_storgIdle[p,t]), JuMP.value.(FUCR_storgChrgPwr[p,t]),
                JuMP.value.(FUCR_storgDiscPwr[p,t]), JuMP.value.(FUCR_storgSOC[p,t]),
                JuMP.value.(FUCR_storgResUp[p,t]), JuMP.value.(FUCR_storgResDn[p,t]) ), ',')
         end # ends the loop
    end; # closes file

    # Writing the transmission line flows in CSV file
    open(".//outputs//csv//FUCR_TranFlowOutputs.csv", FILE_ACCESS_APPEND) do io
        for t in 1:HRS_FUCR, n=1:N_ZONES, m=1:M_ZONES
           writedlm(io, hcat(day, t+INIT_HR_FUCR, n,
               JuMP.value.(FUCR_powerFlow[n,m,t]), TranC[n,m] ), ',')
        end # ends the loop
    end; # closes file

    # Writing the curtilment, overgeneration, and spillage outcomes in CSV file
    open(".//outputs//csv//FUCR_Curtail.csv", FILE_ACCESS_APPEND) do io
        for t in 1:HRS_FUCR, n=1:N_ZONES
           writedlm(io, hcat(day, t+INIT_HR_FUCR, n,
               JuMP.value.(FUCR_OverGen[n,t]), JuMP.value.(FUCR_Demand_Curt[n,t]),
               JuMP.value.(FUCR_windGSpil[n,t]), JuMP.value.(FUCR_solarGSpil[n,t]),
               JuMP.value.(FUCR_hydroGSpil[n,t])), ',')
        end # ends the loop
    end; # closes file

    t2_write_FUCRmodel_results = time_ns()

    time_write_FUCRmodel_results = (t2_write_FUCRmodel_results -t1_write_FUCRmodel_results)/1.0e9;
    @info "Write FUCRmodel results for day $day: $time_write_FUCRmodel_results executed in (s)";

    open(".//outputs//csv//time_performance.csv", FILE_ACCESS_APPEND) do io
            writedlm(io, hcat("FUCRmodel", time_write_FUCRmodel_results, "day: $day",
                    "", "", "Write CSV files"), ',')
    end; #closes file

## Create and save the following parameters to be passed to BUCR1
    t1_FUCRtoBUCR1_data_hand = time_ns()
    for h=1:INIT_HR_SUCR-INIT_HR_FUCR
        for g=1:GENS
            global FUCRtoBUCR1_genOnOff[g,h]= JuMP.value.(FUCR_genOnOff[g,h]);
            global FUCRtoBUCR1_genOut[g,h]= JuMP.value.(FUCR_genOut[g,h]);
            global FUCRtoBUCR1_genStartUp[g,h]= JuMP.value.(FUCR_genStartUp[g,h]);
            global FUCRtoBUCR1_genShutDown[g,h]=JuMP.value.(FUCR_genShutDown[g,h]);
            for b=1:BLOCKS
                FUCRtoBUCR1_genOut_Block[g,b,h]=JuMP.value.(FUCR_genOut_Block[g,b,h]);
            end
        end
        for k=1:PEAKERS
            global FUCRtoBUCR1_peakerOnOff[k,h]= round(JuMP.value.(FUCR_peakerOnOff[k,h]));
            global FUCRtoBUCR1_peakerOut[k,h]=JuMP.value.(FUCR_peakerOut[k,h]);
            global FUCRtoBUCR1_peakerStartUp[k,h]= round(JuMP.value.(FUCR_peakerStartUp[k,h]));
            global FUCRtoBUCR1_peakerShutDown[k,h]= round(JuMP.value.(FUCR_peakerShutDown[k,h]));
            for b=1:BLOCKS
                FUCRtoBUCR1_peakerOut_Block[k,b,h]=JuMP.value.(FUCR_peakerOut_Block[k,b,h]);
            end
        end
        for p=1:STORG_UNITS
            global FUCRtoBUCR1_storgChrg[p,h]=JuMP.value.(FUCR_storgChrg[p,h]);
            global FUCRtoBUCR1_storgDisc[p,h]=JuMP.value.(FUCR_storgDisc[p,h]);
            global FUCRtoBUCR1_storgIdle[p,h]=JuMP.value.(FUCR_storgIdle[p,h]);
            global FUCRtoBUCR1_storgChrgPwr[p,h]=JuMP.value.(FUCR_storgChrgPwr[p,h]);
            global FUCRtoBUCR1_storgDiscPwr[p,h]=JuMP.value.(FUCR_storgDiscPwr[p,h]);
            global FUCRtoBUCR1_storgSOC[p,h]=JuMP.value.(FUCR_storgSOC[p,h]);
        end
    end

    t2_FUCRtoBUCR1_data_hand = time_ns();

    time_FUCRtoBUCR1_data_hand = (t2_FUCRtoBUCR1_data_hand -t1_FUCRtoBUCR1_data_hand)/1.0e9;
    @info "FUCRtoBUCR1 data handling for day $day executed in (s): $time_FUCRtoBUCR1_data_hand";

    open(".//outputs//csv//time_performance.csv", FILE_ACCESS_APPEND) do io
            writedlm(io, hcat("FUCRmodel", time_FUCRtoBUCR1_data_hand, "day: $day",
                    " ", "Pre-processing variables", "Data Manipulation"), ',')
    end; #closes file
## This block models the Balancing Unit Commitment Runs between the morning and evening UC Runs

    for h=1:INIT_HR_SUCR-INIT_HR_FUCR # number of BUCR periods in between FUCR and SUCR
        # Pre-processing demand variables
        t1_BUCR_SUCR_data_hand = time_ns()
        D_Rng_BUCR1 = ((day-1)*24)+INIT_HR_FUCR+h  # Bottom cell of the demand data needed for running the first WAUC run at 6 am with 7-day look-ahead horizon
        BUCR1_Hr_Demand = BUCR_Demands[D_Rng_BUCR1, :]
        BUCR1_Hr_SolarG = BUCR_SolarGs[D_Rng_BUCR1, :]
        BUCR1_Hr_WindG = BUCR_WindGs[D_Rng_BUCR1, :]
        BUCR1_Hr_HydroG = BUCR_HydroGs[D_Rng_BUCR1, :]
        BUCR1_Hr_NuclearG = BUCR_NuclearGs[D_Rng_BUCR1, :]
        BUCR1_Hr_CogenG = BUCR_CogenGs[D_Rng_BUCR1, :]

        # Preprocessing module that fixes the commitment of slow-start units to their FUCR's outcome and determines the binary commitment bounds for fast-start units dependent to their initial up/down time and minimum up/down time limits
        #if the units are slow their BAUC's commitment is fixed to their FUCR's schedule
        for g=1:GENS
            #if DF_Generators.FastStart[g]==0 #
            if FUCRtoBUCR1_genOnOff[g,h]==0
                global BUCR1_Commit_LB[g] = 0;
                global BUCR1_Commit_UB[g] = 0;
            else
                global BUCR1_Commit_LB[g] = 1;
                global BUCR1_Commit_UB[g] = 1;
            end
        end
        # if the units are fast their BAUC's commitment could be fixed to 0 or 1
        # or vary between 0 or 1 dependent to their initial up/down time and min up/down time
        for k=1:PEAKERS
            if BUCR1.peakers.dntime_init[k]==0
                if BUCR1.peakers.uptime_init[k]<DF_Peakers.MinUpTime[k]
                    global BUCR1_Commit_Peaker_LB[k] = 1;
                    global BUCR1_Commit_Peaker_UB[k] = 1;
                else
                    global BUCR1_Commit_Peaker_LB[k] = 0;
                    global BUCR1_Commit_Peaker_UB[k] = 1;
                end
            elseif BUCR1.peakers.dntime_init[k]<DF_Peakers.MinDownTime[k]
                global BUCR1_Commit_Peaker_LB[k] = 0;
                global BUCR1_Commit_Peaker_UB[k] = 0;
            else
                global BUCR1_Commit_Peaker_LB[k] = 0;
                global BUCR1_Commit_Peaker_UB[k] = 1;
            end
        end

        t2_BUCR_SUCR_data_hand = time_ns();

        time_BUCR_SUCR_data_hand = (t2_BUCR_SUCR_data_hand -t1_BUCR_SUCR_data_hand)/1.0e9;
        @info "BUCR_SUCR data handling for day $day executed in (s): $time_BUCR_SUCR_data_hand";

        open(".//outputs//csv//time_performance.csv", FILE_ACCESS_APPEND) do io
                writedlm(io, hcat("BUCR1model", time_BUCR_SUCR_data_hand, "day: $day",
                        "hour $(h+INIT_HR_FUCR)", "Pre-processing variables", "Data Manipulation"), ',')
        end; #closes file

        t1_BUCR1model = time_ns()
        BUCR1model = direct_model(CPLEX.Optimizer())
        set_optimizer_attribute(BUCR1model, "CPX_PARAM_EPGAP", SOLVER_EPGAP)

        # Declaring the decision variables for conventional generators
        @variable(BUCR1model, BUCR1_genOnOff[1:GENS], Bin) #Bin
        @variable(BUCR1model, BUCR1_genStartUp[1:GENS], Bin) # startup variable
        @variable(BUCR1model, BUCR1_genShutDown[1:GENS], Bin) # shutdown variable
        @variable(BUCR1model, BUCR1_genOut[1:GENS]>=0) # Generator's output schedule
        @variable(BUCR1model, BUCR1_genOut_Block[1:GENS, 1:BLOCKS]>=0) # Generator's output schedule from each block (block rfers to IHR curve blocks/segments)
        @variable(BUCR1model, BUCR1_TotGenVioP[g=1:GENS]>=0)
        @variable(BUCR1model, BUCR1_TotGenVioN[g=1:GENS]>=0)
        @variable(BUCR1model, BUCR1_MaxGenVioP[g=1:GENS]>=0)
        @variable(BUCR1model, BUCR1_MinGenVioP[g=1:GENS]>=0)
        #@variable(BUCR1model, BUCR1_genResUp[1:GENS]>=0) # Generators' up reserve schedule
        #@variable(BUCR1model, BUCR1_genResDn[1:GENS]>=0) # Generator's down rserve schedule

        # Declaring the decision variables for peakers
        @variable(BUCR1model, 0<=BUCR1_peakerOnOff[1:PEAKERS]<=1) #Bin, relaxed
        @variable(BUCR1model, 0<=BUCR1_peakerStartUp[1:PEAKERS]<=1) # startup variable
        @variable(BUCR1model, 0<=BUCR1_peakerShutDown[1:PEAKERS]<=1) # shutdown variable
        @variable(BUCR1model, BUCR1_peakerOut[1:PEAKERS]>=0) # Generator's output schedule
        @variable(BUCR1model, BUCR1_peakerOut_Block[1:PEAKERS, 1:BLOCKS]>=0) # Generator's output schedule from each block (block rfers to IHR curve blocks/segments)

        # declaring decision variables for storage Units
        @variable(BUCR1model, BUCR1_storgChrg[1:STORG_UNITS], Bin) #Bin variable equal to 1 if unit runs in the charging mode
        @variable(BUCR1model, BUCR1_storgDisc[1:STORG_UNITS], Bin) #Bin variable equal to 1 if unit runs in the discharging mode
        @variable(BUCR1model, BUCR1_storgIdle[1:STORG_UNITS], Bin) ##Bin variable equal to 1 if unit runs in the idle mode
        @variable(BUCR1model, BUCR1_storgChrgPwr[1:STORG_UNITS]>=0) #Chargung power
        @variable(BUCR1model, BUCR1_storgDiscPwr[1:STORG_UNITS]>=0) # Discharging Power
        @variable(BUCR1model, BUCR1_storgSOC[1:STORG_UNITS]>=0) # state of charge (stored energy level for storage unit at time t)
        #@variable(BUCR1model, BUCR1_storgResUp[1:STORG_UNITS]>=0) # Scheduled up reserve
        #@variable(BUCR1model, BUCR1_storgResDn[1:STORG_UNITS]>=0) # Scheduled down reserve

        # declaring decision variables for renewable generation
        @variable(BUCR1model, BUCR1_solarG[1:N_ZONES]>=0) # solar energy schedules
        @variable(BUCR1model, BUCR1_windG[1:N_ZONES]>=0) # wind energy schedules
        @variable(BUCR1model, BUCR1_hydroG[1:N_ZONES]>=0) # hydro energy schedules
        @variable(BUCR1model, BUCR1_solarGSpil[1:N_ZONES]>=0) # solar energy schedules
        @variable(BUCR1model, BUCR1_windGSpil[1:N_ZONES]>=0) # wind energy schedules
        @variable(BUCR1model, BUCR1_hydroGSpil[1:N_ZONES]>=0) # hydro energy schedules

        # Declaring decision variables for hourly dispatched and curtailed demand
        @variable(BUCR1model, BUCR1_Demand[1:N_ZONES]>=0) # Hourly scheduled demand
        @variable(BUCR1model, BUCR1_Demand_Curt[1:N_ZONES]>=0) # Hourly schedule demand
        @variable(BUCR1model, BUCR1_OverGen[1:N_ZONES]>=0) #

        # declaring variables for transmission system
        @variable(BUCR1model, BUCR1_voltAngle[1:N_ZONES]) #voltage angle at zone/bus n in t//
        @variable(BUCR1model, BUCR1_powerFlow[1:N_ZONES, 1:M_ZONES]) #transmission Flow from zone n to zone m//

        # Defining the objective function that minimizes the overal cost of supplying electricity (=total variable, no-load, startup, and shutdown costs)

        #@objective(BUCR1model, Min, sum(sum(DF_Generators.VariableCost[g]*BUCR1_genOut[g]+DF_Generators.NoLoadCost[g]*BUCR1_genOnOff[g] +DF_Generators.StartUpCost[g]*BUCR1_genStartUp[g] + DF_Generators.ShutdownCost[g]*BUCR1_genShutDown[g] for g in 1:GENS)))
        @objective(BUCR1model, Min, sum(DF_Generators.IHRC_B1_HR[g]*FuelPrice[g,day]*(BUCR1_genOut_Block[g,1])
                                           +DF_Generators.IHRC_B2_HR[g]*FuelPrice[g,day]*(BUCR1_genOut_Block[g,2])
                                           +DF_Generators.IHRC_B3_HR[g]*FuelPrice[g,day]*(BUCR1_genOut_Block[g,3])
                                           +DF_Generators.IHRC_B4_HR[g]*FuelPrice[g,day]*(BUCR1_genOut_Block[g,4])
                                           +DF_Generators.IHRC_B5_HR[g]*FuelPrice[g,day]*(BUCR1_genOut_Block[g,5])
                                           +DF_Generators.IHRC_B6_HR[g]*FuelPrice[g,day]*(BUCR1_genOut_Block[g,6])
                                           +DF_Generators.IHRC_B7_HR[g]*FuelPrice[g,day]*(BUCR1_genOut_Block[g,7])
                                           +DF_Generators.NoLoadHR[g]*FuelPrice[g,day]*(BUCR1_genOnOff[g])
                                           +((DF_Generators.HotStartU_FixedCost[g]+(DF_Generators.HotStartU_HeatRate[g]*FuelPrice[g,day]))*(BUCR1_genStartUp[g]))
                                           +DF_Generators.ShutdownCost[g]*(BUCR1_genShutDown[g])
                                           +(BUCR1_TotGenVioP[g]*VIOLATION_PENALTY)+(BUCR1_TotGenVioN[g]*VIOLATION_PENALTY)+(BUCR1_MaxGenVioP[g]*VIOLATION_PENALTY)+(BUCR1_MinGenVioP[g]*VIOLATION_PENALTY) for g in 1:GENS)
                                           +sum(DF_Peakers.IHRC_B1_HR[k]*FuelPricePeakers[k,day]*(BUCR1_peakerOut_Block[k,1])
                                           +DF_Peakers.IHRC_B2_HR[k]*FuelPricePeakers[k,day]*(BUCR1_peakerOut_Block[k,2])
                                           +DF_Peakers.IHRC_B3_HR[k]*FuelPricePeakers[k,day]*(BUCR1_peakerOut_Block[k,3])
                                           +DF_Peakers.IHRC_B4_HR[k]*FuelPricePeakers[k,day]*(BUCR1_peakerOut_Block[k,4])
                                           +DF_Peakers.IHRC_B5_HR[k]*FuelPricePeakers[k,day]*(BUCR1_peakerOut_Block[k,5])
                                           +DF_Peakers.IHRC_B6_HR[k]*FuelPricePeakers[k,day]*(BUCR1_peakerOut_Block[k,6])
                                           +DF_Peakers.IHRC_B7_HR[k]*FuelPricePeakers[k,day]*(BUCR1_peakerOut_Block[k,7])
                                           +DF_Peakers.NoLoadHR[k]*FuelPricePeakers[k,day]*(BUCR1_peakerOnOff[k])
                                           +((DF_Peakers.HotStartU_FixedCost[k]+(DF_Peakers.HotStartU_HeatRate[k]*FuelPricePeakers[k,day]))*(BUCR1_peakerStartUp[k]))
                                           +DF_Peakers.ShutdownCost[k]*(BUCR1_peakerShutDown[k]) for k in 1:PEAKERS)
                                           +sum((BUCR1_Demand_Curt[n]*LOAD_SHED_PENALTY)+(BUCR1_OverGen[n]*OVERGEN_PENALTY) for n=1:N_ZONES) )



     # Baseload Operation of nuclear units
        @constraint(BUCR1model, conNuckBaseLoad[g=1:GENS], BUCR1_genOnOff[g]>=DF_Generators.Nuclear[g]) #
        @constraint(BUCR1model, conNuclearTotGenZone[n=1:N_ZONES], sum((BUCR1_genOut[g]*Map_Gens[g,n]*DF_Generators.Nuclear[g]) for g=1:GENS) -BUCR1_Hr_NuclearG[n] ==0)

     #Limits on generation of cogen units
        @constraint(BUCR1model, conCoGenBaseLoad[g=1:GENS], BUCR1_genOnOff[g]>=DF_Generators.Cogen[g]) #
        @constraint(BUCR1model, conCoGenTotGenZone[n=1:N_ZONES], sum((BUCR1_genOut[g]*Map_Gens[g,n]*DF_Generators.Cogen[g]) for g=1:GENS) -BUCR1_Hr_CogenG[n] ==0)

    # Constraints representing technical limits of conventional generators
        #Status transition trajectory of
        @constraint(BUCR1model, conStartUpAndDn[g=1:GENS], (BUCR1_genOnOff[g] - BUCR1.gens.onoff_init[g] - BUCR1_genStartUp[g] + BUCR1_genShutDown[g])==0)
        # Max Power generation limit in Block 1
        @constraint(BUCR1model, conMaxPowBlock1[g=1:GENS],  BUCR1_genOut_Block[g,1] <= DF_Generators.IHRC_B1_Q[g]*BUCR1_genOnOff[g] )
        # Max Power generation limit in Block 2
        @constraint(BUCR1model, conMaxPowBlock2[g=1:GENS],  BUCR1_genOut_Block[g,2] <= DF_Generators.IHRC_B2_Q[g]*BUCR1_genOnOff[g] )
        # Max Power generation limit in Block 3
        @constraint(BUCR1model, conMaxPowBlock3[g=1:GENS],  BUCR1_genOut_Block[g,3] <= DF_Generators.IHRC_B3_Q[g]*BUCR1_genOnOff[g] )
        # Max Power generation limit in Block 4
        @constraint(BUCR1model, conMaxPowBlock4[g=1:GENS],  BUCR1_genOut_Block[g,4] <= DF_Generators.IHRC_B4_Q[g]*BUCR1_genOnOff[g] )
        # Max Power generation limit in Block 5
        @constraint(BUCR1model, conMaxPowBlock5[g=1:GENS],  BUCR1_genOut_Block[g,5] <= DF_Generators.IHRC_B5_Q[g]*BUCR1_genOnOff[g] )
        # Max Power generation limit in Block 6
        @constraint(BUCR1model, conMaxPowBlock6[g=1:GENS],  BUCR1_genOut_Block[g,6] <= DF_Generators.IHRC_B6_Q[g]*BUCR1_genOnOff[g] )
        # Max Power generation limit in Block 7
        @constraint(BUCR1model, conMaxPowBlock7[g=1:GENS],  BUCR1_genOut_Block[g,7] <= DF_Generators.IHRC_B7_Q[g]*BUCR1_genOnOff[g] )
        # Total Production of each generation equals the sum of generation from its all blocks
        @constraint(BUCR1model, conTotalGen[g=1:GENS],  sum(BUCR1_genOut_Block[g,b] for b=1:BLOCKS)+ BUCR1_TotGenVioP[g]-BUCR1_TotGenVioN[g]==BUCR1_genOut[g])
        #Max power generation limit
        @constraint(BUCR1model, conMaxPow[g=1:GENS],  BUCR1_genOut[g] - BUCR1_MaxGenVioP[g] <= DF_Generators.MaxPowerOut[g]*BUCR1_genOnOff[g])
        # Min power generation limit
        @constraint(BUCR1model, conMinPow[g=1:GENS],  BUCR1_genOut[g] + BUCR1_MinGenVioP[g] >= DF_Generators.MinPowerOut[g]*BUCR1_genOnOff[g])
        #Up ramp rate limit
        @constraint(BUCR1model, conRampRateUp[g=1:GENS], (BUCR1_genOut[g] - BUCR1.gens.power_out[g] <=(DF_Generators.RampUpLimit[g]*BUCR1.gens.onoff_init[g]) + (DF_Generators.RampStartUpLimit[g]*BUCR1_genStartUp[g])))
        # Down ramp rate limit
        @constraint(BUCR1model, conRampRateDown[g=1:GENS], (BUCR1.gens.power_out[g] - BUCR1_genOut[g] <=(DF_Generators.RampDownLimit[g]*BUCR1_genOnOff[g]) + (DF_Generators.RampShutDownLimit[g]*BUCR1_genShutDown[g])))
        # Min Up Time limit with alternative formulation
        #The next two constraints enforce limits on binary commitment variables of slow and fast generators
        # scheduled slow units are forced to remain on, offline slow units remain off, and fast start units
        # could change their commitment dependent on their MUT and MDT
        @constraint(BUCR1model, conCommitmentUB[g=1:GENS], (BUCR1_genOnOff[g] <= BUCR1_Commit_UB[g]))
        # if the generator is slow start and scheduled "on" in the FUCR,  is fixed by the following constraint
        @constraint(BUCR1model, conCommitmentLB[g=1:GENS], (BUCR1_genOnOff[g] >= BUCR1_Commit_LB[g]))


        # Constraints representing technical limits of peakers
        #Status transition trajectory of
        @constraint(BUCR1model, conStartUpAndDn_Peaker[k=1:PEAKERS], (BUCR1_peakerOnOff[k] - BUCR1.peakers.onoff_init[k] - BUCR1_peakerStartUp[k] + BUCR1_peakerShutDown[k])==0)
        # Max Power generation limit in Block 1
        @constraint(BUCR1model, conMaxPowBlock1_Peaker[k=1:PEAKERS],  BUCR1_peakerOut_Block[k,1] <= DF_Peakers.IHRC_B1_Q[k]*BUCR1_peakerOnOff[k] )
        # Max Power generation limit in Block 2
        @constraint(BUCR1model, conMaxPowBlock2_Peaker[k=1:PEAKERS],  BUCR1_peakerOut_Block[k,2] <= DF_Peakers.IHRC_B2_Q[k]*BUCR1_peakerOnOff[k] )
        # Max Power generation limit in Block 3
        @constraint(BUCR1model, conMaxPowBlock3_Peaker[k=1:PEAKERS],  BUCR1_peakerOut_Block[k,3] <= DF_Peakers.IHRC_B3_Q[k]*BUCR1_peakerOnOff[k] )
        # Max Power generation limit in Block 4
        @constraint(BUCR1model, conMaxPowBlock4_Peaker[k=1:PEAKERS],  BUCR1_peakerOut_Block[k,4] <= DF_Peakers.IHRC_B4_Q[k]*BUCR1_peakerOnOff[k] )
        # Max Power generation limit in Block 5
        @constraint(BUCR1model, conMaxPowBlock5_Peaker[k=1:PEAKERS],  BUCR1_peakerOut_Block[k,5] <= DF_Peakers.IHRC_B5_Q[k]*BUCR1_peakerOnOff[k] )
        # Max Power generation limit in Block 6
        @constraint(BUCR1model, conMaxPowBlock6_Peaker[k=1:PEAKERS],  BUCR1_peakerOut_Block[k,6] <= DF_Peakers.IHRC_B6_Q[k]*BUCR1_peakerOnOff[k] )
        # Max Power generation limit in Block 7
        @constraint(BUCR1model, conMaxPowBlock7_Peaker[k=1:PEAKERS],  BUCR1_peakerOut_Block[k,7] <= DF_Peakers.IHRC_B7_Q[k]*BUCR1_peakerOnOff[k] )
        # Total Production of each generation equals the sum of generation from its all blocks
        @constraint(BUCR1model, conTotalGen_Peaker[k=1:PEAKERS], sum(BUCR1_peakerOut_Block[k,b] for b=1:BLOCKS)>= BUCR1_peakerOut[k])
        #Max power generation limit
        @constraint(BUCR1model, conMaxPow_Peaker[k=1:PEAKERS],  BUCR1_peakerOut[k] <= DF_Peakers.MaxPowerOut[k]*BUCR1_peakerOnOff[k])
        # Min power generation limit
        @constraint(BUCR1model, conMinPow_Peaker[k=1:PEAKERS],  BUCR1_peakerOut[k] >= DF_Peakers.MinPowerOut[k]*BUCR1_peakerOnOff[k])
        #Up ramp rate limit
        @constraint(BUCR1model, conRampRateUp_Peaker[k=1:PEAKERS], (BUCR1_peakerOut[k] - BUCR1.peakers.power_out[k] <=(DF_Peakers.RampUpLimit[k]*BUCR1.peakers.onoff_init[k]) + (DF_Peakers.RampStartUpLimit[k]*BUCR1_peakerStartUp[k])))
        # Down ramp rate limit
        @constraint(BUCR1model, conRampRateDown_Peaker[k=1:PEAKERS], (BUCR1.peakers.power_out[k] - BUCR1_peakerOut[k] <=(DF_Peakers.RampDownLimit[k]*BUCR1_peakerOnOff[k]) + (DF_Peakers.RampShutDownLimit[k]*BUCR1_peakerShutDown[k])))
        # Min Up Time limit with alternative formulation
        #The next two constraints enforce limits on binary commitment variables of slow and fast generators
        # scheduled slow units are forced to remain on, offline slow units remain off, and fast start units
        # could change their commitment dependent on their MUT and MDT
        @constraint(BUCR1model, conCommitmentUB_Peaker[k=1:PEAKERS], (BUCR1_peakerOnOff[k] <= BUCR1_Commit_Peaker_UB[k]))
        # if the generator is slow start and scheduled "on" in the FUCR,  is fixed by the following constraint
        @constraint(BUCR1model, conCommitmentLB_Peaker[k=1:PEAKERS], (BUCR1_peakerOnOff[k] >= BUCR1_Commit_Peaker_LB[k]))


        # Renewable generation constraints
        @constraint(BUCR1model, conSolarLimit[n=1:N_ZONES], BUCR1_solarG[n] + BUCR1_solarGSpil[n]<=BUCR1_Hr_SolarG[n])
        @constraint(BUCR1model, conWindLimit[n=1:N_ZONES], BUCR1_windG[n] + BUCR1_windGSpil[n]<=BUCR1_Hr_WindG[n])
        @constraint(BUCR1model, conHydroLimit[n=1:N_ZONES], BUCR1_hydroG[n] + BUCR1_hydroGSpil[n]<=BUCR1_Hr_HydroG[n])

        # Constraints representing technical characteristics of storage units
        # the next three constraints fix the balancing charging/discharging/Idle status to their optimal outcomes as determined by FUCR
        @constraint(BUCR1model, conStorgChrgStatusFixed[p=1:STORG_UNITS], (BUCR1_storgChrg[p]==FUCRtoBUCR1_storgChrg[p,h]))
        @constraint(BUCR1model, conStorgDisChrgStatusFixed[p=1:STORG_UNITS], (BUCR1_storgDisc[p]==FUCRtoBUCR1_storgDisc[p,h]))
        @constraint(BUCR1model, conStorgIdleStatusFixed[p=1:STORG_UNITS], (BUCR1_storgIdle[p]==FUCRtoBUCR1_storgIdle[p,h]))

        # charging power limit
        @constraint(BUCR1model, conStrgChargPowerLimit[p=1:STORG_UNITS], (BUCR1_storgChrgPwr[p])<=DF_Storage.Power[p]*BUCR1_storgChrg[p])
        # Discharging power limit
        @constraint(BUCR1model, conStrgDisChgPowerLimit[p=1:STORG_UNITS], (BUCR1_storgDiscPwr[p])<=DF_Storage.Power[p]*BUCR1_storgDisc[p])
        # State of charge at t
        @constraint(BUCR1model, conStorgSOC[p=1:STORG_UNITS], BUCR1_storgSOC[p]==BUCR1.soc_init[p]-(BUCR1_storgDiscPwr[p]/DF_Storage.TripEfficDown[p])+(BUCR1_storgChrgPwr[p]*DF_Storage.TripEfficUp[p])-(BUCR1_storgSOC[p]*DF_Storage.SelfDischarge[p]))
        # minimum energy limit
        @constraint(BUCR1model, conMinEnrgStorgLimi[p=1:STORG_UNITS], BUCR1_storgSOC[p]>=0)
        # Maximum energy limit
        @constraint(BUCR1model, conMaxEnrgStorgLimi[p=1:STORG_UNITS], BUCR1_storgSOC[p]<=(DF_Storage.Power[p]/DF_Storage.PowerToEnergRatio[p]))

        # Constraints representing transmission grid capacity constraints
        # DC Power Flow Calculation
        #@constraint(BUCR1model, conDCPowerFlowPos[n=1:N_ZONES, m=1:N_ZONES], BUCR1_powerFlow[n,m]-(TranS[n,m]*(BUCR1_voltAngle[n]-BUCR1_voltAngle[m])) ==0)
        @constraint(BUCR1model, conDCPowerFlowNeg[n=1:N_ZONES, m=1:N_ZONES], BUCR1_powerFlow[n,m]+BUCR1_powerFlow[m,n]==0)
        # Tranmission flow bounds (from n to m and from m to n)
        @constraint(BUCR1model, conPosFlowLimit[n=1:N_ZONES, m=1:N_ZONES], BUCR1_powerFlow[n,m]<=TranC[n,m])
        @constraint(BUCR1model, conNegFlowLimit[n=1:N_ZONES, m=1:N_ZONES], BUCR1_powerFlow[n,m]>=-TranC[n,m])
        # Voltage Angle bounds and reference point
        #@constraint(BUCR1model, conVoltAnglUB[n=1:N_ZONES], BUCR1_voltAngle[n]<=π)
        #@constraint(BUCR1model, conVoltAnglLB[n=1:N_ZONES], BUCR1_voltAngle[n]>=-π)
        #@constraint(BUCR1model, conVoltAngRef, BUCR1_voltAngle[1]==0)

        # Demand-side Constraints
        @constraint(BUCR1model, conDemandLimit[n=1:N_ZONES], BUCR1_Demand[n]+ BUCR1_Demand_Curt[n] == BUCR1_Hr_Demand[n])

        # Demand Curtailment and wind generation limits
        @constraint(BUCR1model, conDemandCurtLimit[n=1:N_ZONES], BUCR1_Demand_Curt[n] <= LOAD_SHED_MAX);
        @constraint(BUCR1model, conOverGenLimit[n=1:N_ZONES], BUCR1_OverGen[n] <= OVERGEN_MAX);

        # System-wide Constraints
        #nodal balance constraint
        @constraint(BUCR1model, conNodBalanc[n=1:N_ZONES], sum((BUCR1_genOut[g]*Map_Gens[g,n]) for g=1:GENS) + sum((BUCR1_peakerOut[k]*Map_Peakers[k,n]) for k=1:PEAKERS) + sum((BUCR1_storgDiscPwr[p]*Map_Storage[p,n]) for p=1:STORG_UNITS) - sum((BUCR1_storgChrgPwr[p]*Map_Storage[p,n]) for p=1:STORG_UNITS) +BUCR1_solarG[n] +BUCR1_windG[n] +BUCR1_hydroG[n] - BUCR1_OverGen[n]- BUCR1_Demand[n] == sum(BUCR1_powerFlow[n,m] for m=1:M_ZONES))
        # Minimum up reserve requirement
        #    @constraint(BUCR1model, conMinUpReserveReq[t=1:N_Hrs_BUCR], sum(genResUp[g,t] for g=1:GENS) + sum(storgResUp[p,t] for p=1:STORG_UNITS) >= Reserve_Req_Up[t] )

        # Minimum down reserve requirement
        #    @constraint(BUCR1model, conMinDnReserveReq[t=1:N_Hrs_BUCR], sum(genResDn[g,t] for g=1:GENS) + sum(storgResDn[p,t] for p=1:STORG_UNITS) >= Reserve_Req_Dn[t] )

        t2_BUCR1model = time_ns()
        time_BUCR1model = (t2_BUCR1model -t1_BUCR1model)/1.0e9;
        @info "BUCR1model for day: $day, hour $(h+INIT_HR_FUCR) setup executed in (s):  $time_BUCR1model";

        open(".//outputs//csv//time_performance.csv", FILE_ACCESS_APPEND) do io
                writedlm(io, hcat("BUCR1model", time_BUCR1model, "day: $day",
                        "hour $(h+INIT_HR_FUCR)", "", "Model Setup"), ',')
        end; # closes file

        # solve the First WAUC model (BUCR)
        JuMP.optimize!(BUCR1model)

        # Pricing general results in the terminal window
        println("Objective value: ", JuMP.objective_value(BUCR1model))

        println("------------------------------------")
        println("------- BAUC1 OBJECTIVE VALUE -------")
        println("Objective value for day ", day, " and hour ", h+INIT_HR_FUCR," is: ", JuMP.objective_value(BUCR1model))
        println("------------------------------------")
        println("------- BAUC1 PRIMAL STATUS -------")
        println(primal_status(BUCR1model))
        println("------------------------------------")
        println("------- BAUC1 DUAL STATUS -------")
        println(JuMP.dual_status(BUCR1model))
        println("Day: ", day, " and hour ", h+INIT_HR_FUCR, ": solved")
        println("---------------------------")
        println("BUCR1model Number of variables: ", JuMP.num_variables(BUCR1model))
        @info "BUCR1model Number of variables: " JuMP.num_variables(BUCR1model)
        open(".//outputs//csv//time_performance.csv", FILE_ACCESS_APPEND) do io
                writedlm(io, hcat("BUCR1model", JuMP.num_variables(BUCR1model), "day: $day",
                        "hour $(h+INIT_HR_FUCR)", "", "Variables"), ',')
        end;

        @debug "BUCR1model for day: $day, hour $(h+INIT_HR_FUCR) optimized executed in (s): $(solve_time(BUCR1model))";

        t1_write_BUCR1model_results = time_ns()
        open(".//outputs//csv//time_performance.csv", FILE_ACCESS_APPEND) do io
                writedlm(io, hcat("BUCR1model", solve_time(BUCR1model), "day: $day",
                        "hour $(h+INIT_HR_FUCR)", "", "Model Optimization"), ',')
        end; # closes file

## Write the optimal outcomes into spreadsheets
# Later we need to include a variable for day so the cell number in which the results are printed is updated accordingly

# Write the conventional generators' schedules
        open(".//outputs//csv//BUCR_GenOutputs.csv", FILE_ACCESS_APPEND) do io
            for g=1:GENS
                writedlm(io, hcat(day, h+INIT_HR_FUCR, g, DF_Generators.UNIT_ID[g],
					DF_Generators.MinPowerOut[g], DF_Generators.MaxPowerOut[g],
					JuMP.value.(BUCR1_genOut[g]), JuMP.value.(BUCR1_genOnOff[g]),
					JuMP.value.(BUCR1_genShutDown[g]), JuMP.value.(BUCR1_genStartUp[g]), JuMP.value.(BUCR1_TotGenVioP[g]),
                    JuMP.value.(BUCR1_TotGenVioN[g]), JuMP.value.(BUCR1_MaxGenVioP[g]), JuMP.value.(BUCR1_MinGenVioP[g]) ), ',')
            end # ends the loop
        end; # closes file

# Write the conventional peakers' schedules
        open(".//outputs//csv//BUCR_PeakerOutputs.csv", FILE_ACCESS_APPEND) do io
            for k=1:PEAKERS
                writedlm(io, hcat(day, h+INIT_HR_FUCR, k, DF_Peakers.UNIT_ID[k],
                    DF_Peakers.MinPowerOut[k], DF_Peakers.MaxPowerOut[k],
                    JuMP.value.(BUCR1_peakerOut[k]), JuMP.value.(BUCR1_peakerOnOff[k]),
                    JuMP.value.(BUCR1_peakerShutDown[k]), JuMP.value.(BUCR1_peakerStartUp[k]) ), ',')
            end # ends the loop
        end; # closes file

# Writing storage units' optimal schedules in CSV file
        open(".//outputs//csv//BUCR_StorageOutputs.csv", FILE_ACCESS_APPEND) do io
            for p=1:STORG_UNITS
                writedlm(io, hcat(day, h+INIT_HR_FUCR, p, DF_Storage.Name[p],
					DF_Storage.Power[p], DF_Storage.Power[p]/DF_Storage.PowerToEnergRatio[p],
					JuMP.value.(BUCR1_storgChrg[p]), JuMP.value.(BUCR1_storgDisc[p]),
					JuMP.value.(BUCR1_storgIdle[p]), JuMP.value.(BUCR1_storgChrgPwr[p]),
					JuMP.value.(BUCR1_storgDiscPwr[p]), JuMP.value.(BUCR1_storgSOC[p]) ), ',')
            end # ends the loop
        end; # closes file

# Writing the transmission flow schedules in CSV file
        open(".//outputs//csv//BUCR_TranFlowOutputs.csv", FILE_ACCESS_APPEND) do io
            for n=1:N_ZONES, m=1:M_ZONES
                writedlm(io, hcat(day, h+INIT_HR_FUCR, n, m,
                    JuMP.value.(BUCR1_powerFlow[n,m]), TranC[n,m] ), ',')
            end # ends the loop
        end; # closes file

# Writing the curtilment, overgeneration, and spillage outcomes in CSV file
        open(".//outputs//csv//BUCR_Curtail.csv", FILE_ACCESS_APPEND) do io
            for n=1:N_ZONES
               writedlm(io, hcat(day, h+INIT_HR_FUCR, n,
                   JuMP.value.(BUCR1_OverGen[n]), JuMP.value.(BUCR1_Demand_Curt[n]),
                   JuMP.value.(BUCR1_windGSpil[n]), JuMP.value.(BUCR1_solarGSpil[n]),
                   JuMP.value.(BUCR1_hydroGSpil[n]) ), ',')
            end # ends the loop
        end; # closes file

        t2_write_BUCR1model_results = time_ns()
        time_write_BUCR1model_results = (t2_write_BUCR1model_results -t1_write_BUCR1model_results)/1.0e9;
        @info "Write BUCR1model results for day $day and hour $(h+INIT_HR_FUCR) executed in (s): $time_write_BUCR1model_results";

        open(".//outputs//csv//time_performance.csv", FILE_ACCESS_APPEND) do io
                writedlm(io, hcat("BUCR1model", time_write_BUCR1model_results, "day: $day",
                        "hour $(h+INIT_HR_FUCR)", "", "Write CSV files"), ',')
        end; #closes file
## Initilization of the next UC Run
    # This must be updated later when we run two WAUCs every day and then RTUCs
    # Setting initial values for BUCR1 (next hour), SUCR1, and BUCR2
        t1_BUCR1_init_next_UC = time_ns();

        for g=1:GENS
            global BUCR1.gens.onoff_init[g] = JuMP.value.(BUCR1_genOnOff[g]);
            global BUCR1.gens.power_out[g] = JuMP.value.(BUCR1_genOut[g]);
            if h==(INIT_HR_SUCR-INIT_HR_FUCR)
                global BUCR2.gens.onoff_init[g] = JuMP.value.(BUCR1_genOnOff[g]);
                global BUCR2.gens.power_out[g] = JuMP.value.(BUCR1_genOut[g]);
                global SUCR.gens.onoff_init[g] = JuMP.value.(BUCR1_genOnOff[g]);
                global SUCR.gens.power_out[g] = JuMP.value.(BUCR1_genOut[g]);
            end
        end

        for k=1:PEAKERS
            global BUCR1.peakers.onoff_init[k] = round(JuMP.value.(BUCR1_peakerOnOff[k]));
            global BUCR1.peakers.power_out[k] = JuMP.value.(BUCR1_peakerOut[k]);
            if h==(INIT_HR_SUCR-INIT_HR_FUCR)
                global BUCR2.peakers.onoff_init[k] = round(JuMP.value.(BUCR1_peakerOnOff[k]));
                global BUCR2.peakers.power_out[k] = JuMP.value.(BUCR1_peakerOut[k]);
                global SUCR.peakers.onoff_init[k] = round(JuMP.value.(BUCR1_peakerOnOff[k]));
                global SUCR.peakers.power_out[k] = JuMP.value.(BUCR1_peakerOut[k]);
            end
        end

        for p=1:STORG_UNITS
            BUCR1.soc_init[p]=JuMP.value.(BUCR1_storgSOC[p]);
            if h==(INIT_HR_SUCR-INIT_HR_FUCR)
                global BUCR2.soc_init[p] = JuMP.value.(BUCR1_storgSOC[p]);
                global SUCR.soc_init[p] = JuMP.value.(BUCR1_storgSOC[p]);
            end
        end

        for g=1:GENS
            if JuMP.value.(BUCR1_genStartUp[g]) >= 0.5
                global BUCR1.gens.uptime_init[g]= 1;
                global BUCR1.gens.dntime_init[g] = 0;
            elseif JuMP.value.(BUCR1_genShutDown[g]) >= 0.5
                global BUCR1.gens.uptime_init[g]= 0;
                global BUCR1.gens.dntime_init[g]= 1;
            else
                if JuMP.value.(BUCR1_genOnOff[g]) >= 0.5
                    global BUCR1.gens.uptime_init[g]= BUCR1.gens.uptime_init[g]+1;
                    global BUCR1.gens.dntime_init[g]= 0;
                else
                    global BUCR1.gens.uptime_init[g]= 0;
                    global BUCR1.gens.dntime_init[g]= BUCR1.gens.dntime_init[g]+1;
                end
            end
            if h==(INIT_HR_SUCR-INIT_HR_FUCR)
                global BUCR2.gens.uptime_init[g]= BUCR1.gens.uptime_init[g];
                global BUCR2.gens.dntime_init[g]= BUCR1.gens.dntime_init[g];
                global SUCR.gens.uptime_init[g]= BUCR1.gens.uptime_init[g];
                global SUCR.gens.dntime_init[g]= BUCR1.gens.dntime_init[g];
            end
        end
        #TODO:No need to use the round function.  Since 0<= BUCR1_peakerStartUp<=1,
        # BUCR1_genStartUp>0 in the If Statement is enough
        for k=1:PEAKERS
            if (JuMP.value.(BUCR1_peakerStartUp[k]))>0
                global BUCR1.peakers.uptime_init[k]= 1;
                global BUCR1.peakers.dntime_init[k] = 0;
            elseif (JuMP.value.(BUCR1_peakerShutDown[k]))>0
                global BUCR1.peakers.uptime_init[k]= 0;
                global BUCR1.peakers.dntime_init[k]= 1;
            else
                if (JuMP.value.(BUCR1_peakerOnOff[k]))>0
                    global BUCR1.peakers.uptime_init[k]= BUCR1.peakers.uptime_init[k]+1;
                    global BUCR1.peakers.dntime_init[k]= 0;
                else
                    global BUCR1.peakers.uptime_init[k]= 0;
                    global BUCR1.peakers.dntime_init[k]= BUCR1.peakers.dntime_init[k]+1;
                end
            end
            if h==(INIT_HR_SUCR-INIT_HR_FUCR)
                global BUCR2.peakers.uptime_init[k]= BUCR1.peakers.uptime_init[k];
                global BUCR2.peakers.dntime_init[k]= BUCR1.peakers.dntime_init[k];
                global SUCR.peakers.uptime_init[k]= BUCR1.peakers.uptime_init[k];
                global SUCR.peakers.dntime_init[k]= BUCR1.peakers.dntime_init[k];
            end
        end

        t2_BUCR1_init_next_UC = time_ns();

        time_BUCR1_init_next_UC = (t2_BUCR1_init_next_UC -t1_BUCR1_init_next_UC)/1.0e9;
        @info "BUCR1_init_next_UC data handling for day $day and hour hour $(h+INIT_HR_FUCR) executed in (s): $time_BUCR1_init_next_UC";

        open(".//outputs//csv//time_performance.csv", FILE_ACCESS_APPEND) do io
                writedlm(io, hcat("BUCR1model", time_BUCR1_init_next_UC, "day: $day",
                        "hour $(h+INIT_HR_FUCR)", "BUCR1_init_next_UC", "Data Manipulation"), ',')
        end; #closes file

    end # ends the loop that runs hourly BUCR1 between [INIT_HR_FUCR and INIT_HR_SUCR)

## This block models the second UC optimization that is run in the evening

    t1_SUCRmodel = time_ns()
    SUCRmodel = direct_model(CPLEX.Optimizer())
    set_optimizer_attribute(SUCRmodel, "CPX_PARAM_EPGAP", SOLVER_EPGAP)

# Declaring the decision variables for conventional generators
    @variable(SUCRmodel, SUCR_genOnOff[1:GENS, 0:HRS_SUCR], Bin) #Bin
    @variable(SUCRmodel, SUCR_genStartUp[1:GENS, 1:HRS_SUCR], Bin) # startup variable
    @variable(SUCRmodel, SUCR_genShutDown[1:GENS, 1:HRS_SUCR], Bin) # shutdown variable
    @variable(SUCRmodel, SUCR_genOut[1:GENS, 0:HRS_SUCR]>=0) # Generator's output schedule
    @variable(SUCRmodel, SUCR_genOut_Block[1:GENS, 1:BLOCKS, 1:HRS_SUCR]>=0) # Generator's output schedule from each block (block rfers to IHR curve blocks/segments)
    @variable(SUCRmodel, SUCR_genResUp[1:GENS, 1:HRS_SUCR]>=0) # Generators' up reserve schedule
    @variable(SUCRmodel, SUCR_genResNonSpin[1:GENS, 1:HRS_SUCR]>=0) # Generators' up reserve schedule
    @variable(SUCRmodel, SUCR_genResDn[1:GENS, 1:HRS_SUCR]>=0) # Generator's down rserve schedule
    @variable(SUCRmodel, SUCR_TotGenVioP[g=1:GENS, 1:HRS_SUCR]>=0)
    @variable(SUCRmodel, SUCR_TotGenVioN[g=1:GENS, 1:HRS_SUCR]>=0)
    @variable(SUCRmodel, SUCR_MaxGenVioP[g=1:GENS, 1:HRS_SUCR]>=0)
    @variable(SUCRmodel, SUCR_MinGenVioP[g=1:GENS, 1:HRS_SUCR]>=0)

    # Declaring the decision variables for peakers
    @variable(SUCRmodel, 0<=SUCR_peakerOnOff[1:PEAKERS, 0:HRS_SUCR]<=1) #Bin, relaxed
    @variable(SUCRmodel, 0<=SUCR_peakerStartUp[1:PEAKERS, 1:HRS_SUCR]<=1) # startup variable
    @variable(SUCRmodel, 0<=SUCR_peakerShutDown[1:PEAKERS, 1:HRS_SUCR]<=1) # shutdown variable
    @variable(SUCRmodel, SUCR_peakerOut[1:PEAKERS, 0:HRS_SUCR]>=0) # Generator's output schedule
    @variable(SUCRmodel, SUCR_peakerOut_Block[1:PEAKERS, 1:BLOCKS, 1:HRS_SUCR]>=0) # Generator's output schedule from each block (block rfers to IHR curve blocks/segments)
    @variable(SUCRmodel, SUCR_peakerResUp[1:PEAKERS, 1:HRS_SUCR]>=0) # Generators' up reserve schedule
    @variable(SUCRmodel, SUCR_peakerResNonSpin[1:PEAKERS, 1:HRS_SUCR]>=0) # Generators' up reserve schedule
    @variable(SUCRmodel, SUCR_peakerResDn[1:PEAKERS, 1:HRS_SUCR]>=0) # Generator's down rserve schedule

# declaring decision variables for storage Units
    @variable(SUCRmodel, SUCR_storgChrg[1:STORG_UNITS, 1:HRS_SUCR], Bin) #Bin variable equal to 1 if unit runs in the charging mode
    @variable(SUCRmodel, SUCR_storgDisc[1:STORG_UNITS, 1:HRS_SUCR], Bin) #Bin variable equal to 1 if unit runs in the discharging mode
    @variable(SUCRmodel, SUCR_storgIdle[1:STORG_UNITS, 1:HRS_SUCR], Bin) ##Bin variable equal to 1 if unit runs in the idle mode
    @variable(SUCRmodel, SUCR_storgChrgPwr[1:STORG_UNITS, 0:HRS_SUCR]>=0) #Chargung power
    @variable(SUCRmodel, SUCR_storgDiscPwr[1:STORG_UNITS, 0:HRS_SUCR]>=0) # Discharging Power
    @variable(SUCRmodel, SUCR_storgSOC[1:STORG_UNITS, 0:HRS_SUCR]>=0) # state of charge (stored energy level for storage unit at time t)
    @variable(SUCRmodel, SUCR_storgResUp[1:STORG_UNITS, 0:HRS_SUCR]>=0) # Scheduled up reserve
    @variable(SUCRmodel, SUCR_storgResDn[1:STORG_UNITS, 0:HRS_SUCR]>=0) # Scheduled down reserve

    # declaring decision variables for renewable generation
    @variable(SUCRmodel, SUCR_solarG[1:N_ZONES, 1:HRS_SUCR]>=0) # solar energy schedules
    @variable(SUCRmodel, SUCR_windG[1:N_ZONES, 1:HRS_SUCR]>=0) # wind energy schedules
    @variable(SUCRmodel, SUCR_hydroG[1:N_ZONES, 1:HRS_SUCR]>=0) # hydro energy schedules
    @variable(SUCRmodel, SUCR_solarGSpil[1:N_ZONES, 1:HRS_SUCR]>=0) # solar energy schedules
    @variable(SUCRmodel, SUCR_windGSpil[1:N_ZONES, 1:HRS_SUCR]>=0) # wind energy schedules
    @variable(SUCRmodel, SUCR_hydroGSpil[1:N_ZONES, 1:HRS_SUCR]>=0) # hydro energy schedules

# Declaring decision variables for hourly dispatched and curtailed demand
    @variable(SUCRmodel, SUCR_Demand[1:N_ZONES, 1:HRS_SUCR]>=0) # Hourly scheduled demand
    @variable(SUCRmodel, SUCR_Demand_Curt[1:N_ZONES, 1:HRS_SUCR]>=0) # Hourly schedule demand

    @variable(SUCRmodel, SUCR_OverGen[1:N_ZONES, 1:HRS_SUCR]>=0) # Hourly schedule demand

# declaring variables for transmission system
    @variable(SUCRmodel, SUCR_voltAngle[1:N_ZONES, 1:HRS_SUCR]) #voltage angle at zone/bus n in t//
    @variable(SUCRmodel, SUCR_powerFlow[1:N_ZONES, 1:M_ZONES, 1:HRS_SUCR]) #transmission Flow from zone n to zone m//


# Defining the objective function that minimizes the overal cost of supplying electricity (=total variable, no-load, startup, and shutdown costs)
    @objective(SUCRmodel, Min, sum(sum(DF_Generators.IHRC_B1_HR[g]*FuelPrice[g,day]*SUCR_genOut_Block[g,1,t]
                                                   +DF_Generators.IHRC_B2_HR[g]*FuelPrice[g,day]*SUCR_genOut_Block[g,2,t]
                                                   +DF_Generators.IHRC_B3_HR[g]*FuelPrice[g,day]*SUCR_genOut_Block[g,3,t]
                                                   +DF_Generators.IHRC_B4_HR[g]*FuelPrice[g,day]*SUCR_genOut_Block[g,4,t]
                                                   +DF_Generators.IHRC_B5_HR[g]*FuelPrice[g,day]*SUCR_genOut_Block[g,5,t]
                                                   +DF_Generators.IHRC_B6_HR[g]*FuelPrice[g,day]*SUCR_genOut_Block[g,6,t]
                                                   +DF_Generators.IHRC_B7_HR[g]*FuelPrice[g,day]*SUCR_genOut_Block[g,7,t]
                                                   +DF_Generators.NoLoadHR[g]*FuelPrice[g,day]*SUCR_genOnOff[g,t] +((DF_Generators.HotStartU_FixedCost[g]+(DF_Generators.HotStartU_HeatRate[g]*FuelPrice[g,day]))*SUCR_genStartUp[g,t])
                                                   +DF_Generators.ShutdownCost[g]*SUCR_genShutDown[g, t]
                                                   +(SUCR_TotGenVioP[g,t]*VIOLATION_PENALTY)+(SUCR_TotGenVioN[g,t]*VIOLATION_PENALTY)+(SUCR_MaxGenVioP[g,t]*VIOLATION_PENALTY)+(SUCR_MinGenVioP[g,t]*VIOLATION_PENALTY) for g in 1:GENS)
                                                   +sum(DF_Peakers.IHRC_B1_HR[k]*FuelPricePeakers[k,day]*SUCR_peakerOut_Block[k,1,t]
                                                   +DF_Peakers.IHRC_B2_HR[k]*FuelPricePeakers[k,day]*SUCR_peakerOut_Block[k,2,t]
                                                   +DF_Peakers.IHRC_B3_HR[k]*FuelPricePeakers[k,day]*SUCR_peakerOut_Block[k,3,t]
                                                   +DF_Peakers.IHRC_B4_HR[k]*FuelPricePeakers[k,day]*SUCR_peakerOut_Block[k,4,t]
                                                   +DF_Peakers.IHRC_B5_HR[k]*FuelPricePeakers[k,day]*SUCR_peakerOut_Block[k,5,t]
                                                   +DF_Peakers.IHRC_B6_HR[k]*FuelPricePeakers[k,day]*SUCR_peakerOut_Block[k,6,t]
                                                   +DF_Peakers.IHRC_B7_HR[k]*FuelPricePeakers[k,day]*SUCR_peakerOut_Block[k,7,t]
                                                   +DF_Peakers.NoLoadHR[k]*FuelPricePeakers[k,day]*SUCR_peakerOnOff[k,t] +((DF_Peakers.HotStartU_FixedCost[k]+(DF_Peakers.HotStartU_HeatRate[k]*FuelPricePeakers[k,day]))*SUCR_peakerStartUp[k,t])
                                                   +DF_Peakers.ShutdownCost[k]*SUCR_peakerShutDown[k, t] for k in 1:PEAKERS) for t in 1:HRS_SUCR)
                                                   +sum(sum((SUCR_Demand_Curt[n,t]*LOAD_SHED_PENALTY)+(SUCR_OverGen[n,t]*OVERGEN_PENALTY) for n=1:N_ZONES) for t=1:HRS_SUCR))


#Initialization of commitment and dispatch variables for slow-start generators at t=0 (representing the last hour of previous scheduling horizon day=day-1 and t=24)
    @constraint(SUCRmodel, conInitGenOnOff[g=1:GENS], SUCR_genOnOff[g,0]==SUCR.gens.onoff_init[g]) # initial generation level for generator g at t=0
    @constraint(SUCRmodel, conInitGenOut[g=1:GENS], SUCR_genOut[g,0]==SUCR.gens.power_out[g]) # initial on/off status for generators g at t=0
#Initialization of commitment and dispatch variables for peakers at t=0 (representing the last hour of previous scheduling horizon day=day-1 and t=24)
    @constraint(SUCRmodel, conInitGenOnOff_Peaker[k=1:PEAKERS], SUCR_peakerOnOff[k,0]==SUCR.peakers.onoff_init[k]) # initial generation level for peaker k at t=0
    @constraint(SUCRmodel, conInitGenOut_Peaker[k=1:PEAKERS], SUCR_peakerOut[k,0]==SUCR.peakers.power_out[k]) # initial on/off status for peaker k at t=0
#Initialization of commitment and dispatch variables for storage units at t=0 (representing the last hour of previous scheduling horizon day=day-1 and t=24)
    @constraint(SUCRmodel, conInitSOC[p=1:STORG_UNITS], SUCR_storgSOC[p,0]==SUCR.soc_init[p]) # SOC for storage unit p at t=0
# Baseload Operation of nuclear units
    @constraint(SUCRmodel, conNuckBaseLoad[t=1:HRS_SUCR, g=1:GENS], SUCR_genOnOff[g,t]>=DF_Generators.Nuclear[g]) #
    @constraint(SUCRmodel, conNuclearTotGenZone[t=1:HRS_SUCR, n=1:N_ZONES], sum((SUCR_genOut[g,t]*Map_Gens[g,n]*DF_Generators.Nuclear[g]) for g=1:GENS) -sucr_prep_demand.nuclear_wa[t,n] ==0)

#Limits on generation of cogen units
    @constraint(SUCRmodel, conCoGenBaseLoad[t=1:HRS_SUCR, g=1:GENS], SUCR_genOnOff[g,t]>=DF_Generators.Cogen[g]) #
    @constraint(SUCRmodel, conCoGenTotGenZone[t=1:HRS_SUCR, n=1:N_ZONES], sum((SUCR_genOut[g,t]*Map_Gens[g,n]*DF_Generators.Cogen[g]) for g=1:GENS) -sucr_prep_demand.cogen_wa[t,n] ==0)

# Constraints representing technical limits of conventional generators
#Status transition trajectory of
    @constraint(SUCRmodel, conStartUpAndDn[t=1:HRS_SUCR, g=1:GENS], (SUCR_genOnOff[g,t] - SUCR_genOnOff[g,t-1] - SUCR_genStartUp[g,t] + SUCR_genShutDown[g,t])==0)
# Max Power generation limit in Block 1
    @constraint(SUCRmodel, conMaxPowBlock1[t=1:HRS_SUCR, g=1:GENS],  SUCR_genOut_Block[g,1,t] <= DF_Generators.IHRC_B1_Q[g]*SUCR_genOnOff[g,t] )
# Max Power generation limit in Block 2
    @constraint(SUCRmodel, conMaxPowBlock2[t=1:HRS_SUCR, g=1:GENS],  SUCR_genOut_Block[g,2,t] <= DF_Generators.IHRC_B2_Q[g]*SUCR_genOnOff[g,t] )
# Max Power generation limit in Block 3
    @constraint(SUCRmodel, conMaxPowBlock3[t=1:HRS_SUCR, g=1:GENS],  SUCR_genOut_Block[g,3,t] <= DF_Generators.IHRC_B3_Q[g]*SUCR_genOnOff[g,t] )
# Max Power generation limit in Block 4
    @constraint(SUCRmodel, conMaxPowBlock4[t=1:HRS_SUCR, g=1:GENS],  SUCR_genOut_Block[g,4,t] <= DF_Generators.IHRC_B4_Q[g]*SUCR_genOnOff[g,t] )
# Max Power generation limit in Block 5
    @constraint(SUCRmodel, conMaxPowBlock5[t=1:HRS_SUCR, g=1:GENS],  SUCR_genOut_Block[g,5,t] <= DF_Generators.IHRC_B5_Q[g]*SUCR_genOnOff[g,t] )
# Max Power generation limit in Block 6
    @constraint(SUCRmodel, conMaxPowBlock6[t=1:HRS_SUCR, g=1:GENS],  SUCR_genOut_Block[g,6,t] <= DF_Generators.IHRC_B6_Q[g]*SUCR_genOnOff[g,t] )
# Max Power generation limit in Block 7
    @constraint(SUCRmodel, conMaxPowBlock7[t=1:HRS_SUCR, g=1:GENS],  SUCR_genOut_Block[g,7,t] <= DF_Generators.IHRC_B7_Q[g]*SUCR_genOnOff[g,t] )
# Total Production of each generation equals the sum of generation from its all blocks
    @constraint(SUCRmodel, conTotalGen[t=1:HRS_SUCR, g=1:GENS],  sum(SUCR_genOut_Block[g,b,t] for b=1:BLOCKS) + SUCR_TotGenVioP[g,t] - SUCR_TotGenVioN[g,t] >=SUCR_genOut[g,t])

#Max power generation limit
    @constraint(SUCRmodel, conMaxPow[t=1:HRS_SUCR, g=1:GENS],  SUCR_genOut[g,t]+SUCR_genResUp[g,t] - SUCR_MaxGenVioP[g,t]  <= DF_Generators.MaxPowerOut[g]*SUCR_genOnOff[g,t] )
# Min power generation limit
    @constraint(SUCRmodel, conMinPow[t=1:HRS_SUCR, g=1:GENS],  SUCR_genOut[g,t]-SUCR_genResDn[g,t] + SUCR_MinGenVioP[g,t] >= DF_Generators.MinPowerOut[g]*SUCR_genOnOff[g,t] )
# Up reserve provision limit
    @constraint(SUCRmodel, conMaxResUp[t=1:HRS_SUCR, g=1:GENS], SUCR_genResUp[g,t] <= DF_Generators.SpinningRes_Limit[g]*SUCR_genOnOff[g,t] )
# Non-Spinning Reserve Limit
    #@constraint(SUCRmodel, conMaxNonSpinResUp[t=1:HRS_SUCR, g=1:GENS], SUCR_genResNonSpin[g,t] <= (DF_Generators.NonSpinningRes_Limit[g]*(1-SUCR_genOnOff[g,t])) )
    @constraint(SUCRmodel, conMaxNonSpinResUp[t=1:HRS_SUCR, g=1:GENS], SUCR_genResNonSpin[g,t] <= 0 )
#Down reserve provision limit
    @constraint(SUCRmodel, conMaxResDown[t=1:HRS_SUCR, g=1:GENS],  SUCR_genResDn[g,t] <= DF_Generators.SpinningRes_Limit[g]*SUCR_genOnOff[g,t] )
#Up ramp rate limit
    @constraint(SUCRmodel, conRampRateUp[t=1:HRS_SUCR, g=1:GENS], (SUCR_genOut[g,t] - SUCR_genOut[g,t-1] <=(DF_Generators.RampUpLimit[g]*SUCR_genOnOff[g, t-1]) + (DF_Generators.RampStartUpLimit[g]*SUCR_genStartUp[g,t])))
# Down ramp rate limit
    @constraint(SUCRmodel, conRampRateDown[t=1:HRS_SUCR, g=1:GENS], (SUCR_genOut[g,t-1] - SUCR_genOut[g,t] <=(DF_Generators.RampDownLimit[g]*SUCR_genOnOff[g,t]) + (DF_Generators.RampShutDownLimit[g]*SUCR_genShutDown[g,t])))
# Min Up Time limit with alternative formulation
    @constraint(SUCRmodel, conUpTime[t=1:HRS_SUCR, g=1:GENS], (sum(SUCR_genStartUp[g,k] for k=lb_MUT[g,t]:t)<=SUCR_genOnOff[g,t]))
# Min down Time limit with alternative formulation
    @constraint(SUCRmodel, conDownTime[t=1:HRS_SUCR, g=1:GENS], (1-sum(SUCR_genShutDown[g,i] for i=lb_MDT[g,t]:t)>=SUCR_genOnOff[g,t]))

# Constraints representing technical limits of Peakers
#Status transition trajectory of peakers
    @constraint(SUCRmodel, conStartUpAndDn_Peaker[t=1:HRS_SUCR, k=1:PEAKERS], (SUCR_peakerOnOff[k,t] - SUCR_peakerOnOff[k,t-1] - SUCR_peakerStartUp[k,t] + SUCR_peakerShutDown[k,t])==0)
# Max Power generation limit in Block 1
    @constraint(SUCRmodel, conMaxPowBlock1_Peaker[t=1:HRS_SUCR, k=1:PEAKERS],  SUCR_peakerOut_Block[k,1,t] <= DF_Peakers.IHRC_B1_Q[k]*SUCR_peakerOnOff[k,t] )
# Max Power generation limit in Block 2
    @constraint(SUCRmodel, conMaxPowBlock2_Peaker[t=1:HRS_SUCR, k=1:PEAKERS],  SUCR_peakerOut_Block[k,2,t] <= DF_Peakers.IHRC_B2_Q[k]*SUCR_peakerOnOff[k,t] )
# Max Power generation limit in Block 3
    @constraint(SUCRmodel, conMaxPowBlock3_Peaker[t=1:HRS_SUCR, k=1:PEAKERS],  SUCR_peakerOut_Block[k,3,t] <= DF_Peakers.IHRC_B3_Q[k]*SUCR_peakerOnOff[k,t] )
# Max Power generation limit in Block 4
    @constraint(SUCRmodel, conMaxPowBlock4_Peaker[t=1:HRS_SUCR, k=1:PEAKERS],  SUCR_peakerOut_Block[k,4,t] <= DF_Peakers.IHRC_B4_Q[k]*SUCR_peakerOnOff[k,t] )
# Max Power generation limit in Block 5
    @constraint(SUCRmodel, conMaxPowBlock5_Peaker[t=1:HRS_SUCR, k=1:PEAKERS],  SUCR_peakerOut_Block[k,5,t] <= DF_Peakers.IHRC_B5_Q[k]*SUCR_peakerOnOff[k,t] )
# Max Power generation limit in Block 6
    @constraint(SUCRmodel, conMaxPowBlock6_Peaker[t=1:HRS_SUCR, k=1:PEAKERS],  SUCR_peakerOut_Block[k,6,t] <= DF_Peakers.IHRC_B6_Q[k]*SUCR_peakerOnOff[k,t] )
# Max Power generation limit in Block 7
    @constraint(SUCRmodel, conMaxPowBlock7_Peaker[t=1:HRS_SUCR, k=1:PEAKERS],  SUCR_peakerOut_Block[k,7,t] <= DF_Peakers.IHRC_B7_Q[k]*SUCR_peakerOnOff[k,t] )
# Total Production of each generation equals the sum of generation from its all blocks
    @constraint(SUCRmodel, conTotalGen_Peaker[t=1:HRS_SUCR, k=1:PEAKERS],  sum(SUCR_peakerOut_Block[k,b,t] for b=1:BLOCKS)>=SUCR_peakerOut[k,t])
#Max power generation limit
    @constraint(SUCRmodel, conMaxPow_Peaker[t=1:HRS_SUCR, k=1:PEAKERS],  SUCR_peakerOut[k,t]+SUCR_peakerResUp[k,t] <= DF_Peakers.MaxPowerOut[k]*SUCR_peakerOnOff[k,t] )
# Min power generation limit
    @constraint(SUCRmodel, conMinPow_Peaker[t=1:HRS_SUCR, k=1:PEAKERS],  SUCR_peakerOut[k,t]-SUCR_peakerResDn[k,t] >= DF_Peakers.MinPowerOut[k]*SUCR_peakerOnOff[k,t] )
# Up reserve provision limit
    @constraint(SUCRmodel, conMaxResUp_Peaker[t=1:HRS_SUCR, k=1:PEAKERS], SUCR_peakerResUp[k,t] <= DF_Peakers.SpinningRes_Limit[k]*SUCR_peakerOnOff[k,t] )
# Non-Spinning Reserve Limit
    @constraint(SUCRmodel, conMaxNonSpinResUp_Peaker[t=1:HRS_SUCR, k=1:PEAKERS], SUCR_peakerResNonSpin[k,t] <= (DF_Peakers.NonSpinningRes_Limit[k]*(1-SUCR_peakerOnOff[k,t])))
#Down reserve provision limit
    @constraint(SUCRmodel, conMaxResDown_Peaker[t=1:HRS_SUCR, k=1:PEAKERS],  SUCR_peakerResDn[k,t] <= DF_Peakers.SpinningRes_Limit[k]*SUCR_peakerOnOff[k,t] )
#Up ramp rate limit
    @constraint(SUCRmodel, conRampRateUp_Peaker[t=1:HRS_SUCR, k=1:PEAKERS], (SUCR_peakerOut[k,t] - SUCR_peakerOut[k,t-1] <=(DF_Peakers.RampUpLimit[k]*SUCR_peakerOnOff[k, t-1]) + (DF_Peakers.RampStartUpLimit[k]*SUCR_peakerStartUp[k,t])))
# Down ramp rate limit
    @constraint(SUCRmodel, conRampRateDown_Peaker[t=1:HRS_SUCR, k=1:PEAKERS], (SUCR_peakerOut[k,t-1] - SUCR_peakerOut[k,t] <=(DF_Peakers.RampDownLimit[k]*SUCR_peakerOnOff[k,t]) + (DF_Peakers.RampShutDownLimit[k]*SUCR_peakerShutDown[k,t])))
# Min Up Time limit with alternative formulation
    @constraint(SUCRmodel, conUpTime_Peaker[t=1:HRS_SUCR, k=1:PEAKERS], (sum(SUCR_peakerStartUp[k,r] for r=lb_MUT_Peaker[k,t]:t)<=SUCR_peakerOnOff[k,t]))
# Min down Time limit with alternative formulation
    @constraint(SUCRmodel, conDownTime_Peaker[t=1:HRS_SUCR, k=1:PEAKERS], (1-sum(SUCR_peakerShutDown[k,s] for s=lb_MDT_Peaker[k,t]:t)>=SUCR_peakerOnOff[k,t]))

# Renewable generation constraints
    @constraint(SUCRmodel, conSolarLimit[t=1:HRS_SUCR, n=1:N_ZONES], SUCR_solarG[n, t] + SUCR_solarGSpil[n,t]<=sucr_prep_demand.solar_wa[t,n])
    @constraint(SUCRmodel, conWindLimit[t=1:HRS_SUCR, n=1:N_ZONES], SUCR_windG[n, t] + SUCR_windGSpil[n,t]<=sucr_prep_demand.wind_wa[t,n])
    @constraint(SUCRmodel, conHydroLimit[t=1:HRS_SUCR, n=1:N_ZONES], SUCR_hydroG[n, t] + SUCR_hydroGSpil[n,t]<=sucr_prep_demand.hydro_wa[t,n])

# Constraints representing technical characteristics of storage units
# status transition of storage units between charging, discharging, and idle modes
    @constraint(SUCRmodel, conStorgStatusTransition[t=1:HRS_SUCR, p=1:STORG_UNITS], (SUCR_storgChrg[p,t]+SUCR_storgDisc[p,t]+SUCR_storgIdle[p,t])==1)
# charging power limit
    @constraint(SUCRmodel, conStrgChargPowerLimit[t=1:HRS_SUCR, p=1:STORG_UNITS], (SUCR_storgChrgPwr[p,t] - SUCR_storgResDn[p,t])<=DF_Storage.Power[p]*SUCR_storgChrg[p,t])
# Discharging power limit
    @constraint(SUCRmodel, conStrgDisChgPowerLimit[t=1:HRS_SUCR, p=1:STORG_UNITS], (SUCR_storgDiscPwr[p,t] + SUCR_storgResUp[p,t])<=DF_Storage.Power[p]*SUCR_storgDisc[p,t])
# Down reserve provision limit
    @constraint(SUCRmodel, conStrgDownResrvMax[t=1:HRS_SUCR, p=1:STORG_UNITS], SUCR_storgResDn[p,t]<=DF_Storage.Power[p]*SUCR_storgChrg[p,t])
# Up reserve provision limit`
    @constraint(SUCRmodel, conStrgUpResrvMax[t=1:HRS_SUCR, p=1:STORG_UNITS], SUCR_storgResUp[p,t]<=DF_Storage.Power[p]*SUCR_storgDisc[p,t])
# State of charge at t
    @constraint(SUCRmodel, conStorgSOC[t=1:HRS_SUCR, p=1:STORG_UNITS], SUCR_storgSOC[p,t]==SUCR_storgSOC[p,t-1]-(SUCR_storgDiscPwr[p,t]/DF_Storage.TripEfficDown[p])+(SUCR_storgChrgPwr[p,t]*DF_Storage.TripEfficUp[p])-(SUCR_storgSOC[p,t]*DF_Storage.SelfDischarge[p]))
# minimum energy limit
    @constraint(SUCRmodel, conMinEnrgStorgLimi[t=1:HRS_SUCR, p=1:STORG_UNITS], SUCR_storgSOC[p,t]-(SUCR_storgResUp[p,t]/DF_Storage.TripEfficDown[p])+(SUCR_storgResDn[p,t]/DF_Storage.TripEfficUp[p])>=0)
# Maximum energy limit
    @constraint(SUCRmodel, conMaxEnrgStorgLimi[t=1:HRS_SUCR, p=1:STORG_UNITS], SUCR_storgSOC[p,t]-(SUCR_storgResUp[p,t]/DF_Storage.TripEfficDown[p])+(SUCR_storgResDn[p,t]/DF_Storage.TripEfficUp[p])<=(DF_Storage.Power[p]/DF_Storage.PowerToEnergRatio[p]))
# Constraints representing transmission grid capacity constraints
# DC Power Flow Calculation
    #@constraint(SUCRmodel, conDCPowerFlowPos[t=1:HRS_SUCR, n=1:N_ZONES, m=1:N_ZONES], SUCR_powerFlow[n,m,t]-(TranS[n,m]*(SUCR_voltAngle[n,t]-SUCR_voltAngle[m,t])) ==0)
    @constraint(SUCRmodel, conDCPowerFlowNeg[t=1:HRS_SUCR, n=1:N_ZONES, m=1:N_ZONES], SUCR_powerFlow[n,m,t]+SUCR_powerFlow[m,n,t]==0)
# Tranmission flow bounds (from n to m and from m to n)
    @constraint(SUCRmodel, conPosFlowLimit[t=1:HRS_SUCR, n=1:N_ZONES, m=1:N_ZONES], SUCR_powerFlow[n,m,t]<=TranC[n,m])
    @constraint(SUCRmodel, conNegFlowLimit[t=1:HRS_SUCR, n=1:N_ZONES, m=1:N_ZONES], SUCR_powerFlow[n,m,t]>=-TranC[n,m])
# Voltage Angle bounds and reference point
    #@constraint(SUCRmodel, conVoltAnglUB[t=1:HRS_SUCR, n=1:N_ZONES], SUCR_voltAngle[n,t]<=π)
    #@constraint(SUCRmodel, conVoltAnglLB[t=1:HRS_SUCR, n=1:N_ZONES], SUCR_voltAngle[n,t]>=-π)
    #@constraint(SUCRmodel, conVoltAngRef[t=1:HRS_SUCR], SUCR_voltAngle[1,t]==0)

    # Demand-side Constraints
    @constraint(SUCRmodel, conDemandLimit[t=1:HRS_SUCR, n=1:N_ZONES], SUCR_Demand[n,t]+ SUCR_Demand_Curt[n,t] == sucr_prep_demand.wk_ahead[t,n])

    # Demand Curtailment and wind generation limits
    @constraint(SUCRmodel, conDemandCurtLimit[t=1:HRS_SUCR, n=1:N_ZONES], SUCR_Demand_Curt[n,t] <= LOAD_SHED_MAX);
    @constraint(SUCRmodel, conOverGenLimit[t=1:HRS_SUCR, n=1:N_ZONES], SUCR_OverGen[n,t] <= OVERGEN_MAX);

    # System-wide Constraints
    #nodal balance constraint
    @constraint(SUCRmodel, conNodBalanc[t=1:HRS_SUCR, n=1:N_ZONES], sum((SUCR_genOut[g,t]*Map_Gens[g,n]) for g=1:GENS) + sum((SUCR_storgDiscPwr[p,t]*Map_Storage[p,n]) for p=1:STORG_UNITS) - sum((SUCR_storgChrgPwr[p,t]*Map_Storage[p,n]) for p=1:STORG_UNITS) +SUCR_solarG[n, t] +SUCR_windG[n, t] +SUCR_hydroG[n, t] - SUCR_OverGen[n,t] - SUCR_Demand[n,t] == sum(SUCR_powerFlow[n,m,t] for m=1:M_ZONES))

# Minimum zonal up reserve requirement, if there are more than two zones, we should  define reserve regions for DEC and DEP
    #@constraint(SUCRmodel, conMinUpReserveReq[t=1:HRS_SUCR, n=1:N_ZONES], sum((SUCR_genResUp[g,t]*Map_Gens[g,n]) for g=1:GENS) + sum((SUCR_storgResUp[p,t]*Map_Storage[p,n]) for p=1:STORG_UNITS) >= Reserve_Req_Up[n] )
    @constraint(SUCRmodel, conMinUpReserveReq[t=1:HRS_SUCR], sum((SUCR_genResUp[g,t]+SUCR_genResNonSpin[g,t]) for g=1:GENS) + sum((SUCR_storgResUp[p,t]) for p=1:STORG_UNITS) >= sum(Reserve_Req_Up[n] for n=1:N_ZONES))

# Minimum down reserve requirement
#    @constraint(SUCRmodel, conMinDnReserveReq[t=1:HRS_SUCR], sum(genResDn[g,t] for g=1:GENS) + sum(storgResDn[p,t] for p=1:STORG_UNITS) >= Reserve_Req_Dn[t] )

    t2_SUCRmodel = time_ns()
    time_SUCRmodel = (t2_SUCRmodel -t1_SUCRmodel)/1.0e9;
    @info "SUCRmodel for day: $day setup executed in (s): $time_SUCRmodel";

    open(".//outputs//csv//time_performance.csv", FILE_ACCESS_APPEND) do io
            writedlm(io, hcat("SUCRmodel", time_SUCRmodel, "day: $day",
                    "", "", "Model Setup"), ',')
    end; # closes file

# solve the First WAUC model (SUCR)
    JuMP.optimize!(SUCRmodel)
# Pricing general results in the terminal window
    println("Objective value: ", JuMP.objective_value(SUCRmodel))
    println("------------------------------------")
    println("------- SURC OBJECTIVE VALUE -------")
    println("Objective value for day ", day, " is ", JuMP.objective_value(SUCRmodel))
    println("------------------------------------")
    println("------- SURC PRIMAL STATUS -------")
    println(primal_status(SUCRmodel))
    println("------------------------------------")
    println("------- SURC DUAL STATUS -------")
    println(JuMP.dual_status(SUCRmodel))
    println("Day: ", day, " solved")
    println("---------------------------")
    println("SUCRmodel Number of variables: ", JuMP.num_variables(SUCRmodel))
    @info "SUCRmodel Number of variables: " JuMP.num_variables(SUCRmodel)

    open(".//outputs//csv//time_performance.csv", FILE_ACCESS_APPEND) do io
            writedlm(io, hcat("SUCRmodel", JuMP.num_variables(SUCRmodel), "day: $day",
                    "", "", "Variables"), ',')
    end;

    @debug "SUCRmodel for day: $day optimized executed in (s):  $(solve_time(SUCRmodel))";

    open(".//outputs//csv//time_performance.csv", FILE_ACCESS_APPEND) do io
            writedlm(io, hcat("SUCRmodel", solve_time(SUCRmodel), "day: $day",
                    "", "", "Model Optimization"), ',')
    end; # closes file


## Write the optimal outcomes into spreadsheets
#TODO: Later we need to include a variable for day so the cell
# number in which the results are printed is updated accordingly

    # Write the conventional generators' schedules
    t1_write_SUCRmodel_results = time_ns()
    open(".//outputs//csv//SUCR_GenOutputs.csv", FILE_ACCESS_APPEND) do io
        for t in 1:HRS_SUCR, g=1:GENS
            writedlm(io, hcat(day, t+INIT_HR_SUCR, g, DF_Generators.UNIT_ID[g],
                DF_Generators.MinPowerOut[g], DF_Generators.MaxPowerOut[g],
                JuMP.value.(SUCR_genOut[g,t]), JuMP.value.(SUCR_genOnOff[g,t]),
                JuMP.value.(SUCR_genShutDown[g,t]), JuMP.value.(SUCR_genStartUp[g,t]),
                JuMP.value.(SUCR_genResUp[g,t]), JuMP.value.(SUCR_genResNonSpin[g,t]),
                JuMP.value.(SUCR_genResDn[g,t]), JuMP.value.(SUCR_TotGenVioP[g,t]),
                JuMP.value.(SUCR_TotGenVioN[g,t]), JuMP.value.(SUCR_MaxGenVioP[g,t]),
                JuMP.value.(SUCR_MinGenVioP[g,t])), ',')
        end # ends the loop
    end; # closes file

    open(".//outputs//csv//SUCR_PeakerOutputs.csv", FILE_ACCESS_APPEND) do io
        for t in 1:HRS_SUCR, k=1:PEAKERS
            writedlm(io, hcat(day, t+INIT_HR_SUCR, k, DF_Peakers.UNIT_ID[k],
                DF_Peakers.MinPowerOut[k], DF_Peakers.MaxPowerOut[k],
                JuMP.value.(SUCR_peakerOut[k,t]), JuMP.value.(SUCR_peakerOnOff[k,t]),
                JuMP.value.(SUCR_peakerShutDown[k,t]), JuMP.value.(SUCR_peakerStartUp[k,t]),
                JuMP.value.(SUCR_peakerResUp[k,t]), JuMP.value.(SUCR_peakerResNonSpin[k,t]),
                JuMP.value.(SUCR_peakerResDn[k,t])), ',')
        end # ends the loop
    end; # closes file

# Writing storage units' optimal schedules in CSV file
    open(".//outputs//csv//SUCR_StorageOutputs.csv", FILE_ACCESS_APPEND) do io
        for t in 1:HRS_SUCR, p=1:STORG_UNITS
            writedlm(io, hcat(day, t+INIT_HR_SUCR, p, DF_Storage.Power[p],
				DF_Storage.Power[p]/DF_Storage.PowerToEnergRatio[p],
				JuMP.value.(SUCR_storgChrg[p,t]), JuMP.value.(SUCR_storgDisc[p,t]),
				JuMP.value.(SUCR_storgIdle[p,t]), JuMP.value.(SUCR_storgChrgPwr[p,t]),
				JuMP.value.(SUCR_storgDiscPwr[p,t]), JuMP.value.(SUCR_storgSOC[p,t]),
				JuMP.value.(SUCR_storgResUp[p,t]), JuMP.value.(SUCR_storgResDn[p,t]) ), ',')
        end # ends the loop
    end; # closes file

# Writing the transmission flow schedules into spreadsheets
    open(".//outputs//csv//SUCR_TranFlowOutputs.csv", FILE_ACCESS_APPEND) do io
        for t in 1:HRS_SUCR, n=1:N_ZONES, m=1:M_ZONES
            writedlm(io, hcat(day, t+INIT_HR_SUCR, n, m,
                JuMP.value.(SUCR_powerFlow[n,m,t]), TranC[n,m] ), ',')
        end # ends the loop
    end; # closes file

    # Writing the curtilment, overgeneration, and spillage outcomes in CSV file
    open(".//outputs//csv//SUCR_Curtail.csv", FILE_ACCESS_APPEND) do io
        for t in 1:HRS_SUCR, n=1:N_ZONES
           writedlm(io, hcat(day, t+INIT_HR_SUCR, n,
               JuMP.value.(SUCR_OverGen[n,t]), JuMP.value.(SUCR_Demand_Curt[n,t]),
               JuMP.value.(SUCR_windGSpil[n,t]), JuMP.value.(SUCR_solarGSpil[n,t]),
               JuMP.value.(SUCR_hydroGSpil[n,t])), ',')
        end # ends the loop
    end; # closes file

    t2_write_SUCRmodel_results = time_ns()
    time_write_SUCRmodel_results = (t2_write_SUCRmodel_results -t1_write_SUCRmodel_results)/1.0e9;
    @info "Write SUCRmodel results for day $day: $time_write_SUCRmodel_results executed in (s)";

    open(".//outputs//csv//time_performance.csv", FILE_ACCESS_APPEND) do io
            writedlm(io, hcat("SUCRmodel", time_write_SUCRmodel_results, "day: $day",
                    "", "", "Write CSV files"), ',')
    end; #closes file

    # Create and save the following parameters, which are transefered to BAUC2
        for h=1:24-INIT_HR_SUCR+INIT_HR_FUCR
            for g=1:GENS
                global SUCRtoBUCR2_genOnOff[g,h]=JuMP.value.(SUCR_genOnOff[g,h]);
                global SUCRtoBUCR2_genOut[g,h]=JuMP.value.(SUCR_genOut[g,h]);
                global SUCRtoBUCR2_genStartUp[g,h]=JuMP.value.(SUCR_genStartUp[g,h]);
                global SUCRtoBUCR2_genShutDown[g,h]=JuMP.value.(SUCR_genShutDown[g,h]);
                for b=1:BLOCKS
                    SUCRtoBUCR2_genOut_Block[g,b,h]=JuMP.value.(SUCR_genOut_Block[g,b,h]);
                end
            end
            for k=1:PEAKERS
                global SUCRtoBUCR2_peakerOnOff[k,h]=round(JuMP.value.(SUCR_peakerOnOff[k,h]));
                global SUCRtoBUCR2_peakerOut[k,h]=JuMP.value.(SUCR_peakerOut[k,h]);
                global SUCRtoBUCR2_peakerStartUp[k,h]=round(JuMP.value.(SUCR_peakerStartUp[k,h]));
                global SUCRtoBUCR2_peakerShutDown[k,h]=round(JuMP.value.(SUCR_peakerShutDown[k,h]));
                for b=1:BLOCKS
                    SUCRtoBUCR2_peakerOut_Block[k,b,h]=JuMP.value.(SUCR_peakerOut_Block[k,b,h]);
                end
            end
            for p=1:STORG_UNITS
                global SUCRtoBUCR2_storgChrg[p,h]=round(JuMP.value.(SUCR_storgChrg[p,h]));
                global SUCRtoBUCR2_storgDisc[p,h]=round(JuMP.value.(SUCR_storgDisc[p,h]));
                global SUCRtoBUCR2_storgIdle[p,h]=round(JuMP.value.(SUCR_storgIdle[p,h]));
                global SUCRtoBUCR2_storgChrgPwr[p,h]=JuMP.value.(SUCR_storgChrgPwr[p,h]);
                global SUCRtoBUCR2_storgDiscPwr[p,h]=JuMP.value.(SUCR_storgDiscPwr[p,h]);
                global SUCRtoBUCR2_storgSOC[p,h]=JuMP.value.(SUCR_storgSOC[p,h]);
            end
        end

## Initilization of the next UC Run
#=
    # This must be updated later when we run two WAUCs every day and then RTUCs
        for g=1:GENS
            DF_Generators.StatusInit[g]=JuMP.value.(SUCR_genOnOff[g,24-INIT_HR_SUCR+INIT_HR_FUCR]);
            DF_Generators.PowerInit[g]=JuMP.value.(SUCR_genOut[g,24-INIT_HR_SUCR+INIT_HR_FUCR]);
        end
        for p=1:STORG_UNITS
            DF_Storage.SOCInit[p]=JuMP.value.(SUCR_storgSOC[p,24-INIT_HR_SUCR+INIT_HR_FUCR]);
        end
=#

## This block models the second Balancing Unit Commitment Run, which is for the time range between the morning and evening UC Runs
    for h=1:24-INIT_HR_SUCR+INIT_HR_FUCR # number of BUCR periods in between FUCR and SUCR
        if h==24-INIT_HR_SUCR+INIT_HR_FUCR
            println("this period is hour: ", h)
        end

        # Preprocessing the demand data
        D_Rng_BUCR2 = ((day-1)*24)+INIT_HR_SUCR+h  # cell of the demand data needed for running the first WAUC run at 6 am with 7-day look-ahead horizon
        BUCR2_Hr_Demand = BUCR_Demands[D_Rng_BUCR2, :]
        BUCR2_Hr_SolarG = BUCR_SolarGs[D_Rng_BUCR2, :]
        BUCR2_Hr_WindG = BUCR_WindGs[D_Rng_BUCR2, :]
        BUCR2_Hr_HydroG = BUCR_HydroGs[D_Rng_BUCR2, :]
        BUCR2_Hr_NuclearG = BUCR_NuclearGs[D_Rng_BUCR2, :]
        BUCR2_Hr_CogenG = BUCR_CogenGs[D_Rng_BUCR2, :]

        # Preprocessing module that fixes the commitment of slow-start units to their FUCR's outcome and determines the binary commitment bounds for fast-start units dependent to their initial up/down time and minimum up/down time limits
        #if the units are slow their BAUC's commitment is fixed to their FUCR's schedule
        for g=1:GENS
            #if DF_Generators.FastStart[g]==0 # if the units are slow their BAUC's commitment is fixed to their FUCR's schedule
            if SUCRtoBUCR2_genOnOff[g,h]==0
                global BUCR2_Commit_LB[g] = 0;
                global BUCR2_Commit_UB[g] = 0;
            else
                global BUCR2_Commit_LB[g] = 1;
                global BUCR2_Commit_UB[g] = 1;
            end
        end
        # if the units are fast their BAUC's commitment could be fixed to 0 or 1 or vary between 0 or 1 dependent to their initial up/down time and minimum up/down time
        for k=1:PEAKERS
            if BUCR2.peakers.dntime_init[k]==0
                if BUCR2.peakers.uptime_init[k]<DF_Peakers.MinUpTime[k]
                    global BUCR2_Commit_Peaker_LB[k] = 1;
                    global BUCR2_Commit_Peaker_UB[k] = 1;
                else
                    global BUCR2_Commit_Peaker_LB[k] = 0;
                    global BUCR2_Commit_Peaker_UB[k] = 1;
                end
            elseif BUCR2.peakers.dntime_init[k]<DF_Peakers.MinDownTime[k]
                    global BUCR2_Commit_Peaker_LB[k] = 0;
                    global BUCR2_Commit_Peaker_UB[k] = 0;
            else
                    global BUCR2_Commit_Peaker_LB[k] = 0;
                    global BUCR2_Commit_Peaker_UB[k] = 1;
            end
        end

        t1_BUCR2model = time_ns()

        BUCR2model = direct_model(CPLEX.Optimizer())
        set_optimizer_attribute(BUCR2model, "CPX_PARAM_EPGAP", SOLVER_EPGAP)

        # Declaring the decision variables for conventional generators
        @variable(BUCR2model, BUCR2_genOnOff[1:GENS], Bin) #Bin
        @variable(BUCR2model, BUCR2_genStartUp[1:GENS], Bin) # startup variable
        @variable(BUCR2model, BUCR2_genShutDown[1:GENS], Bin) # shutdown variable
        @variable(BUCR2model, BUCR2_genOut[1:GENS]>=0) # Generator's output schedule
        @variable(BUCR2model, BUCR2_genOut_Block[1:GENS, 1:BLOCKS]>=0) # Generator's output schedule from each block (block rfers to IHR curve blocks/segments)
        @variable(BUCR2model, BUCR2_TotGenVioP[g=1:GENS]>=0)
        @variable(BUCR2model, BUCR2_TotGenVioN[g=1:GENS]>=0)
        @variable(BUCR2model, BUCR2_MaxGenVioP[g=1:GENS]>=0)
        @variable(BUCR2model, BUCR2_MinGenVioP[g=1:GENS]>=0)


        # Declaring the decision variables for peakers
        @variable(BUCR2model, 0<=BUCR2_peakerOnOff[1:PEAKERS]<=1) #Bin, relaxed
        @variable(BUCR2model, 0<=BUCR2_peakerStartUp[1:PEAKERS]<=1) # startup variable
        @variable(BUCR2model, 0<=BUCR2_peakerShutDown[1:PEAKERS]<=1) # shutdown variable
        @variable(BUCR2model, BUCR2_peakerOut[1:PEAKERS]>=0) # Generator's output schedule
        @variable(BUCR2model, BUCR2_peakerOut_Block[1:PEAKERS, 1:BLOCKS]>=0) # Generator's output schedule from each block (block rfers to IHR curve blocks/segments)

        #@variable(BUCR2model, BUCR2_genResUp[1:GENS]>=0) # Generators' up reserve schedule
        #@variable(BUCR2model, BUCR2_genResDn[1:GENS]>=0) # Generator's down rserve schedule

        # declaring decision variables for storage Units
        @variable(BUCR2model, BUCR2_storgChrg[1:STORG_UNITS], Bin) #Bin variable equal to 1 if unit runs in the charging mode
        @variable(BUCR2model, BUCR2_storgDisc[1:STORG_UNITS], Bin) #Bin variable equal to 1 if unit runs in the discharging mode
        @variable(BUCR2model, BUCR2_storgIdle[1:STORG_UNITS], Bin) ##Bin variable equal to 1 if unit runs in the idle mode
        @variable(BUCR2model, BUCR2_storgChrgPwr[1:STORG_UNITS]>=0) #Chargung power
        @variable(BUCR2model, BUCR2_storgDiscPwr[1:STORG_UNITS]>=0) # Discharging Power
        @variable(BUCR2model, BUCR2_storgSOC[1:STORG_UNITS]>=0) # state of charge (stored energy level for storage unit at time t)
        #@variable(BUCR2model, BUCR2_storgResUp[1:STORG_UNITS]>=0) # Scheduled up reserve
        #@variable(BUCR2model, BUCR2_storgResDn[1:STORG_UNITS]>=0) # Scheduled down reserve

        # declaring decision variables for renewable generation
        @variable(BUCR2model, BUCR2_solarG[1:N_ZONES]>=0) # solar energy schedules
        @variable(BUCR2model, BUCR2_windG[1:N_ZONES]>=0) # wind energy schedules
        @variable(BUCR2model, BUCR2_hydroG[1:N_ZONES]>=0) # hydro energy schedules
        @variable(BUCR2model, BUCR2_solarGSpil[1:N_ZONES]>=0) # solar energy schedules
        @variable(BUCR2model, BUCR2_windGSpil[1:N_ZONES]>=0) # wind energy schedules
        @variable(BUCR2model, BUCR2_hydroGSpil[1:N_ZONES]>=0) # hydro energy schedules

        # Declaring decision variables for hourly dispatched and curtailed demand
        @variable(BUCR2model, BUCR2_Demand[1:N_ZONES]>=0) # Hourly scheduled demand
        @variable(BUCR2model, BUCR2_Demand_Curt[1:N_ZONES]>=0) # Hourly schedule demand
        @variable(BUCR2model, BUCR2_OverGen[1:N_ZONES]>=0)

        # declaring variables for transmission system
        @variable(BUCR2model, BUCR2_voltAngle[1:N_ZONES]) #voltage angle at zone/bus n in t//
        @variable(BUCR2model, BUCR2_powerFlow[1:N_ZONES, 1:M_ZONES]) #transmission Flow from zone n to zone m//

        # Defining the objective function that minimizes the overal cost of supplying electricity (=total variable, no-load, startup, and shutdown costs)
        @objective(BUCR2model, Min, sum(DF_Generators.IHRC_B1_HR[g]*FuelPrice[g,day]*(BUCR2_genOut_Block[g,1])
                                           +DF_Generators.IHRC_B2_HR[g]*FuelPrice[g,day]*(BUCR2_genOut_Block[g,2])
                                           +DF_Generators.IHRC_B3_HR[g]*FuelPrice[g,day]*(BUCR2_genOut_Block[g,3])
                                           +DF_Generators.IHRC_B4_HR[g]*FuelPrice[g,day]*(BUCR2_genOut_Block[g,4])
                                           +DF_Generators.IHRC_B5_HR[g]*FuelPrice[g,day]*(BUCR2_genOut_Block[g,5])
                                           +DF_Generators.IHRC_B6_HR[g]*FuelPrice[g,day]*(BUCR2_genOut_Block[g,6])
                                           +DF_Generators.IHRC_B7_HR[g]*FuelPrice[g,day]*(BUCR2_genOut_Block[g,7])
                                           +(BUCR2_TotGenVioP[g]*VIOLATION_PENALTY)+(BUCR2_TotGenVioN[g]*VIOLATION_PENALTY)+(BUCR2_MaxGenVioP[g]*VIOLATION_PENALTY)+(BUCR2_MinGenVioP[g]*VIOLATION_PENALTY)
                                           +DF_Generators.NoLoadHR[g]*FuelPrice[g,day]*(BUCR2_genOnOff[g]) +((DF_Generators.HotStartU_FixedCost[g]+(DF_Generators.HotStartU_HeatRate[g]*FuelPrice[g,day]))*(BUCR2_genStartUp[g]))
                                           +DF_Generators.ShutdownCost[g]*(BUCR2_genShutDown[g]) for g in 1:GENS)
                                           +sum(DF_Peakers.IHRC_B1_HR[k]*FuelPricePeakers[k,day]*(BUCR2_peakerOut_Block[k,1])
                                           +DF_Peakers.IHRC_B2_HR[k]*FuelPricePeakers[k,day]*(BUCR2_peakerOut_Block[k,2])
                                           +DF_Peakers.IHRC_B3_HR[k]*FuelPricePeakers[k,day]*(BUCR2_peakerOut_Block[k,3])
                                           +DF_Peakers.IHRC_B4_HR[k]*FuelPricePeakers[k,day]*(BUCR2_peakerOut_Block[k,4])
                                           +DF_Peakers.IHRC_B5_HR[k]*FuelPricePeakers[k,day]*(BUCR2_peakerOut_Block[k,5])
                                           +DF_Peakers.IHRC_B6_HR[k]*FuelPricePeakers[k,day]*(BUCR2_peakerOut_Block[k,6])
                                           +DF_Peakers.IHRC_B7_HR[k]*FuelPricePeakers[k,day]*(BUCR2_peakerOut_Block[k,7])
                                           +DF_Peakers.NoLoadHR[k]*FuelPricePeakers[k,day]*(BUCR2_peakerOnOff[k]) +((DF_Peakers.HotStartU_FixedCost[k]+(DF_Peakers.HotStartU_HeatRate[k]*FuelPricePeakers[k,day]))*(BUCR2_peakerStartUp[k]))
                                           +DF_Peakers.ShutdownCost[k]*(BUCR2_peakerShutDown[k]) for k in 1:PEAKERS)
                                           +sum((BUCR2_Demand_Curt[n]*LOAD_SHED_PENALTY)+(BUCR2_OverGen[n]*OVERGEN_PENALTY) for n=1:N_ZONES) )


        # Baseload Operation of nuclear units
        @constraint(BUCR2model, conNuckBaseLoad[g=1:GENS], BUCR2_genOnOff[g]>=DF_Generators.Nuclear[g]) #
        @constraint(BUCR2model, conNuclearTotGenZone[n=1:N_ZONES], sum((BUCR2_genOut[g]*Map_Gens[g,n]*DF_Generators.Nuclear[g]) for g=1:GENS) -BUCR2_Hr_NuclearG[n] ==0)

        #Limits on generation of cogen units
        @constraint(BUCR2model, conCoGenBaseLoad[g=1:GENS], BUCR2_genOnOff[g]>=DF_Generators.Cogen[g]) #
        @constraint(BUCR2model, conCoGenTotGenZone[n=1:N_ZONES], sum((BUCR2_genOut[g]*Map_Gens[g,n]*DF_Generators.Cogen[g]) for g=1:GENS) -BUCR2_Hr_CogenG[n] ==0)
        # Constraints representing technical limits of conventional generators
        #Status transition trajectory of
        @constraint(BUCR2model, conStartUpAndDn[g=1:GENS], (BUCR2_genOnOff[g] - BUCR2.gens.onoff_init[g] - BUCR2_genStartUp[g] + BUCR2_genShutDown[g])==0)
        # Max Power generation limit in Block 1
        @constraint(BUCR2model, conMaxPowBlock1[g=1:GENS],  BUCR2_genOut_Block[g,1] <= DF_Generators.IHRC_B1_Q[g]*BUCR2_genOnOff[g] )
        # Max Power generation limit in Block 2
        @constraint(BUCR2model, conMaxPowBlock2[g=1:GENS],  BUCR2_genOut_Block[g,2] <= DF_Generators.IHRC_B2_Q[g]*BUCR2_genOnOff[g] )
        # Max Power generation limit in Block 3
        @constraint(BUCR2model, conMaxPowBlock3[g=1:GENS],  BUCR2_genOut_Block[g,3] <= DF_Generators.IHRC_B3_Q[g]*BUCR2_genOnOff[g] )
        # Max Power generation limit in Block 4
        @constraint(BUCR2model, conMaxPowBlock4[g=1:GENS],  BUCR2_genOut_Block[g,4] <= DF_Generators.IHRC_B4_Q[g]*BUCR2_genOnOff[g] )
        # Max Power generation limit in Block 5
        @constraint(BUCR2model, conMaxPowBlock5[g=1:GENS],  BUCR2_genOut_Block[g,5] <= DF_Generators.IHRC_B5_Q[g]*BUCR2_genOnOff[g] )
        # Max Power generation limit in Block 6
        @constraint(BUCR2model, conMaxPowBlock6[g=1:GENS],  BUCR2_genOut_Block[g,6] <= DF_Generators.IHRC_B6_Q[g]*BUCR2_genOnOff[g] )
        # Max Power generation limit in Block 7
        @constraint(BUCR2model, conMaxPowBlock7[g=1:GENS],  BUCR2_genOut_Block[g,7] <= DF_Generators.IHRC_B7_Q[g]*BUCR2_genOnOff[g] )
        # Total Production of each generation equals the sum of generation from its all blocks
        @constraint(BUCR2model, conTotalGen[g=1:GENS],  sum(BUCR2_genOut_Block[g,b] for b=1:BLOCKS) + BUCR2_TotGenVioP[g]-BUCR2_TotGenVioN[g]== BUCR2_genOut[g])
        #Max power generation limit
        @constraint(BUCR2model, conMaxPow[g=1:GENS],  BUCR2_genOut[g] - BUCR2_MaxGenVioP[g] <= DF_Generators.MaxPowerOut[g]*BUCR2_genOnOff[g])
        # Min power generation limit
        @constraint(BUCR2model, conMinPow[g=1:GENS],  BUCR2_genOut[g] + BUCR2_MinGenVioP[g]>= DF_Generators.MinPowerOut[g]*BUCR2_genOnOff[g])
        #Up ramp rate limit
        @constraint(BUCR2model, conRampRateUp[g=1:GENS], (BUCR2_genOut[g] - BUCR2.gens.power_out[g] <=(DF_Generators.RampUpLimit[g]*BUCR2.gens.onoff_init[g]) + (DF_Generators.RampStartUpLimit[g]*BUCR2_genStartUp[g])))
        # Down ramp rate limit
        @constraint(BUCR2model, conRampRateDown[g=1:GENS], (BUCR2.gens.power_out[g] - BUCR2_genOut[g] <=(DF_Generators.RampDownLimit[g]*BUCR2_genOnOff[g]) + (DF_Generators.RampShutDownLimit[g]*BUCR2_genShutDown[g])))
        # Min Up Time limit with alternative formulation
        #The next twyo constraints enforce limits on binary commitment variables of slow and fast generators
        # scheduled slow units are forced to remain on, offline slow units remain off, and fast start units could change their commitment dependent on their MUT and MDT
        @constraint(BUCR2model, conCommitmentUB[g=1:GENS], (BUCR2_genOnOff[g] <= BUCR2_Commit_UB[g]))
        # if the generator is slow start and scheduled "on" in the SUCR,  is fixed by the following constraint
        @constraint(BUCR2model, conCommitmentLB[g=1:GENS], (BUCR2_genOnOff[g] >= BUCR2_Commit_LB[g]))

        # Constraints representing technical limits of peakers
        #Status transition trajectory of
        @constraint(BUCR2model, conStartUpAndDn_Peaker[k=1:PEAKERS], (BUCR2_peakerOnOff[k] - BUCR2.peakers.onoff_init[k] - BUCR2_peakerStartUp[k] + BUCR2_peakerShutDown[k])==0)
        # Max Power generation limit in Block 1
        @constraint(BUCR2model, conMaxPowBlock1_Peaker[k=1:PEAKERS],  BUCR2_peakerOut_Block[k,1] <= DF_Peakers.IHRC_B1_Q[k]*BUCR2_peakerOnOff[k] )
        # Max Power generation limit in Block 2
        @constraint(BUCR2model, conMaxPowBlock2_Peaker[k=1:PEAKERS],  BUCR2_peakerOut_Block[k,2] <= DF_Peakers.IHRC_B2_Q[k]*BUCR2_peakerOnOff[k] )
        # Max Power generation limit in Block 3
        @constraint(BUCR2model, conMaxPowBlock3_Peaker[k=1:PEAKERS],  BUCR2_peakerOut_Block[k,3] <= DF_Peakers.IHRC_B3_Q[k]*BUCR2_peakerOnOff[k] )
        # Max Power generation limit in Block 4
        @constraint(BUCR2model, conMaxPowBlock4_Peaker[k=1:PEAKERS],  BUCR2_peakerOut_Block[k,4] <= DF_Peakers.IHRC_B4_Q[k]*BUCR2_peakerOnOff[k] )
        # Max Power generation limit in Block 5
        @constraint(BUCR2model, conMaxPowBlock5_Peaker[k=1:PEAKERS],  BUCR2_peakerOut_Block[k,5] <= DF_Peakers.IHRC_B5_Q[k]*BUCR2_peakerOnOff[k] )
        # Max Power generation limit in Block 6
        @constraint(BUCR2model, conMaxPowBlock6_Peaker[k=1:PEAKERS],  BUCR2_peakerOut_Block[k,6] <= DF_Peakers.IHRC_B6_Q[k]*BUCR2_peakerOnOff[k] )
        # Max Power generation limit in Block 7
        @constraint(BUCR2model, conMaxPowBlock7_Peaker[k=1:PEAKERS],  BUCR2_peakerOut_Block[k,7] <= DF_Peakers.IHRC_B7_Q[k]*BUCR2_peakerOnOff[k] )
        # Total Production of each generation equals the sum of generation from its all blocks
        @constraint(BUCR2model, conTotalGen_Peaker[k=1:PEAKERS],  sum(BUCR2_peakerOut_Block[k,b] for b=1:BLOCKS)>=BUCR2_peakerOut[k])
        #Max power generation limit
        @constraint(BUCR2model, conMaxPow_Peaker[k=1:PEAKERS],  BUCR2_peakerOut[k] <= DF_Peakers.MaxPowerOut[k]*BUCR2_peakerOnOff[k])
        # Min power generation limit
        @constraint(BUCR2model, conMinPow_Peaker[k=1:PEAKERS],  BUCR2_peakerOut[k] >= DF_Peakers.MinPowerOut[k]*BUCR2_peakerOnOff[k])
        #Up ramp rate limit
        @constraint(BUCR2model, conRampRateUp_Peaker[k=1:PEAKERS], (BUCR2_peakerOut[k] - BUCR2.peakers.power_out[k] <=(DF_Peakers.RampUpLimit[k]*BUCR2.peakers.onoff_init[k]) + (DF_Peakers.RampStartUpLimit[k]*BUCR2_peakerStartUp[k])))
        # Down ramp rate limit
        @constraint(BUCR2model, conRampRateDown_Peaker[k=1:PEAKERS], (BUCR2.peakers.power_out[k] - BUCR2_peakerOut[k] <=(DF_Peakers.RampDownLimit[k]*BUCR2_peakerOnOff[k]) + (DF_Peakers.RampShutDownLimit[k]*BUCR2_peakerShutDown[k])))
        # Min Up Time limit with alternative formulation
        #The next twyo constraints enforce limits on binary commitment variables of slow and fast generators
        # scheduled slow units are forced to remain on, offline slow units remain off, and fast start units could change their commitment dependent on their MUT and MDT
        @constraint(BUCR2model, conCommitmentUB_Peaker[k=1:PEAKERS], (BUCR2_peakerOnOff[k] <= BUCR2_Commit_Peaker_UB[k]))
        # if the generator is slow start and scheduled "on" in the SUCR,  is fixed by the following constraint
        @constraint(BUCR2model, conCommitmentLB_Peaker[k=1:PEAKERS], (BUCR2_peakerOnOff[k] >= BUCR2_Commit_Peaker_LB[k]))

        # Renewable generation constraints
        @constraint(BUCR2model, conSolarLimit[n=1:N_ZONES], BUCR2_solarG[n] + BUCR2_solarGSpil[n]<=BUCR2_Hr_SolarG[n])
        @constraint(BUCR2model, conWindLimit[n=1:N_ZONES], BUCR2_windG[n] + BUCR2_windGSpil[n]<=BUCR2_Hr_WindG[n])
        @constraint(BUCR2model, conHydroLimit[n=1:N_ZONES], BUCR2_hydroG[n] + BUCR2_hydroGSpil[n]<=BUCR2_Hr_HydroG[n])

        # Constraints representing technical characteristics of storage units
        # the next three constraints fix the balancing charging/discharging/Idle status to their optimal outcomes as determined by SUCR
        @constraint(BUCR2model, conStorgChrgStatusFixed[p=1:STORG_UNITS], (BUCR2_storgChrg[p]==SUCRtoBUCR2_storgChrg[p,h]))
        @constraint(BUCR2model, conStorgDisChrgStatusFixed[p=1:STORG_UNITS], (BUCR2_storgDisc[p]==SUCRtoBUCR2_storgDisc[p,h]))
        @constraint(BUCR2model, conStorgIdleStatusFixed[p=1:STORG_UNITS], (BUCR2_storgIdle[p]==SUCRtoBUCR2_storgIdle[p,h]))

        # charging power limit
        @constraint(BUCR2model, conStrgChargPowerLimit[p=1:STORG_UNITS], (BUCR2_storgChrgPwr[p] )<=DF_Storage.Power[p]*BUCR2_storgChrg[p])
        # Discharging power limit
        @constraint(BUCR2model, conStrgDisChgPowerLimit[p=1:STORG_UNITS], (BUCR2_storgDiscPwr[p])<=DF_Storage.Power[p]*BUCR2_storgDisc[p])
        # State of charge at t
        @constraint(BUCR2model, conStorgSOC[p=1:STORG_UNITS], BUCR2_storgSOC[p]==BUCR2.soc_init[p]-(BUCR2_storgDiscPwr[p]/DF_Storage.TripEfficDown[p])+(BUCR2_storgChrgPwr[p]*DF_Storage.TripEfficUp[p])-(BUCR2_storgSOC[p]*DF_Storage.SelfDischarge[p]))
        # minimum energy limit
        @constraint(BUCR2model, conMinEnrgStorgLimi[p=1:STORG_UNITS], BUCR2_storgSOC[p]>=0)
        # Maximum energy limit
        @constraint(BUCR2model, conMaxEnrgStorgLimi[p=1:STORG_UNITS], BUCR2_storgSOC[p]<=(DF_Storage.Power[p]/DF_Storage.PowerToEnergRatio[p]))

        # Constraints representing transmission grid capacity constraints
        # DC Power Flow Calculation
        #@constraint(BUCR2model, conDCPowerFlowPos[n=1:N_ZONES, m=1:N_ZONES], BUCR2_powerFlow[n,m]-(TranS[n,m]*(BUCR2_voltAngle[n]-BUCR2_voltAngle[m])) ==0)
        @constraint(BUCR2model, conDCPowerFlowNeg[n=1:N_ZONES, m=1:N_ZONES], BUCR2_powerFlow[n,m]+BUCR2_powerFlow[m,n]==0)
        # Tranmission flow bounds (from n to m and from m to n)
        @constraint(BUCR2model, conPosFlowLimit[n=1:N_ZONES, m=1:N_ZONES], BUCR2_powerFlow[n,m]<=TranC[n,m])
        @constraint(BUCR2model, conNegFlowLimit[n=1:N_ZONES, m=1:N_ZONES], BUCR2_powerFlow[n,m]>=-TranC[n,m])
        # Voltage Angle bounds and reference point
        #@constraint(BUCR2model, conVoltAnglUB[n=1:N_ZONES], BUCR2_voltAngle[n]<=π)
        #@constraint(BUCR2model, conVoltAnglLB[n=1:N_ZONES], BUCR2_voltAngle[n]>=-π)
        #@constraint(BUCR2model, conVoltAngRef, BUCR2_voltAngle[1]==0)

        # Demand-side Constraints
        @constraint(BUCR2model, conDemandLimit[n=1:N_ZONES], BUCR2_Demand[n]+ BUCR2_Demand_Curt[n] == BUCR2_Hr_Demand[n])

        # Demand Curtailment and wind generation limits
        @constraint(BUCR2model, conDemandCurtLimit[n=1:N_ZONES], BUCR2_Demand_Curt[n] <= LOAD_SHED_MAX);
        @constraint(BUCR2model, conOverGenLimit[n=1:N_ZONES], BUCR2_OverGen[n] <= OVERGEN_MAX);

        # System-wide Constraints
        #nodal balance constraint
        @constraint(BUCR2model, conNodBalanc[n=1:N_ZONES], sum((BUCR2_genOut[g]*Map_Gens[g,n]) for g=1:GENS) + sum((BUCR2_peakerOut[k]*Map_Peakers[k,n]) for k=1:PEAKERS) + sum((BUCR2_storgDiscPwr[p]*Map_Storage[p,n]) for p=1:STORG_UNITS) - sum((BUCR2_storgChrgPwr[p]*Map_Storage[p,n]) for p=1:STORG_UNITS) +BUCR2_solarG[n] +BUCR2_windG[n] +BUCR2_hydroG[n] - BUCR2_OverGen[n]- BUCR2_Demand[n] == sum(BUCR2_powerFlow[n,m] for m=1:M_ZONES))
        # Minimum up reserve requirement
        #    @constraint(BUCR2model, conMinUpReserveReq[t=1:N_Hrs_BUCR], sum(genResUp[g,t] for g=1:GENS) + sum(storgResUp[p,t] for p=1:STORG_UNITS) >= Reserve_Req_Up[t] )

        # Minimum down reserve requirement
        #    @constraint(BUCR2model, conMinDnReserveReq[t=1:N_Hrs_BUCR], sum(genResDn[g,t] for g=1:GENS) + sum(storgResDn[p,t] for p=1:STORG_UNITS) >= Reserve_Req_Dn[t] )

        t2_BUCR2model = time_ns()
        time_BUCR2model = (t2_BUCR2model -t1_BUCR2model)/1.0e9;
        @info "BUCR2model for day: $day and hour $(h+INIT_HR_SUCR) setup executed in (s): $time_BUCR2model";

        open(".//outputs//csv//time_performance.csv", FILE_ACCESS_APPEND) do io
                writedlm(io, hcat("BUCR2model", time_BUCR2model, "day: $day",
                        "hour $(h+INIT_HR_SUCR)", "", "Model Setup"), ',')
        end; # closes file

        # solve the First WAUC model (BUCR)
        JuMP.optimize!(BUCR2model)

        #compute_conflict!(BUCR2model)
        #if MOI.get(BUCR2model, MOI.ConflictStatus()) != MOI.CONFLICT_FOUND
        #    error("No conflict could be found for an infeasible model.")
        #end

        # Both constraints should participate in the conflict.
        #MOI.get(BUCR2model, MOI.ConstraintConflictStatus(), conTotalGen)
        #MOI.get(BUCR2model, MOI.ConstraintConflictStatus(), c2)

        # Pricing general results in the terminal window
        println("Objective value: ", JuMP.objective_value(BUCR2model))

        println("------------------------------------")
        println("------- BAUC2 OBJECTIVE VALUE -------")
        println("Objective value for day ", day, " and hour ", h+INIT_HR_SUCR, " is: ", JuMP.objective_value(BUCR2model))
        println("------------------------------------")
        println("------- BAUC2 PRIMAL STATUS -------")
        println(primal_status(BUCR2model))
        println("------------------------------------")
        println("------- BAUC2 DUAL STATUS -------")
        println(JuMP.dual_status(BUCR2model))
        println("Day: ", day, " and hour ", h+INIT_HR_SUCR, " solved")
        println("---------------------------")
        println("BUCR2model Number of variables: ", JuMP.num_variables(BUCR2model))
        @info "BUCR2model Number of variables: " JuMP.num_variables(BUCR2model)
        open(".//outputs//csv//time_performance.csv", FILE_ACCESS_APPEND) do io
                writedlm(io, hcat("BUCR2model", JuMP.num_variables(BUCR2model), "day: $day",
                        "hour $(h+INIT_HR_SUCR)", "", "Variables"), ',')
        end;

        @debug "BUCR2model for day: $day and hour $(h+INIT_HR_SUCR) optimized executed in (s): $(solve_time(BUCR2model))";

        open(".//outputs//csv//time_performance.csv", FILE_ACCESS_APPEND) do io
                writedlm(io, hcat("BUCR2model", solve_time(BUCR2model), "day: $day",
                        "hour $(h+INIT_HR_SUCR)", "", "Model Optimization"), ',')
        end; # closes file

        ## Write the optimal outcomes into spreadsheets
        # TODO: Later we need to include a variable for day so the cell number in which the results are printed is updated accordingly

        # Write the conventional generators' schedules
        t1_write_BUCR2model_results = time_ns()
        open(".//outputs//csv//BUCR_GenOutputs.csv", FILE_ACCESS_APPEND) do io
            for g=1:GENS
                writedlm(io, hcat(day, h+INIT_HR_SUCR, g, DF_Generators.UNIT_ID[g],
                    DF_Generators.MinPowerOut[g], DF_Generators.MaxPowerOut[g],
                    JuMP.value.(BUCR2_genOut[g]), JuMP.value.(BUCR2_genOnOff[g]),
                    JuMP.value.(BUCR2_genShutDown[g]), JuMP.value.(BUCR2_genStartUp[g]), JuMP.value.(BUCR2_TotGenVioP[g]),
                    JuMP.value.(BUCR2_TotGenVioN[g]), JuMP.value.(BUCR2_MaxGenVioP[g]), JuMP.value.(BUCR2_MinGenVioP[g])), ',')
            end # ends the loop
        end; # closes file

# Write the peakers' schedules
        open(".//outputs//csv//BUCR_PeakerOutputs.csv", FILE_ACCESS_APPEND) do io
            for k=1:PEAKERS
                writedlm(io, hcat(day, h+INIT_HR_SUCR, k, DF_Peakers.UNIT_ID[k],
                    DF_Peakers.MinPowerOut[k], DF_Peakers.MaxPowerOut[k],
                    JuMP.value.(BUCR2_peakerOut[k]), JuMP.value.(BUCR2_peakerOnOff[k]),
                    JuMP.value.(BUCR2_peakerShutDown[k]), JuMP.value.(BUCR2_peakerStartUp[k])), ',')
            end # ends the loop
        end; # closes file


    # Writing storage units' optimal schedules into CSV file
        open(".//outputs//csv//BUCR_StorageOutputs.csv", FILE_ACCESS_APPEND) do io
            for p=1:STORG_UNITS
                writedlm(io, hcat(day, h+INIT_HR_SUCR, p, DF_Storage.Name[p],
                        DF_Storage.Power[p], DF_Storage.Power[p]/DF_Storage.PowerToEnergRatio[p],
                        JuMP.value.(BUCR2_storgChrg[p]), JuMP.value.(BUCR2_storgDisc[p]),
                        JuMP.value.(BUCR2_storgIdle[p]), JuMP.value.(BUCR2_storgChrgPwr[p]),
                        JuMP.value.(BUCR2_storgDiscPwr[p]), JuMP.value.(BUCR2_storgSOC[p]) ), ',')
            end # ends the loop
        end; # closes file


        # Writing the transmission flow schedules in CSV file
        open(".//outputs//csv//BUCR_TranFlowOutputs.csv", FILE_ACCESS_APPEND) do io
            for n=1:N_ZONES, m=1:M_ZONES
                writedlm(io, hcat(day, h+INIT_HR_SUCR, n, m,
                    JuMP.value.(BUCR2_powerFlow[n,m]), TranC[n,m]), ',')
            end # ends the loop
        end; # closes file


        # Writing the curtilment, overgeneration, and spillage outcomes in CSV file
        open(".//outputs//csv//BUCR_Curtail.csv", FILE_ACCESS_APPEND) do io
            for n=1:N_ZONES
               writedlm(io, hcat(day, h+INIT_HR_SUCR, n,
                   JuMP.value.(BUCR2_OverGen[n]), JuMP.value.(BUCR2_Demand_Curt[n]),
                   JuMP.value.(BUCR2_windGSpil[n]), JuMP.value.(BUCR2_solarGSpil[n]),
                   JuMP.value.(BUCR2_hydroGSpil[n])), ',')
            end # ends the loop
        end; # closes file
        t2_write_BUCR2model_results = time_ns()

        time_write_BUCR2model_results = (t2_write_BUCR2model_results -t1_write_BUCR2model_results)/1.0e9;
        @info "Write BUCR2model results for day $day and hour $(h+INIT_HR_SUCR) executed in (s): $time_write_BUCR2model_results";

        open(".//outputs//csv//time_performance.csv", FILE_ACCESS_APPEND) do io
                writedlm(io, hcat("BUCR2model", time_write_BUCR2model_results, "day: $day",
                        "hour $(h+INIT_HR_SUCR)", "", "Write CSV files"), ',')
        end; #closes file
    ##
    # Initilization of the next UC Run

    # Setting initial values for conventional generators in BUCR2 (next hour), FUCR, and BUCR1
        for g=1:GENS
            # set the initiali values to be fed to the next hour BUCR2
            global BUCR2.gens.onoff_init[g] = JuMP.value.(BUCR2_genOnOff[g]); #
            global BUCR2.gens.power_out[g] = JuMP.value.(BUCR2_genOut[g]);
            # Set the initial values fed to the next FUCR and BUCR1

            if h==(24-INIT_HR_SUCR+INIT_HR_FUCR)
                global BUCR1.gens.onoff_init[g] = JuMP.value.(BUCR2_genOnOff[g]);
                global BUCR1.gens.power_out[g] = JuMP.value.(BUCR2_genOut[g]);
                global FUCR.gens.onoff_init[g] = JuMP.value.(BUCR2_genOnOff[g]);
                global FUCR.gens.power_out[g] = JuMP.value.(BUCR2_genOut[g]);
            end
        end

    # Setting initial values for peakers in BUCR2 (next hour), FUCR, and BUCR1
        for g=1:PEAKERS
            # set the initiali values to be fed to the next hour BUCR2
            global BUCR2.peakers.onoff_init[g] = round(JuMP.value.(BUCR2_peakerOnOff[g])); #
            global BUCR2.peakers.power_out[g] = JuMP.value.(BUCR2_peakerOut[g]);
            # Set the initial values fed to the next FUCR and BUCR1

            if h==(24-INIT_HR_SUCR+INIT_HR_FUCR)
                global BUCR1.peakers.onoff_init[g] = round(JuMP.value.(BUCR2_peakerOnOff[g]));
                global BUCR1.peakers.power_out[g] = JuMP.value.(BUCR2_peakerOut[g]);
                global FUCR.peakers.onoff_init[g] = round(JuMP.value.(BUCR2_peakerOnOff[g]));
                global FUCR.peakers.power_out[g] = JuMP.value.(BUCR2_peakerOut[g]);
            end
        end

        for p=1:STORG_UNITS
            # Set the initial values to be fed to the next hour BUCR2
            global BUCR2.soc_init[p]=JuMP.value.(BUCR2_storgSOC[p]);
            # set the initiali values to be fed to the next hour BUCR2
            if h==(24-INIT_HR_SUCR+INIT_HR_FUCR)
                global BUCR1.soc_init[p] = JuMP.value.(BUCR2_storgSOC[p]);
                global FUCR.soc_init[p] = JuMP.value.(BUCR2_storgSOC[p]);
            end
        end

        #Update the up and down times for individual  generators
        for g=1:GENS
            #Update the total up-time or down-time for each individual conventional generator to be fed into BUCR2
            if (round(JuMP.value.(BUCR2_genStartUp[g])))==1
                global BUCR2.gens.uptime_init[g]= 1;
                global BUCR2.gens.dntime_init[g] = 0;
            elseif (round(JuMP.value.(BUCR2_genShutDown[g])))==1
                global BUCR2.gens.uptime_init[g]= 0;
                global BUCR2.gens.dntime_init[g]= 1;
            else
                if (round(JuMP.value.(BUCR2_genOnOff[g])))==1
                    global BUCR2.gens.uptime_init[g]=BUCR2.gens.uptime_init[g]+1;
                    global BUCR2.gens.dntime_init[g]= 0;
                else
                    global BUCR2.gens.uptime_init[g]= 0;
                    global BUCR2.gens.dntime_init[g]= BUCR2.gens.dntime_init[g]+1;
                end
            end
            #Update the total up and down times to be fed into FUCR and BUCR1
            if h==(INIT_HR_SUCR-INIT_HR_FUCR)
                global BUCR1.gens.uptime_init[g]= BUCR2.gens.uptime_init[g];
                global BUCR1.gens.dntime_init[g]= BUCR2.gens.dntime_init[g];
                global FUCR.gens.uptime_init[g]= BUCR2.gens.uptime_init[g];
                global FUCR.gens.dntime_init[g]= BUCR2.gens.dntime_init[g];
            end
        end

        for g=1:PEAKERS
            #Update the total up-time or down-time for each individual peakers to be fed into BUCR2
            if (JuMP.value.(BUCR2_peakerStartUp[g]))>0
                global BUCR2.peakers.uptime_init[g]= 1;
                global BUCR2.peakers.dntime_init[g] = 0;
            elseif (JuMP.value.(BUCR2_peakerShutDown[g]))>0
                global BUCR2.peakers.uptime_init[g]= 0;
                global BUCR2.peakers.dntime_init[g]= 1;
            else
                if (JuMP.value.(BUCR2_peakerOnOff[g]))>0
                    global BUCR2.peakers.uptime_init[g]=BUCR2.peakers.uptime_init[g]+1;
                    global BUCR2.peakers.dntime_init[g]= 0;
                else
                    global BUCR2.peakers.uptime_init[g]= 0;
                    global BUCR2.peakers.dntime_init[g]= BUCR2.peakers.dntime_init[g]+1;
                end
            end
            #Update the total up and down times to be fed into FUCR and BUCR1
            if h==(INIT_HR_SUCR-INIT_HR_FUCR)
                global BUCR1.peakers.uptime_init[g]= BUCR2.peakers.uptime_init[g];
                global BUCR1.peakers.dntime_init[g]= BUCR2.peakers.dntime_init[g];
                global FUCR.peakers.uptime_init[g]= BUCR2.peakers.uptime_init[g];
                global FUCR.peakers.dntime_init[g]= BUCR2.peakers.dntime_init[g];
            end
        end

    end # ends the loop that runs hourly BUCR between [INIT_HR_FUCR and INIT_HR_SUCR)

    t2_day_execution = time_ns()
    time_day_execution = (t2_day_execution - t1_day_execution)/1.0e9;

    open(".//outputs//csv//time_performance.csv", FILE_ACCESS_APPEND) do io
            writedlm(io, hcat("Whole Day", time_day_execution,
                    "day: $day", " ", "Whole Day Execution"), ',')
    end; #closes file

end # ends the foor loop that runs the UC model on  a daily basis

##
t2 = time_ns()
elapsedTime = (t2 -t1)/1.0e9;

write(io_log, "Whole program time execution (s):\t $elapsedTime\n")
@info "Whole Program setup executed in (s):" elapsedTime;

open(".//outputs//csv//time_performance.csv", FILE_ACCESS_APPEND) do io
        writedlm(io, hcat("Whole Program", elapsedTime,
                "", "", "Whole Execution"), ',')
end; #closes file

close(io_log);
