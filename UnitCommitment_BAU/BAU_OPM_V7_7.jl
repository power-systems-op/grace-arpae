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
Version: 7.7
...
# Arguments: None
# Outputs: dataframe
# Examples: N/A
"""

#NOTES: This file was originally labeled as BAU_OPM_V5_Nuc_Cogen_Imp_Exp_MustRun_DCC
# Changes in this version: Nuclear data was included
#= Changes
1. Specify data type of the vectors that store the data read from CSV input files.
2. Replace several global variables by local variables.
3. Replace several auxiliary variables by data structures.
4. Replace the variables that store the results of the first UC by data structures.
5. Divide the main script in different Julia scripts:
 5.1 constants.jl: Store the constants used across Julia files
 5.2 data_structure.jl: Define the data structures used across Julia files
 5.3 import_data.jl: Read input files and store data in dataframes and vectors
 5.4 fucr_model.jl: Solve first unit commitment model
 5.5 BAU_OPM.jl: Main program
 5.6 bucr_model.jl: Solve Balancing UC problem
 5.6 Embed main program in a function
=#

#=
---------------------------
Suggestions to test the code:
- Don't force the nature of the variables.
- Compare results, objective functions. For 2 days.
- If values are not the same.

- Objective function is similar or smaller
- Cost, if they are higher.
- Optimality gap could.

- Run the code v7 in different computers.
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
using Parameters

t1 = time_ns()
include("constants.jl")
include("data_structure.jl")
t1_read_data = time_ns()
include("import_data.jl")
t2_read_data = time_ns()
time_read_data = (t2_read_data -t1_read_data)/1.0e9;

include("fucr_model.jl")
include("bucr1_model.jl")
include("sucr_model.jl")
include("bucr2_model.jl")
## Enabling debugging code, use ENV["JULIA_DEBUG"] = "" to desable ging code
ENV["JULIA_DEBUG"] = "all"

# Log file
io_log = open( string(".//outputs//logs//UC_BAU_",
        Dates.format(now(), "yyyy-mm-dd_HH-MM-SS"), ".txt"), FILE_ACCESS_APPEND)

logger = SimpleLogger(io_log)
flush(io_log)
global_logger(logger)

@info "Hardware Features: " cpuinfo()

write(io_log, "Running model from day $INITIAL_DAY to day $FINAL_DAY with the following parameters:\n")
write(io_log, "Load-Shedding Penalty: $LOAD_SHED_PENALTY, Over-generation Penalty: $OVERGEN_PENALTY\n")
write(io_log, "Max Load-Shedding Penalty $LOAD_SHED_MAX, Max Over-generation Penalty: $OVERGEN_MAX\n")
write(io_log, "MaxGenLimit Viol Penalty: $VIOLATION_PENALTY, OptimalityGap: $OVERGEN_PENALTY\n")

time_performance_header    = ["Section", "Time", "Note1", "Note2", "Note3", "Note4"]
open(".//outputs//time_performance.csv", FILE_ACCESS_OVER) do io
    writedlm(io, permutedims(time_performance_header), ',')
end; # closes file

@info "Time to read input data (s): $time_read_data";
open(".//outputs//time_performance.csv", FILE_ACCESS_APPEND) do io
        writedlm(io, hcat("Read Input Data", time_read_data, "",
                "", "", "Read CSV files"), ',')
end;

objective_values_header    = ["Section", "Time", "Time2", "Note1", "Value"]
open(".//outputs//objective_values_v76.csv", FILE_ACCESS_OVER) do io
    writedlm(io, permutedims(objective_values_header), ',')
end; # closes file

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

## Spreadsheets for the first unit commitment run
# Creating conventional generating units' schedules in the 1st unit commitment run
open(".//outputs//FUCR_GenOutputs.csv", FILE_ACCESS_OVER) do io
    writedlm(io, permutedims(FUCR_GenOutputs_header), ',')
end; # closes file

open(".//outputs//FUCR_PeakerOutputs.csv", FILE_ACCESS_OVER) do io
    writedlm(io, permutedims(FUCR_PeakerOutputs_header), ',')
end; # closes file

open(".//outputs//FUCR_StorageOutputs.csv", FILE_ACCESS_OVER) do io
    writedlm(io, permutedims(FUCR_StorageOutputs_header), ',')
end;

open(".//outputs//FUCR_TranFlowOutputs.csv", FILE_ACCESS_OVER) do io
    writedlm(io, permutedims(FUCR_TranFlowOutputs_header), ',')
end; # closes file

open(".//outputs//FUCR_Curtail.csv", FILE_ACCESS_OVER) do io
    writedlm(io, permutedims(FUCR_Curtail_header), ',')
end; # closes file

# Spreadsheets for the second unit commitment run
# Creating conventional generating units' schedules in the 2nd unit commitment run
open(".//outputs//SUCR_GenOutputs.csv", FILE_ACCESS_OVER) do io
    writedlm(io, permutedims(SUCR_GenOutputs_header), ',')
end; # closes file

open(".//outputs//SUCR_PeakerOutputs.csv", FILE_ACCESS_OVER) do io
    writedlm(io, permutedims(SUCR_PeakerOutputs_header), ',')
end; # closes file

open(".//outputs//SUCR_StorageOutputs.csv", FILE_ACCESS_OVER) do io
    writedlm(io, permutedims(SUCR_StorageOutputs_header), ',')
end; # closes file

open(".//outputs//SUCR_TranFlowOutputs.csv", FILE_ACCESS_OVER) do io
    writedlm(io, permutedims(SUCR_TranFlowOutputs_header), ',')
end; # closes file

open(".//outputs//SUCR_Curtail.csv", FILE_ACCESS_OVER) do io
    writedlm(io, permutedims(SUCR_Curtail_header), ',')
end; # closes file

# Spreadsheets for the balancing unit commitment run
# Write the conventional generators' schedules
open(".//outputs//BUCR_GenOutputs.csv", FILE_ACCESS_OVER) do io
    writedlm(io, permutedims(BUCR_GenOutputs_header), ',')
end; # closes file

open(".//outputs//BUCR_PeakerOutputs.csv", FILE_ACCESS_OVER) do io
    writedlm(io, permutedims(BUCR_PeakerOutputs_header), ',')
end; # closes file

# Writing storage units' optimal schedules into CSV file
open(".//outputs//BUCR_StorageOutputs.csv", FILE_ACCESS_OVER) do io
    writedlm(io, permutedims(BUCR_StorageOutputs_header), ',')
end; # closes file

# Writing the transmission flow schedules in CSV file
open(".//outputs//BUCR_TranFlowOutputs.csv", FILE_ACCESS_OVER) do io
    writedlm(io, permutedims(BUCR_TranFlowOutputs_header), ',')
end; # closes file

open(".//outputs//BUCR_Curtail.csv", FILE_ACCESS_OVER) do io
    writedlm(io, permutedims(BUCR_Curtail_header), ',')
end; # closes file

function run_main_code()
	# Setting initial values
	fucr_gens = GensResults(
		onoff_init = copy(DF_Generators.StatusInit),
		power_out_init = copy(DF_Generators.PowerInit),
		uptime_init = copy(DF_Generators.UpTimeInit),
		dntime_init = copy(DF_Generators.DownTimeInit))

	fucr_peakers = PeakersResults(
		onoff_init = copy(DF_Peakers.StatusInit),
		power_out_init = copy(DF_Peakers.PowerInit),
		uptime_init = copy(DF_Peakers.UpTimeInit),
		dntime_init = copy(DF_Peakers.DownTimeInit))

	fucr_storg = StorageResults(soc_init =copy(DF_Storage.SOCInit))

	FUCR = UC_Results(fucr_gens, fucr_peakers, fucr_storg)

	sucr_gens = GensResults(
		onoff_init = copy(DF_Generators.StatusInit),
		power_out_init = copy(DF_Generators.PowerInit),
		uptime_init = copy(DF_Generators.UpTimeInit),
		dntime_init = copy(DF_Generators.DownTimeInit))

	sucr_peakers = PeakersResults(
		onoff_init = copy(DF_Peakers.StatusInit),
		power_out_init = copy(DF_Peakers.PowerInit),
		uptime_init = copy(DF_Peakers.UpTimeInit),
		dntime_init = copy(DF_Peakers.DownTimeInit),
		genout_block = zeros(Float64, PEAKERS,BLOCKS,24-INIT_HR_SUCR+INIT_HR_FUCR))

	sucr_storg = StorageResults(soc_init =copy(DF_Storage.SOCInit))

	SUCR = UC_Results(sucr_gens, sucr_peakers, sucr_storg)

	bucr1_gens = GensResults(
		onoff_init = copy(DF_Generators.StatusInit),
		power_out_init = copy(DF_Generators.PowerInit),
		uptime_init = copy(DF_Generators.UpTimeInit),
		dntime_init = copy(DF_Generators.DownTimeInit))

	bucr1_peakers = PeakersResults(
		onoff_init = copy(DF_Peakers.StatusInit),
		power_out_init = copy(DF_Peakers.PowerInit),
		uptime_init = copy(DF_Peakers.UpTimeInit),
		dntime_init = copy(DF_Peakers.DownTimeInit))

	bucr1_storg = StorageResults(soc_init =copy(DF_Storage.SOCInit))

	BUCR1 = UC_Results(bucr1_gens, bucr1_peakers, bucr1_storg)

	bucr2_gens = GensResults()
	bucr2_peakers = PeakersResults()
	bucr2_storg = StorageResults(soc_init = zeros(STORG_UNITS))

	BUCR2 = UC_Results(bucr2_gens, bucr2_peakers, bucr2_storg)

	fucr_to_bucr1_gens = GensResults()
	fucr_to_bucr1_peakers = PeakersResults()
	fucr_to_bucr1_storg = StorageResults()

	FUCRtoBUCR1 = UC_Results(fucr_to_bucr1_gens, fucr_to_bucr1_peakers,
						fucr_to_bucr1_storg)

	# Creating variables that transfer optimal schedules between the Models
	#TODO: Some of the below variables may be unneccsary and can be deleted. Check at the end

	sucr_to_bucr2_gens = GensResults()
	sucr_to_bucr2_peakers = PeakersResults()
	sucr_to_bucr2_storg = StorageResults()

	SUCRtoBUCR2 = UC_Results(sucr_to_bucr2_gens, sucr_to_bucr2_peakers,
						sucr_to_bucr2_storg)

	# Auxiliary variables for enforcing commitment of slow and fast-start units
	# in BUCRs
	#TODO: Include these variables in UC_Results structures
	BUCR1_Commit_LB = zeros(Int64, GENS)
	BUCR1_Commit_UB = zeros(Int64, GENS)
	BUCR2_Commit_LB = zeros(Int64, GENS)
	BUCR2_Commit_UB = zeros(Int64, GENS)

	BUCR1_Commit_Peaker_LB = zeros(Int64, PEAKERS)
	BUCR1_Commit_Peaker_UB = zeros(Int64, PEAKERS)
	BUCR2_Commit_Peaker_LB = zeros(Int64, PEAKERS)
	BUCR2_Commit_Peaker_UB = zeros(Int64, PEAKERS)

	## Pre-processing the data to calculate the model inputs:
	# The time range lower-bound for min up constraint using the alternative approach

	# LB for slow-start conventional generators
	lb_MUT = zeros(Int64, GENS, HRS_FUCR);
	lb_MDT = zeros(Int64, GENS, HRS_FUCR);
	for g in 1:GENS, t in 1:HRS_FUCR
	    lb_MUT[g,t] =  replace_lower_limit(t-DF_Generators.MinUpTime[g]+1);
	    lb_MDT[g,t] =  replace_lower_limit(t-DF_Generators.MinDownTime[g]+1);
	end;

	# LB for peakers
	lb_MUT_Peaker=zeros(Int64, PEAKERS, HRS_FUCR)
	lb_MDT_Peaker=zeros(Int64, PEAKERS, HRS_FUCR)
	for k in 1:PEAKERS , t in 1:HRS_FUCR
	    lb_MUT_Peaker[k,t] =  replace_lower_limit(t-DF_Peakers.MinUpTime[k]+1);
	    lb_MDT_Peaker[k,t] =  replace_lower_limit(t-DF_Peakers.MinDownTime[k]+1);
	end;
	## TODO: We need two more loops for calculating the lb_MUT and lb_MDT for the second UC runs
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
	   fucr_prepoc = DemandWAPreprocGens(
	   		copy(FUCR_Demands[D_Rng_Dn_FUCR:D_Rng_Up_FUCR, :]),
	    	copy(FUCR_SolarGs[R_Rng_Dn_FUCR:R_Rng_Up_FUCR, :]),
	        copy(FUCR_WindGs[R_Rng_Dn_FUCR:R_Rng_Up_FUCR, :]),
	        copy(FUCR_HydroGs[R_Rng_Dn_FUCR:R_Rng_Up_FUCR, :]),
	        copy(FUCR_NuclearGs[R_Rng_Dn_FUCR:R_Rng_Up_FUCR, :]),
	        copy(FUCR_CogenGs[R_Rng_Dn_FUCR:R_Rng_Up_FUCR, :]) )

	    # Bottom and upper cells of the demand data needed for running the second
	    # WA-UC run at 5 pm with 7-day look-ahead horizon
	    D_Rng_Dn_SUCR = ((day-1)*(INIT_HR_FUCR+HRS_FUCR))+INIT_HR_SUCR+1;
	    D_Rng_Up_SUCR = day*(INIT_HR_FUCR+HRS_FUCR);

	    R_Rng_Dn_SUCR = ((day-1)*(24))+INIT_HR_SUCR+1;
	    R_Rng_Up_SUCR = ((day+6)*(24));

	    sucr_prepoc = DemandWAPreprocGens(
	    	copy(SUCR_Demands[D_Rng_Dn_SUCR:D_Rng_Up_SUCR, :]),
	    	copy(SUCR_SolarGs[R_Rng_Dn_SUCR:R_Rng_Up_SUCR, :]),
	    	copy(SUCR_WindGs[R_Rng_Dn_SUCR:R_Rng_Up_SUCR, :]),
	    	copy(SUCR_HydroGs[R_Rng_Dn_SUCR:R_Rng_Up_SUCR, :]),
	    	copy(SUCR_NuclearGs[R_Rng_Dn_SUCR:R_Rng_Up_SUCR, :]),
	    	copy(SUCR_CogenGs[R_Rng_Dn_SUCR:R_Rng_Up_SUCR, :]) )

		# This block models the first UC optimization that is run in the morning
	    t1_FUCRmodel = time_ns()

		FUCRtoBUCR1 = fucr_model(day, DF_Generators, DF_Peakers, DF_Storage,
			FuelPrice, FuelPricePeakers, Map_Gens, Map_Peakers, Map_Storage,
            FUCR, fucr_prepoc, lb_MDT, lb_MUT, lb_MDT_Peaker, lb_MUT_Peaker)

		# This block models the Balancing Unit Commitment Runs between the
		# morning and evening UC Runs
	    for h=1:INIT_HR_SUCR-INIT_HR_FUCR # number of BUCR periods between FUCR and SUCR
	        # Pre-processing demand variables
	        t1_BUCR_SUCR_data_hand = time_ns()
			# Bottom cell of the demand data needed for running the first WA-UC
			# run at 6 am with 7-day look-ahead horizon
	        D_Rng_BUCR1 = ((day-1)*24)+INIT_HR_FUCR+h

			bucr1_prepoc = DemandHrPreprocGens(
				copy(BUCR_Demands[D_Rng_BUCR1, :]),
				copy(BUCR_SolarGs[D_Rng_BUCR1, :]),
				copy(BUCR_WindGs[D_Rng_BUCR1, :]),
				copy(BUCR_HydroGs[D_Rng_BUCR1, :]),
				copy(BUCR_NuclearGs[D_Rng_BUCR1, :]),
				copy(BUCR_CogenGs[D_Rng_BUCR1, :]) )

	        # Preprocessing module that fixes the commitment of slow-start units
			# to their FUCR's outcome and determines the binary commitment bounds
			# for fast-start units dependent to their initial up/down time and
			# min up/down time limits if the units are slow their BAUC's
			# commitment is fixed to their FUCR's schedule

	        for g=1:GENS
				BUCR1_Commit_LB[g] = fix_uc_slow_start(FUCRtoBUCR1.gens.onoff[g,h])
				BUCR1_Commit_UB[g] = fix_uc_slow_start(FUCRtoBUCR1.gens.onoff[g,h])
	        end;

	        # If the units are fast, their BAUC's commitment could be fixed
	        # to 0 or 1 or vary between 0 or 1 dependent to their initial
			# up/down time and min up/down time
	        for k=1:PEAKERS
	            if BUCR1.peakers.dntime_init[k] == 0
	                if BUCR1.peakers.uptime_init[k] < DF_Peakers.MinUpTime[k]
	                    BUCR1_Commit_Peaker_LB[k] = 1;
	                    BUCR1_Commit_Peaker_UB[k] = 1;
	                else
	                    BUCR1_Commit_Peaker_LB[k] = 0;
	                    BUCR1_Commit_Peaker_UB[k] = 1;
	                end
	            elseif BUCR1.peakers.dntime_init[k] < DF_Peakers.MinDownTime[k]
	                BUCR1_Commit_Peaker_LB[k] = 0;
	                BUCR1_Commit_Peaker_UB[k] = 0;
	            else
	                BUCR1_Commit_Peaker_LB[k] = 0;
	                BUCR1_Commit_Peaker_UB[k] = 1;
	            end
	        end

	        t2_BUCR_SUCR_data_hand = time_ns();

	        time_BUCR_SUCR_data_hand = (t2_BUCR_SUCR_data_hand -t1_BUCR_SUCR_data_hand)/1.0e9;
	        @info "BUCR_SUCR data handling for day $day executed in (s): $time_BUCR_SUCR_data_hand";

	        open(".//outputs//time_performance.csv", FILE_ACCESS_APPEND) do io
	                writedlm(io, hcat("BUCR1model", time_BUCR_SUCR_data_hand,
						"day: $day", "hour $(h+INIT_HR_FUCR)",
						"Pre-processing variables", "Data Manipulation"), ',')
	        end; #closes file

			# This function models the 2nd UC optimization that is run in the evening
			BUCR1, SUCR, BUCR2 = bucr1_model(day, h, DF_Generators, DF_Peakers,
				DF_Storage, FuelPrice, FuelPricePeakers, Map_Gens, Map_Peakers,
				Map_Storage, BUCR1, SUCR, BUCR2, FUCRtoBUCR1,
				bucr1_prepoc, BUCR1_Commit_LB, BUCR1_Commit_UB,
				BUCR1_Commit_Peaker_LB, BUCR1_Commit_Peaker_UB)

	    end # ends loop that runs hourly BUCR1 between INIT_HR_FUCR & INIT_HR_SUCR

		# Run second unit commitment model
		SUCRtoBUCR2 = sucr_model(day, DF_Generators, DF_Peakers, DF_Storage,
					FuelPrice, FuelPricePeakers, Map_Gens,
					Map_Storage, SUCR, sucr_prepoc, lb_MDT, lb_MUT,
					lb_MDT_Peaker, lb_MUT_Peaker);

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

		# This block models the second Balancing Unit Commitment Run, which is
		# for the time range between the morning and evening UC Runs
	    for h= 1:(24-INIT_HR_SUCR+INIT_HR_FUCR) # number of BUCR periods between FUCR and SUCR
	        if h==24-INIT_HR_SUCR+INIT_HR_FUCR
	            println("this period is hour: ", h)
	        end

	        # Preprocessing the demand data
			# Cell of the demand data needed for running the first WAUC run
			# at 6 am with 7-day look-ahead horizon
	        D_Rng_BUCR2 = ((day-1)*24)+INIT_HR_SUCR+h

			bucr2_prepoc = DemandHrPreprocGens(
				copy(BUCR_Demands[D_Rng_BUCR2, :]),
				copy(BUCR_SolarGs[D_Rng_BUCR2, :]),
				copy(BUCR_WindGs[D_Rng_BUCR2, :]),
				copy(BUCR_HydroGs[D_Rng_BUCR2, :]),
				copy(BUCR_NuclearGs[D_Rng_BUCR2, :]),
				copy(BUCR_CogenGs[D_Rng_BUCR2, :]) )

			#TODO: Delete this
			#=BUCR2_Hr_Demand = BUCR_Demands[D_Rng_BUCR2, :]
	        BUCR2_Hr_SolarG = BUCR_SolarGs[D_Rng_BUCR2, :]
	        BUCR2_Hr_WindG = BUCR_WindGs[D_Rng_BUCR2, :]
	        BUCR2_Hr_HydroG = BUCR_HydroGs[D_Rng_BUCR2, :]
	        BUCR2_Hr_NuclearG = BUCR_NuclearGs[D_Rng_BUCR2, :]
	        BUCR2_Hr_CogenG = BUCR_CogenGs[D_Rng_BUCR2, :]
			=#

	        # Preprocessing module that fixes the commitment of slow-start units
			# to their FUCR's outcome and determines the binary commitment bounds
			# for fast-start units dependent to their initial up/down time and
			# minimum up/down time limits. If the units are slow their BAUC's
			# commitment is fixed to their FUCR's schedule
	        for g=1:GENS
	            # If DF_Generators.FastStart[g]==0 # if the units are slow their
				# BAUC's commitment is fixed to their FUCR's schedule
				BUCR2_Commit_LB[g] =  fix_uc_slow_start(SUCRtoBUCR2.gens.onoff[g,h]);
				BUCR2_Commit_UB[g] =  fix_uc_slow_start(SUCRtoBUCR2.gens.onoff[g,h]);
	            #= TODO: Delete this
				if SUCRtoBUCR2.gens.onoff[g,h]==0
	                BUCR2_Commit_LB[g] = 0;
	                BUCR2_Commit_UB[g] = 0;
	            else
	                BUCR2_Commit_LB[g] = 1;
	                BUCR2_Commit_UB[g] = 1;
	            end=#
	        end

	        # if the units are fast their BAUC's commitment could be fixed to 0
			# or 1 or vary between 0 or 1 dependent to their initial up/down
			# time and minimum up/down time
	        for k=1:PEAKERS
	            if BUCR2.peakers.dntime_init[k]==0
	                if BUCR2.peakers.uptime_init[k] < DF_Peakers.MinUpTime[k]
	                    BUCR2_Commit_Peaker_LB[k] = 1;
	                    BUCR2_Commit_Peaker_UB[k] = 1;
	                else
	                    BUCR2_Commit_Peaker_LB[k] = 0;
	                    BUCR2_Commit_Peaker_UB[k] = 1;
	                end
	            elseif BUCR2.peakers.dntime_init[k] < DF_Peakers.MinDownTime[k]
	                    BUCR2_Commit_Peaker_LB[k] = 0;
	                    BUCR2_Commit_Peaker_UB[k] = 0;
	            else
	                    BUCR2_Commit_Peaker_LB[k] = 0;
	                    BUCR2_Commit_Peaker_UB[k] = 1;
	            end
	        end

			# Run Second Balancing Unit Commitment Model
			FUCR, BUCR1, BUCR2 = bucr2_model(day, h, DF_Generators, DF_Peakers,
				DF_Storage, FuelPrice, FuelPricePeakers, Map_Gens, Map_Peakers,
				Map_Storage, FUCR, BUCR1, BUCR2, SUCRtoBUCR2, bucr2_prepoc,
				BUCR2_Commit_LB, BUCR2_Commit_UB, BUCR2_Commit_Peaker_LB,
				BUCR2_Commit_Peaker_UB)

		end # loop that runs hourly BUCR between 1 to (24 - INIT_HR_SUCR + INIT_HR_FUCR)

		t2_day_execution = time_ns()
		time_day_execution = (t2_day_execution - t1_day_execution)/1.0e9;

		open(".//outputs//time_performance.csv", FILE_ACCESS_APPEND) do io
				writedlm(io, hcat("Whole Day", time_day_execution,
						"day: $day", " ", "Whole Day Execution"), ',')
		end; #closes file

	end # foor loop that runs the UC model on  a daily basis

end; # end of run_main_code

##

# Function to "replace" values equal to zero by 0, 1 otherwise
fix_uc_slow_start(x::Int64) = x == 0 ? 0 : 1

# Function to replace values below 1 by 1
replace_lower_limit(x::Int64) = x < 1 ? 1 : x

run_main_code()

t2 = time_ns()
elapsedTime = (t2 -t1)/1.0e9;

write(io_log, "Whole program time execution (s):\t $elapsedTime\n")
@info "Whole Program setup executed in (s):" elapsedTime;

open(".//outputs//time_performance.csv", FILE_ACCESS_APPEND) do io
        writedlm(io, hcat("Whole Program", elapsedTime,
                "", "", "Whole Execution"), ',')
end; #closes file

close(io_log);
