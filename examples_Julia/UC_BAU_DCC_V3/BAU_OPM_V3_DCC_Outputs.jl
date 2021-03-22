# set the Directory to the local folder
#cd("C://Users//Ali Nikpendar//Google Drive//Julia files//Grace//Temp_Projects//dataentry")

#using Queryverse
using XLSX
using DataFrames
using Dates
using DelimitedFiles
using JuMP
using CPLEX
using CSV

# Parameters
const N_Gens =  8 # number of conventional generators
const N_StorgUs =  2 # number of storage units
const N_Zones = 2
const M_Zones = 10
const N_Blocks =7
const INITIAL_DAY = 1
const FINAL_DAY = 2
const INITIAL_HR_FUCR = 6 # represents the running time for the first WA unit commitment run. INITIAL_HR_FUCR=0 means the FUCR's optimal outcomes are ready at 00:00
const INITIAL_HR_SUCR = 17 # represents the running time for the second WA unit commitment run. INITIAL_HR_SUCR=17 means the SUCR's optimal outcomes are ready at 17:00
const N_Hrs_FUCR = 162 # N_Hrs_FUCR = 168-INITIAL_HR_FUCR, and INITIAL_HR_FUCR runs from 0 to 23; INITIAL_HR_FUCR=6 ==> N_Hrs_FUCR =162
const N_Hrs_SUCR = 151  # N_Hrs_SUCR = 168-INITIAL_HR_SUCR, and INITIAL_HR_SUCR runs from 17 to 23; INITIAL_HR_SUCR=17 ==> N_Hrs_FUCR =168

const FILE_ACCESS_OVER = "w+"
const FILE_ACCESS_APPEND = "a+"


# Logging file
io_log = open(
    string(
        ".//OOutputs//log//UC_BAU_",
        Dates.format(now(), "yyyy-mm-dd_HH-MM-SS"),
        ".txt",
    ),
    FILE_ACCESS_APPEND,
)

t1 = time_ns()

#const π
##
########################### Importing input data from the input spreadsheets
# Generators' specification

DF_Generators = DataFrame(XLSX.readtable(".\\IInputs\\data_generators.XLSX", "data_generators")...)

# Generators location map: if a generator g is located in zone z Map_Gens[g,z]=1; and 0 otherwise
DF_Map_Gens = DataFrame(XLSX.readtable(".\\IInputs\\data_generators.XLSX", "location_generators")...)
Map_Gens = convert(Matrix, DF_Map_Gens[:,2:N_Zones+1])

# Storage Units' specification and location
DF_Storage = DataFrame(XLSX.readtable(".\\IInputs\\data_storage.XLSX", "data_storage")...) # storage specs
DF_Map_Storage = DataFrame(XLSX.readtable(".\\IInputs\\data_storage.XLSX", "location_storage")...) # storage location as a dataframe
Map_Storage = convert(Matrix, DF_Map_Gens[:,2:N_Zones+1]) # convert storage location data to  a matrix

# energy demand at each location
#DF_Dems = DataFrame(XLSX.readtable(".\\Inputs\\data_demand.XLSX", "data_demand")...)
FUCR_Demands = XLSX.readdata(".\\IInputs\\data_demand.XLSX", "data_demand", "D2:M505")
SUCR_Demands = XLSX.readdata(".\\IInputs\\data_demand.XLSX", "data_demand_updated", "D2:M505")
BUCR_Demands = XLSX.readdata(".\\IInputs\\data_demand.XLSX", "data_demand_actual", "C2:L169")
# There is no map for the demand data. Instead we take the input demand data for each zone. In other words, Demand[t,z] represents demand at zone z and time t

# wind energy data for each location
FUCR_WindGs = XLSX.readdata(".\\IInputs\\data_wind.XLSX", "data_wind", "D2:M505")
SUCR_WindGs = XLSX.readdata(".\\IInputs\\data_wind.XLSX", "data_wind_updated", "D2:M505")
BUCR_WindGs = XLSX.readdata(".\\IInputs\\data_wind.XLSX", "data_wind_actual", "C2:L169")

#hydro generation data for each location
FUCR_HydroGs = XLSX.readdata(".\\IInputs\\data_hydro.XLSX", "data_hydro", "D2:M505")
SUCR_HydroGs = XLSX.readdata(".\\IInputs\\data_hydro.XLSX", "data_hydro_updated", "D2:M505")
BUCR_HydroGs = XLSX.readdata(".\\IInputs\\data_hydro.XLSX", "data_hydro_actual", "C2:L169")

# solar generation data at each location
FUCR_SolarGs = XLSX.readdata(".\\IInputs\\data_solar.XLSX", "data_solar", "D2:M505")
SUCR_SolarGs = XLSX.readdata(".\\IInputs\\data_solar.XLSX", "data_solar_updated", "D2:M505")
BUCR_SolarGs = XLSX.readdata(".\\IInputs\\data_solar.XLSX", "data_solar_actual", "C2:L169")

#Zonal Reserve Targets
Reserve_Req_Up = XLSX.readdata(".\\IInputs\\data_reserve_reqs.XLSX", "data_reserve_reqs", "A2:J2")

# Transmission system data (Capacity and Susceptance)
TranC = XLSX.readdata(".\\IInputs\\data_transmission.XLSX", "LineCapacity","B2:K11") # Transmission line capacity
TranS = XLSX.readdata(".\\IInputs\\data_transmission.XLSX", "LineSusceptance","B2:K11")# Transmission line susceptance

# Daily Fuel Price data
FuelPrice = XLSX.readdata(".\\IInputs\\data_generators.XLSX", "data_fuel_price", "C2:E9")

## Creating the output spreadsheet that save the optimal outcomes as reported by WA and RT UC Models
######## Spreadsheets for the first unit commitment run
# Creating Conventional generating units' schedules in the first unit commitment run
XLSX.openxlsx(".\\OOutputs\\FUCR_GenOutputs.xlsx", mode="w") do xf
    sheet = xf[1]
    XLSX.rename!(sheet, "new_sheet")
    sheet["A1:J1"] = ["Day" "Hour" "GeneratorID" "VariableCost" "MinPowerOut" "MaxPowerOut" "Output" "On/off" "ShutDown" "Startup"]
end
# Creating the spreadsheet for saving Conventional generating units' schedules in the first unit commitment run
XLSX.openxlsx(".\\OOutputs\\FUCR_StorageOutputs.xlsx", mode="w") do xf
    sheet = xf[1]
    XLSX.rename!(sheet, "new_sheet")
    sheet["A1:M1"] = ["Day" "Hour" "StorageUniID" "Power" "EnergyLimit" "Charge_St" "Discharge_St" "Idle_St" "storgChrgPwr" "storgDiscPwr" "storgSOC" "storgResUp" "storgResDn"]
end
#Creating the spreadsheet for writing and saving the transmission flow schedules in the first unit commitment run
XLSX.openxlsx(".\\OOutputs\\FUCR_TranFlowOutputs.xlsx", mode="w") do tf
    sheet = tf[1]
    XLSX.rename!(sheet, "new_sheet_II")
    sheet["A1:F1"] = ["Day" "Time period" "Source" "Sink" "Flow" "TransCap"]
end

######## Spreadsheets for the second unit commitment run
# Creating Conventional generating units' schedules in the second unit commitment run
XLSX.openxlsx(".\\OOutputs\\SUCR_GenOutputs.xlsx", mode="w") do xf
    sheet = xf[1]
    XLSX.rename!(sheet, "new_sheet")
    sheet["A1:J1"] = ["Day" "Hour" "GeneratorID" "VariableCost" "MinPowerOut" "MaxPowerOut" "Output" "On/off" "ShutDown" "Startup"]
end
# Creating the spreadsheet for saving Conventional generating units' schedules in the second unit commitment run
XLSX.openxlsx(".\\OOutputs\\SUCR_StorageOutputs.xlsx", mode="w") do xf
    sheet = xf[1]
    XLSX.rename!(sheet, "new_sheet")
    sheet["A1:M1"] = ["Day" "Hour" "StorageUniID" "Power" "EnergyLimit" "Charge_St" "Discharge_St" "Idle_St" "storgChrgPwr" "storgDiscPwr" "storgSOC" "storgResUp" "storgResDn"]
end
#Creating the spreadsheet for writing and saving the transmission flow schedules in the second unit commitment run
XLSX.openxlsx(".\\OOutputs\\SUCR_TranFlowOutputs.xlsx", mode="w") do tf
    sheet = tf[1]
    XLSX.rename!(sheet, "new_sheet_II")
    sheet["A1:F1"] = ["Day" "Time period" "Source" "Sink" "Flow" "TransCap"]
end

######## Spreadsheets for the first BUCR (BUCR1)
# Creating Conventional generating units' schedules in the second unit commitment run
XLSX.openxlsx(".\\OOutputs\\BUCR_GenOutputs.xlsx", mode="w") do xf
    sheet = xf[1]
    XLSX.rename!(sheet, "new_sheet")
    sheet["A1:J1"] = ["Day" "Hour" "GeneratorID" "VariableCost" "MinPowerOut" "MaxPowerOut" "Output" "On/off" "ShutDown" "Startup"]
end
# Creating the spreadsheet for saving Conventional generating units' schedules in the second unit commitment run
XLSX.openxlsx(".\\OOutputs\\BUCR_StorageOutputs.xlsx", mode="w") do xf
    sheet = xf[1]
    XLSX.rename!(sheet, "new_sheet")
    sheet["A1:M1"] = ["Day" "Hour" "StorageUniID" "Power" "EnergyLimit" "Charge_St" "Discharge_St" "Idle_St" "storgChrgPwr" "storgDiscPwr" "storgSOC" "storgResUp" "storgResDn"]
end
#Creating the spreadsheet for writing and saving the transmission flow schedules in the second unit commitment run
XLSX.openxlsx(".\\OOutputs\\BUCR_TranFlowOutputs.xlsx", mode="w") do tf
    sheet = tf[1]
    XLSX.rename!(sheet, "new_sheet_II")
    sheet["A1:F1"] = ["Day" "Time period" "Source" "Sink" "Flow" "TransCap"]
end



## Creating variables that transfer optimal schedules between the Models

#### Some of the below variables may be unneccsary and can be deletetd. Check at the end
FUCRtoBUCR1_genOnOff = zeros(N_Gens,INITIAL_HR_SUCR-INITIAL_HR_FUCR)
FUCRtoBUCR1_genOut = zeros(N_Gens,INITIAL_HR_SUCR-INITIAL_HR_FUCR)
FUCRtoBUCR1_genOut_Block = zeros(N_Gens,N_Blocks,INITIAL_HR_SUCR-INITIAL_HR_FUCR)
FUCRtoBUCR1_genStartUp = zeros(N_Gens,INITIAL_HR_SUCR-INITIAL_HR_FUCR)
FUCRtoBUCR1_genShutDown= zeros(N_Gens,INITIAL_HR_SUCR-INITIAL_HR_FUCR)


FUCRtoBUCR1_storgChrg = zeros(N_StorgUs, INITIAL_HR_SUCR-INITIAL_HR_FUCR)
FUCRtoBUCR1_storgDisc = zeros(N_StorgUs, INITIAL_HR_SUCR-INITIAL_HR_FUCR)
FUCRtoBUCR1_storgIdle = zeros(N_StorgUs, INITIAL_HR_SUCR-INITIAL_HR_FUCR)
FUCRtoBUCR1_storgChrgPwr = zeros(N_StorgUs, INITIAL_HR_SUCR-INITIAL_HR_FUCR)
FUCRtoBUCR1_storgDiscPwr = zeros(N_StorgUs, INITIAL_HR_SUCR-INITIAL_HR_FUCR)
FUCRtoBUCR1_storgSOC = zeros(N_StorgUs, INITIAL_HR_SUCR-INITIAL_HR_FUCR)

SUCRtoBUCR2_genOnOff = zeros(N_Gens,24-INITIAL_HR_SUCR+INITIAL_HR_FUCR)
SUCRtoBUCR2_genOut = zeros(N_Gens,24-INITIAL_HR_SUCR+INITIAL_HR_FUCR)
SUCRtoBUCR2_genOut_Block = zeros(N_Gens,N_Blocks,24-INITIAL_HR_SUCR+INITIAL_HR_FUCR)
SUCRtoBUCR2_genStartUp = zeros(N_Gens,24-INITIAL_HR_SUCR+INITIAL_HR_FUCR)
SUCRtoBUCR2_genShutDown= zeros(N_Gens,24-INITIAL_HR_SUCR+INITIAL_HR_FUCR)


SUCRtoBUCR2_storgChrg = zeros(N_StorgUs, 24-INITIAL_HR_SUCR+INITIAL_HR_FUCR)
SUCRtoBUCR2_storgDisc = zeros(N_StorgUs, 24-INITIAL_HR_SUCR+INITIAL_HR_FUCR)
SUCRtoBUCR2_storgIdle = zeros(N_StorgUs, 24-INITIAL_HR_SUCR+INITIAL_HR_FUCR)
SUCRtoBUCR2_storgChrgPwr = zeros(N_StorgUs, 24-INITIAL_HR_SUCR+INITIAL_HR_FUCR)
SUCRtoBUCR2_storgDiscPwr = zeros(N_StorgUs, 24-INITIAL_HR_SUCR+INITIAL_HR_FUCR)
SUCRtoBUCR2_storgSOC = zeros(N_StorgUs, 24-INITIAL_HR_SUCR+INITIAL_HR_FUCR)

#=
BUCR1toSUCR_genOnOff = zeros(N_Gens,24-INITIAL_HR_SUCR+INITIAL_HR_FUCR)
BUCR1toSUCR_genOut = zeros(N_Gens,24-INITIAL_HR_SUCR+INITIAL_HR_FUCR)
FUCR1toSUCR_genStartUp = zeros(N_Gens,24-INITIAL_HR_SUCR-INITIAL_HR_FUCR)
BUCR1toSUCR_genShutDown= zeros(N_Gens,INITIAL_HR_SUCR-INITIAL_HR_FUCR)


BUCR1toSUCR_storgChrg = zeros(N_StorgUs,24-INITIAL_HR_SUCR+INITIAL_HR_FUCR)
BUCR1toSUCR_storgDisc = zeros(N_StorgUs,24-INITIAL_HR_SUCR+INITIAL_HR_FUCR)
BUCR1toSUCR_storgIdle = zeros(N_StorgUs,24-INITIAL_HR_SUCR+INITIAL_HR_FUCR)
BUCR1toSUCR_storgChrgPwr = zeros(N_StorgUs,24-INITIAL_HR_SUCR+INITIAL_HR_FUCR)
BUCR1toSUCR_storgDiscPwr = zeros(N_StorgUs,24-INITIAL_HR_SUCR+INITIAL_HR_FUCR)
BUCR1toSUCR_storgSOC = zeros(N_StorgUs,24-INITIAL_HR_SUCR+INITIAL_HR_FUCR)


BUCR1toBUCR2_genOnOff = zeros(N_Gens,??)
BUCR1toBUCR2_genOut = zeros(N_Gens,??)
FUCR1toBUCR2_genStartUp = zeros(N_Gens,??)
BUCR1toBUCR2_genShutDown= zeros(N_Gens,??)

BUCR1toBUCR2_storgChrg = zeros(N_StorgUs,??)
BUCR1toBUCR2_storgDisc = zeros(N_StorgUs,??)
BUCR1toBUCR2_storgIdle = zeros(N_StorgUs,???)
BUCR1toBUCR2_storgChrgPwr = zeros(N_StorgUs,??)
BUCR1toBUCR2_storgDiscPwr = zeros(N_StorgUs,????)
BUCR1toBUCR2_storgSOC = zeros(N_StorgUs,???)
=#

## Auxiliary variables for enforcing commitment of slow and fast-start units in BUCRs
BUCR1_Commit_LB = zeros(N_Gens)
BUCR1_Commit_UB = zeros(N_Gens)
BUCR2_Commit_LB = zeros(N_Gens)
BUCR2_Commit_UB = zeros(N_Gens)
## Auxiliary variables representing the initial values for commitment/dispatch schedules fed to different Models
FUCR_Init_genOnOff = zeros(N_Gens)
FUCR_Init_genOut = zeros(N_Gens)
FUCR_Init_UpTime = zeros(N_Gens)
FUCR_Init_DownTime = zeros(N_Gens)
FUCR_Init_storgSOC = zeros(N_StorgUs)


SUCR_Init_genOnOff = zeros(N_Gens)
SUCR_Init_genOut = zeros(N_Gens)
SUCR_Init_UpTime = zeros(N_Gens)
SUCR_Init_DownTime = zeros(N_Gens)
SUCR_Init_storgSOC = zeros(N_StorgUs)

BUCR1_Init_genOnOff = zeros(N_Gens)
BUCR1_Init_genOut = zeros(N_Gens)
BUCR1_Init_UpTime = zeros(N_Gens)
BUCR1_Init_DownTime = zeros(N_Gens)
BUCR1_Init_storgSOC = zeros(N_StorgUs)

BUCR2_Init_genOnOff = zeros(N_Gens)
BUCR2_Init_genOut = zeros(N_Gens)
BUCR2_Init_UpTime = zeros(N_Gens)
BUCR2_Init_DownTime = zeros(N_Gens)
BUCR2_Init_storgSOC = zeros(N_StorgUs)
## Pre-processing the data to calculate the model inputs:
#=
## Pre-processing calculations for the first method enforcing min up and down time constraints
ReqUpTime=zeros(N_Gens,1) # Difference between minimum up time and  the number of periods that unit g was on before t=1 of the scheduling horizon
ReqUpTimeInit=zeros(N_Gens,1) #determined based on ReqDnTime, represents the number of periods that unit must remain on at the beginning of scheduling horizon
ReqDnTime=zeros(N_Gens,1) # Difference between minimum down time and  the number of periods that unit g was off before t=1 of the scheduling horizon
ReqDnTimeInit=zeros(N_Gens,1) #determined based on ReqDnTime, represents the number of periods that unit must remain off at the beginning of scheduling horizon

for g in 1:N_Gens
   ReqUpTime[g] = (DF_Generators.MinUpTime[g] - DF_Generators.UpTimeInit[g])*DF_Generators.StatusInit[g]
   if (ReqUpTime[g] > N_Hrs)
      ReqUpTimeInit[g] = N_Hrs
   elseif (ReqUpTime[g] <0)
      ReqUpTimeInit[g] = 0
   else
      ReqUpTimeInit[g] = ReqUpTime[g]
   end
end
ReqUpTimeInit_I = round.(Int,ReqUpTimeInit)

for g in 1:N_Gens
   ReqDnTime[g] = (DF_Generators.MinDownTime[g] - DF_Generators.DownTimeInit[g])*(1-DF_Generators.StatusInit[g])
   if (ReqDnTime[g] > N_Hrs)
      ReqDnTimeInit[g] = N_Hrs
   elseif (ReqDnTime[g] <0)
      ReqDnTimeInit[g] = 0
   else
      ReqDnTimeInit[g] = ReqDnTime[g]
   end
end
ReqDnTimeInit_I = round.(Int,ReqDnTimeInit)
=#
##
# The time range lower-bound for min up constrain using the alternative approach
lbu=zeros(N_Gens,N_Hrs_FUCR)
for g in 1:N_Gens , t in 1:N_Hrs_FUCR
    lbu[g,t]=t-DF_Generators.MinUpTime[g]+1
    if (lbu[g,t]<1)
        lbu[g,t]=1
    end
end

lb_MUT = round.(Int, lbu)

lbd=zeros(N_Gens,N_Hrs_FUCR)
for g in 1:N_Gens , t in 1:N_Hrs_FUCR
    lbd[g,t]=t-DF_Generators.MinDownTime[g]+1
    if (lbd[g,t]<1)
        lbd[g,t]=1
    end
end

lb_MDT = round.(Int, lbd)

##
#**********
#**********
#**********
# We need two more loops for calculating the lb_MUT abd lb_MDT for the second UC runs
#************************************************************************************
#************************************************************************************
## The foor loop runs two WAUC models and the RTUC models every day
for day = INITIAL_DAY:FINAL_DAY
    # Setting initial values
    if day ==1
        global FUCR_Init_genOnOff = DF_Generators.StatusInit
        global FUCR_Init_genOut = DF_Generators.PowerInit
        global FUCR_Init_UpTime = DF_Generators.UpTimeInit
        global FUCR_Init_DownTime = DF_Generators.DownTimeInit
        global FUCR_Init_storgSOC = DF_Storage.SOCInit
        global BUCR1_Init_genOnOff = DF_Generators.StatusInit
        global BUCR1_Init_genOut = DF_Generators.PowerInit
        global BUCR1_Init_UpTime = DF_Generators.UpTimeInit
        global BUCR1_Init_DownTime = DF_Generators.DownTimeInit
        global BUCR1_Init_storgSOC = DF_Storage.SOCInit
    end

    # Demand Data Pre-Processing for FUCR and SUCR
    D_Rng_Dn_FUCR = ((day-1)*(INITIAL_HR_FUCR+N_Hrs_FUCR))+INITIAL_HR_FUCR+1  # Bottom cell of the demand data needed for running the first WAUC run at 6 am with 7-day look-ahead horizon
    D_Rng_Up_FUCR = day*(INITIAL_HR_FUCR+N_Hrs_FUCR)  # Upper  cell of the demand data needed for running the first WAUC run at 6 am with 7-day look-ahead horizon
    FUCR_WA_Demand = FUCR_Demands[D_Rng_Dn_FUCR:D_Rng_Up_FUCR, :] # week-ahead demand data for the first UC run at 6 am
    FUCR_WA_SolarG = FUCR_SolarGs[D_Rng_Dn_FUCR:D_Rng_Up_FUCR, :] # week-ahead SolarG data for the first UC run at 6 am
    FUCR_WA_WindG = FUCR_WindGs[D_Rng_Dn_FUCR:D_Rng_Up_FUCR, :] # week-ahead WindG data for the first UC run at 6 am
    FUCR_WA_HydroG = FUCR_HydroGs[D_Rng_Dn_FUCR:D_Rng_Up_FUCR, :] # week-ahead HydroG data for the first UC run at 6 am


    D_Rng_Dn_SUCR = ((day-1)*(INITIAL_HR_FUCR+N_Hrs_FUCR))+INITIAL_HR_SUCR+1 # Bottom cell of the demand data needed for running the second WAUC run at 5 pm with 7-day look-ahead horizon
    D_Rng_Up_SUCR = day*(INITIAL_HR_FUCR+N_Hrs_FUCR) # Upper  cell of the demand data needed for running the second WAUC run at pm with 7-day look-ahead horizon
    SUCR_WA_Demand = SUCR_Demands[D_Rng_Dn_SUCR:D_Rng_Up_SUCR, :] # week-ahead demand data for the first UC run at 5 pm
    SUCR_WA_SolarG = SUCR_SolarGs[D_Rng_Dn_SUCR:D_Rng_Up_SUCR, :] # week-ahead SolarG data for the first UC run at 5 pm
    SUCR_WA_WindG = SUCR_WindGs[D_Rng_Dn_SUCR:D_Rng_Up_SUCR, :] # week-ahead WindG data for the first UC run at 5 pm
    SUCR_WA_HydroG = SUCR_HydroGs[D_Rng_Dn_SUCR:D_Rng_Up_SUCR, :] # week-ahead HydroG data for the first UC run at 5 pm


## This block models the first UC optimization that is run in the morning
    #FUCRmodel=Model(with_optimizer(CPLEX.Optimizer))
    FUCRmodel = direct_model(CPLEX.Optimizer())
    #set_optimizer_attribute(FUCRmodel, "CPX_PARAM_EPINT", 1e-5)
    #set_optimizer_attribute(FUCRmodel, "CPX_PARAM_EPINT", 0.2)
    #set_optimizer_attribute(FUCRmodel, "CPX_PARAM_EPGAP", 0.00001)

# Declaring the decision variables for conventional generators
    @variable(FUCRmodel, FUCR_genOnOff[1:N_Gens, 0:N_Hrs_FUCR], Bin) #Bin
    @variable(FUCRmodel, FUCR_genStartUp[1:N_Gens, 1:N_Hrs_FUCR], Bin) # startup variable
    @variable(FUCRmodel, FUCR_genShutDown[1:N_Gens, 1:N_Hrs_FUCR], Bin) # shutdown variable
    @variable(FUCRmodel, FUCR_genOut[1:N_Gens, 0:N_Hrs_FUCR]>=0) # Generator's output schedule
    @variable(FUCRmodel, FUCR_genOut_Block[1:N_Gens, 1:N_Blocks, 1:N_Hrs_FUCR]>=0) # Generator's output schedule from each block (block rfers to IHR curve blocks/segments)
    @variable(FUCRmodel, FUCR_genResUp[1:N_Gens, 1:N_Hrs_FUCR]>=0) # Generators' up reserve schedule
    @variable(FUCRmodel, FUCR_genResDn[1:N_Gens, 1:N_Hrs_FUCR]>=0) # Generator's down rserve schedule

# declaring decision variables for storage Units
    @variable(FUCRmodel, FUCR_storgChrg[1:N_StorgUs, 1:N_Hrs_FUCR], Bin) #Bin variable equal to 1 if unit runs in the charging mode
    @variable(FUCRmodel, FUCR_storgDisc[1:N_StorgUs, 1:N_Hrs_FUCR], Bin) #Bin variable equal to 1 if unit runs in the discharging mode
    @variable(FUCRmodel, FUCR_storgIdle[1:N_StorgUs, 1:N_Hrs_FUCR], Bin) ##Bin variable equal to 1 if unit runs in the idle mode
    @variable(FUCRmodel, FUCR_storgChrgPwr[1:N_StorgUs, 0:N_Hrs_FUCR]>=0) #Chargung power
    @variable(FUCRmodel, FUCR_storgDiscPwr[1:N_StorgUs, 0:N_Hrs_FUCR]>=0) # Discharging Power
    @variable(FUCRmodel, FUCR_storgSOC[1:N_StorgUs, 0:N_Hrs_FUCR]>=0) # state of charge (stored energy level for storage unit at time t)
    @variable(FUCRmodel, FUCR_storgResUp[1:N_StorgUs, 0:N_Hrs_FUCR]>=0) # Scheduled up reserve
    @variable(FUCRmodel, FUCR_storgResDn[1:N_StorgUs, 0:N_Hrs_FUCR]>=0) # Scheduled down reserve

# declaring decision variables for renewable generation
    @variable(FUCRmodel, FUCR_solarG[1:N_Zones, 1:N_Hrs_FUCR]>=0) # solar energy schedules
    @variable(FUCRmodel, FUCR_windG[1:N_Zones, 1:N_Hrs_FUCR]>=0) # wind energy schedules
    @variable(FUCRmodel, FUCR_hydroG[1:N_Zones, 1:N_Hrs_FUCR]>=0) # hydro energy schedules
    @variable(FUCRmodel, FUCR_solarGSpil[1:N_Zones, 1:N_Hrs_FUCR]>=0) # solar energy schedules
    @variable(FUCRmodel, FUCR_windGSpil[1:N_Zones, 1:N_Hrs_FUCR]>=0) # wind energy schedules
    @variable(FUCRmodel, FUCR_hydroGSpil[1:N_Zones, 1:N_Hrs_FUCR]>=0) # hydro energy schedules

# declaring variables for transmission system
    @variable(FUCRmodel, FUCR_voltAngle[1:N_Zones, 1:N_Hrs_FUCR]) #voltage angle at zone/bus n in t//
    @variable(FUCRmodel, FUCR_powerFlow[1:N_Zones, 1:M_Zones, 1:N_Hrs_FUCR]) #transmission Flow from zone n to zone m//

# Defining the objective function that minimizes the overal cost of supplying electricity (=total variable, no-load, startup, and shutdown costs)

    @objective(FUCRmodel, Min, sum(sum(DF_Generators.IHRC_B1_HR[g]*FuelPrice[g,day]*FUCR_genOut_Block[g,1,t]
                                       +DF_Generators.IHRC_B2_HR[g]*FuelPrice[g,day]*FUCR_genOut_Block[g,2,t]
                                       +DF_Generators.IHRC_B3_HR[g]*FuelPrice[g,day]*FUCR_genOut_Block[g,3,t]
                                       +DF_Generators.IHRC_B4_HR[g]*FuelPrice[g,day]*FUCR_genOut_Block[g,4,t]
                                       +DF_Generators.IHRC_B5_HR[g]*FuelPrice[g,day]*FUCR_genOut_Block[g,5,t]
                                       +DF_Generators.IHRC_B6_HR[g]*FuelPrice[g,day]*FUCR_genOut_Block[g,6,t]
                                       +DF_Generators.IHRC_B7_HR[g]*FuelPrice[g,day]*FUCR_genOut_Block[g,7,t]
                                       +DF_Generators.NoLoadHR[g]*FuelPrice[g,day]*FUCR_genOnOff[g,t] +((DF_Generators.FixedSUCost[g]+(DF_Generators.StartUpHR[g]*FuelPrice[g,day]))*FUCR_genStartUp[g,t])
                                       +DF_Generators.ShutdownCost[g]*FUCR_genShutDown[g, t] for g in 1:N_Gens) for t in 1:N_Hrs_FUCR))



#Initialization of commitment and dispatch variables at t=0 (representing the last hour of previous scheduling horizon day=day-1 and t=24)
    @constraint(FUCRmodel, conInitGenOnOff[g=1:N_Gens], FUCR_genOnOff[g,0]==FUCR_Init_genOnOff[g]) # initial generation level for generator g at t=0
    @constraint(FUCRmodel, conInitGenOut[g=1:N_Gens], FUCR_genOut[g,0]==FUCR_Init_genOut[g]) # initial on/off status for generators g at t=0
    @constraint(FUCRmodel, conInitSOC[p=1:N_StorgUs], FUCR_storgSOC[p,0]==FUCR_Init_storgSOC[p]) # SOC for storage unit p at t=0

# Constraints representing technical limits of conventional generators
#Status transition trajectory of
    @constraint(FUCRmodel, conStartUpAndDn[t=1:N_Hrs_FUCR, g=1:N_Gens], (FUCR_genOnOff[g,t] - FUCR_genOnOff[g,t-1] - FUCR_genStartUp[g,t] + FUCR_genShutDown[g,t])==0)
# Max Power generation limit in Block 1
    @constraint(FUCRmodel, conMaxPowBlock1[t=1:N_Hrs_FUCR, g=1:N_Gens],  FUCR_genOut_Block[g,1,t] <= DF_Generators.IHRC_B1_Q[g]*FUCR_genOnOff[g,t] )
# Max Power generation limit in Block 2
    @constraint(FUCRmodel, conMaxPowBlock2[t=1:N_Hrs_FUCR, g=1:N_Gens],  FUCR_genOut_Block[g,2,t] <= DF_Generators.IHRC_B2_Q[g]*FUCR_genOnOff[g,t] )
# Max Power generation limit in Block 3
    @constraint(FUCRmodel, conMaxPowBlock3[t=1:N_Hrs_FUCR, g=1:N_Gens],  FUCR_genOut_Block[g,3,t] <= DF_Generators.IHRC_B3_Q[g]*FUCR_genOnOff[g,t] )
# Max Power generation limit in Block 4
    @constraint(FUCRmodel, conMaxPowBlock4[t=1:N_Hrs_FUCR, g=1:N_Gens],  FUCR_genOut_Block[g,4,t] <= DF_Generators.IHRC_B4_Q[g]*FUCR_genOnOff[g,t] )
# Max Power generation limit in Block 5
    @constraint(FUCRmodel, conMaxPowBlock5[t=1:N_Hrs_FUCR, g=1:N_Gens],  FUCR_genOut_Block[g,5,t] <= DF_Generators.IHRC_B5_Q[g]*FUCR_genOnOff[g,t] )
# Max Power generation limit in Block 6
    @constraint(FUCRmodel, conMaxPowBlock6[t=1:N_Hrs_FUCR, g=1:N_Gens],  FUCR_genOut_Block[g,6,t] <= DF_Generators.IHRC_B6_Q[g]*FUCR_genOnOff[g,t] )
# Max Power generation limit in Block 7
    @constraint(FUCRmodel, conMaxPowBlock7[t=1:N_Hrs_FUCR, g=1:N_Gens],  FUCR_genOut_Block[g,7,t] <= DF_Generators.IHRC_B7_Q[g]*FUCR_genOnOff[g,t] )
# Total Production of each generation equals the sum of generation from its all blocks
    @constraint(FUCRmodel, conTotalGen[t=1:N_Hrs_FUCR, g=1:N_Gens],  FUCR_genOut[g,t] == sum(FUCR_genOut_Block[g,b,t] for b=1:N_Blocks))
#Max power generation limit
    @constraint(FUCRmodel, conMaxPow[t=1:N_Hrs_FUCR, g=1:N_Gens],  FUCR_genOut[g,t]+FUCR_genResUp[g,t] <= DF_Generators.MaxPowerOut[g]*FUCR_genOnOff[g,t] )
# Min power generation limit
    @constraint(FUCRmodel, conMinPow[t=1:N_Hrs_FUCR, g=1:N_Gens],  FUCR_genOut[g,t]-FUCR_genResDn[g,t] >= DF_Generators.MinPowerOut[g]*FUCR_genOnOff[g,t] )
# Up reserve provision limit
    @constraint(FUCRmodel, conMaxResUp[t=1:N_Hrs_FUCR, g=1:N_Gens], FUCR_genResUp[g,t] <= DF_Generators.UpReserveLimit[g]*FUCR_genOnOff[g,t] )
#Down reserve provision limit
    @constraint(FUCRmodel, conMaxResDown[t=1:N_Hrs_FUCR, g=1:N_Gens],  FUCR_genResDn[g,t] <= DF_Generators.DownReserveLimit[g]*FUCR_genOnOff[g,t] )
#Up ramp rate limit
    @constraint(FUCRmodel, conRampRateUp[t=1:N_Hrs_FUCR, g=1:N_Gens], (FUCR_genOut[g,t] - FUCR_genOut[g,t-1] <=(DF_Generators.RampUpLimit[g]*FUCR_genOnOff[g, t-1]) + (DF_Generators.RampStartUpLimit[g]*FUCR_genStartUp[g,t])))
# Down ramp rate limit
    @constraint(FUCRmodel, conRampRateDown[t=1:N_Hrs_FUCR, g=1:N_Gens], (FUCR_genOut[g,t-1] - FUCR_genOut[g,t] <=(DF_Generators.RampDownLimit[g]*FUCR_genOnOff[g,t]) + (DF_Generators.RampShutDownLimit[g]*FUCR_genShutDown[g,t])))
# Min Up Time limit with alternative formulation
    @constraint(FUCRmodel, conUpTime[t=1:N_Hrs_FUCR, g=1:N_Gens], (sum(FUCR_genStartUp[g,k] for k=lb_MUT[g,t]:t)<=FUCR_genOnOff[g,t]))
# Min down Time limit with alternative formulation
    @constraint(FUCRmodel, conDownTime[t=1:N_Hrs_FUCR, g=1:N_Gens], (1-sum(FUCR_genShutDown[g,i] for i=lb_MDT[g,t]:t)>=FUCR_genOnOff[g,t]))

# Renewable generation constraints

    @constraint(FUCRmodel, conSolarLimit[t=1:N_Hrs_FUCR, n=1:N_Zones], FUCR_solarG[n, t] + FUCR_solarGSpil[n,t]<=FUCR_WA_SolarG[t,n])
    @constraint(FUCRmodel, conWindLimit[t=1:N_Hrs_FUCR, n=1:N_Zones], FUCR_windG[n, t] + FUCR_windGSpil[n,t]<=FUCR_WA_WindG[t,n])
    @constraint(FUCRmodel, conHydroLimit[t=1:N_Hrs_FUCR, n=1:N_Zones], FUCR_hydroG[n, t] + FUCR_hydroGSpil[n,t]<=FUCR_WA_HydroG[t,n])
#=
    @constraint(FUCRmodel, conSolarLimit[t=1:N_Hrs_FUCR, n=1:N_Zones], FUCR_solarG[n, t] + FUCR_solarGSpil[n,t]<=0)
    @constraint(FUCRmodel, conWindLimit[t=1:N_Hrs_FUCR, n=1:N_Zones], FUCR_windG[n, t] + FUCR_windGSpil[n,t]<=0)
    @constraint(FUCRmodel, conHydroLimit[t=1:N_Hrs_FUCR, n=1:N_Zones], FUCR_hydroG[n, t] + FUCR_hydroGSpil[n,t]<=0)
=#

# Constraints representing technical characteristics of storage units
# status transition of storage units between charging, discharging, and idle modes
    @constraint(FUCRmodel, conStorgStatusTransition[t=1:N_Hrs_FUCR, p=1:N_StorgUs], (FUCR_storgChrg[p,t]+FUCR_storgDisc[p,t]+FUCR_storgIdle[p,t])==1)
# charging power limit
    @constraint(FUCRmodel, conStrgChargPowerLimit[t=1:N_Hrs_FUCR, p=1:N_StorgUs], (FUCR_storgChrgPwr[p,t] - FUCR_storgResDn[p,t])<=DF_Storage.Power[p]*FUCR_storgChrg[p,t])
# Discharging power limit
    @constraint(FUCRmodel, conStrgDisChgPowerLimit[t=1:N_Hrs_FUCR, p=1:N_StorgUs], (FUCR_storgDiscPwr[p,t] + FUCR_storgResUp[p,t])<=DF_Storage.Power[p]*FUCR_storgDisc[p,t])
# Down reserve provision limit
    @constraint(FUCRmodel, conStrgDownResrvMax[t=1:N_Hrs_FUCR, p=1:N_StorgUs], FUCR_storgResDn[p,t]<=DF_Storage.Power[p]*FUCR_storgChrg[p,t])
# Up reserve provision limit`
    @constraint(FUCRmodel, conStrgUpResrvMax[t=1:N_Hrs_FUCR, p=1:N_StorgUs], FUCR_storgResUp[p,t]<=DF_Storage.Power[p]*FUCR_storgDisc[p,t])
# State of charge at t
    @constraint(FUCRmodel, conStorgSOC[t=1:N_Hrs_FUCR, p=1:N_StorgUs], FUCR_storgSOC[p,t]==FUCR_storgSOC[p,t-1]-(FUCR_storgDiscPwr[p,t]/DF_Storage.TripEfficDown[p])+(FUCR_storgChrgPwr[p,t]*DF_Storage.TripEfficUp[p])-(FUCR_storgSOC[p,t]*DF_Storage.SelfDischarge[p]))
# minimum energy limit
    @constraint(FUCRmodel, conMinEnrgStorgLimi[t=1:N_Hrs_FUCR, p=1:N_StorgUs], FUCR_storgSOC[p,t]-(FUCR_storgResUp[p,t]/DF_Storage.TripEfficDown[p])+(FUCR_storgResDn[p,t]/DF_Storage.TripEfficUp[p])>=0)
# Maximum energy limit
    @constraint(FUCRmodel, conMaxEnrgStorgLimi[t=1:N_Hrs_FUCR, p=1:N_StorgUs], FUCR_storgSOC[p,t]-(FUCR_storgResUp[p,t]/DF_Storage.TripEfficDown[p])+(FUCR_storgResDn[p,t]/DF_Storage.TripEfficUp[p])<=(DF_Storage.Power[p]/DF_Storage.PowerToEnergRatio[p]))
# Constraints representing transmission grid capacity constraints
# DC Power Flow Calculation
    @constraint(FUCRmodel, conDCPowerFlowPos[t=1:N_Hrs_FUCR, n=1:N_Zones, m=1:N_Zones], FUCR_powerFlow[n,m,t]-(TranS[n,m]*(FUCR_voltAngle[n,t]-FUCR_voltAngle[m,t])) ==0)
    @constraint(FUCRmodel, conDCPowerFlowNeg[t=1:N_Hrs_FUCR, n=1:N_Zones, m=1:N_Zones], FUCR_powerFlow[n,m,t]+FUCR_powerFlow[m,n,t]==0)
# Tranmission flow bounds (from n to m and from m to n)
#    @constraint(FUCRmodel, conPosFlowLimit[t=1:N_Hrs_FUCR, n=1:N_Zones, m=1:N_Zones], powerFlow[n,m,t]<=TranC[n,m])
#    @constraint(FUCRmodel, conNegFlowLimit[t=1:N_Hrs_FUCR, n=1:N_Zones, m=1:N_Zones], powerFlow[m,n,t]>=-TranC[n,m])
# Voltage Angle bounds and reference point
    @constraint(FUCRmodel, conVoltAnglUB[t=1:N_Hrs_FUCR, n=1:N_Zones], FUCR_voltAngle[n,t]<=π)
    @constraint(FUCRmodel, conVoltAnglLB[t=1:N_Hrs_FUCR, n=1:N_Zones], FUCR_voltAngle[n,t]>=-π)
    @constraint(FUCRmodel, conVoltAngRef[t=1:N_Hrs_FUCR], FUCR_voltAngle[1,t]==0)

# System-wide Constraints
#nodal balance constraint
    @constraint(FUCRmodel, conNodBalanc[t=1:N_Hrs_FUCR, n=1:N_Zones], sum((FUCR_genOut[g,t]*Map_Gens[g,n]) for g=1:N_Gens) + sum((FUCR_storgDiscPwr[p,t]*Map_Storage[p,n]) for p=1:N_StorgUs) - sum((FUCR_storgChrgPwr[p,t]*Map_Storage[p,n]) for p=1:N_StorgUs) +FUCR_solarG[n, t] +FUCR_windG[n, t] +FUCR_hydroG[n, t] - FUCR_WA_Demand[t,n] == sum(FUCR_powerFlow[n,m,t] for m=1:M_Zones))
# Minimum zonal up reserve requirement, if there are more than two zones, we should  define reserve regions for DEC and DEP
#    @constraint(FUCRmodel, conMinUpReserveReq[t=1:N_Hrs_FUCR, n=1:N_Zones], sum((FUCR_genResUp[g,t]*Map_Gens[g,n]) for g=1:N_Gens) + sum((FUCR_storgResUp[p,t]*Map_Storage[p,n]) for p=1:N_StorgUs) >= Reserve_Req_Up[n] )

# Minimum down reserve requirement
#    @constraint(FUCRmodel, conMinDnReserveReq[t=1:N_Hrs_FUCR], sum(genResDn[g,t] for g=1:N_Gens) + sum(storgResDn[p,t] for p=1:N_StorgUs) >= Reserve_Req_Dn[t] )

# solve the First WAUC model (FUCR)
    JuMP.optimize!(FUCRmodel)

# Pricing general results in the terminal window
    println("Objective value: ", JuMP.objective_value(FUCRmodel))

    println("------------------------------------")
    println("------- FUCR OBJECTIVE VALUE -------")
    println("Objective value for day", day, ": ", JuMP.objective_value(FUCRmodel))
    println("------------------------------------")
    println("-------FUCR PRIMAL STATUS -------")
    println(primal_status(FUCRmodel))
    println("------------------------------------")
    println("------- FUCR DUAL STATUS -------")
    println(JuMP.dual_status(FUCRmodel))
    println("Day:", day, ": solved")
    println("---------------------------")

#########################################################
# Write the optimal outcomes into spreadsheets###########
############# Later we need to include a variable for day so the cell number in which the results are printed is updated accordingly

FUCR_GenOutputs_header     = ["Day", "Hour", "GeneratorID", "VariableCost","MinPowerOut", "MaxPowerOut", "Output", "On/off", "ShutDown", "Startup"]
FUCR_StorageOutputs_header = ["Day", "Hour", "StorageUniID", "Power", "EnergyLimit", "Charge_St", "Discharge_St", "Idle_St", "storgChrgPwr", "storgDiscPwr", "storgSOC", "storgResUp", "storgResDn"]
FUCR_TranFlowOutputs_header= ["Day", "Time period", "Source", "Sink", "Flow", "TransCap"]
SUCR_GenOutputs_header     = ["Day", "Hour", "GeneratorID", "VariableCost", "MinPowerOut", "MaxPowerOut", "Output", "On/off", "ShutDown", "Startup"]
SUCR_StorageOutputs_header = ["Day", "Hour", "StorageUniID", "Power", "EnergyLimit", "Charge_St", "Discharge_St", "Idle_St", "storgChrgPwr", "storgDiscPwr", "storgSOC", "storgResUp", "storgResDn"]
SUCR_TranFlowOutputs_header= ["Day", "Time period", "Source", "Sink", "Flow", "TransCap"]
BUCR_GenOutputs_header    =  ["Day", "Hour", "GeneratorID", "VariableCost", "MinPowerOut", "MaxPowerOut", "Output", "On/off", "ShutDown", "Startup"]
BUCR_StorageOutputs_header = ["Day", "Hour", "StorageUniID", "Power", "EnergyLimit", "Charge_St", "Discharge_St", "Idle_St", "storgChrgPwr", "storgDiscPwr", "storgSOC", "storgResUp", "storgResDn"]
BUCR_TranFlowOutputs_header= ["Day", "Time period", "Source", "Sink", "Flow", "TransCap"]

#TODO: Delete this excel output
# Write the conventional generators' schedules
    #XLSX.openxlsx(".\\OOutputs\\GenOutputs.xlsx", mode="w") do xf
    XLSX.openxlsx(".\\OOutputs\\FUCR_GenOutputs.xlsx", mode="rw") do xf
        sheet = xf[1]
        #XLSX.rename!(sheet, "new_sheet")
        #sheet["A1:I1"] = ["Hour" "GeneratorID" "VariableCost" "MinPowerOut" "MaxPowerOut" "Output" "On/off" "ShutDown" "Startup"]
        for t in 1:N_Hrs_FUCR, g=1:N_Gens
            cell_n = ((day-1)*(N_Hrs_FUCR*N_Gens))+((t-1)*N_Gens)+g+1
        # In the above line, we should also make  usre +1 is only applied to the first day so the results are not printed on labels
            sheet[XLSX.CellRef(cell_n,1)] = day
            sheet[XLSX.CellRef(cell_n,2)] = t+INITIAL_HR_FUCR
            sheet[XLSX.CellRef(cell_n,3)] = g
            #sheet[XLSX.CellRef(cell_n,4)] = DF_Generators.VariableCost[g]
            sheet[XLSX.CellRef(cell_n,5)] = DF_Generators.MinPowerOut[g]
            sheet[XLSX.CellRef(cell_n,6)] = DF_Generators.MaxPowerOut[g]
            sheet[XLSX.CellRef(cell_n,7)] = JuMP.value.(FUCR_genOut[g,t])
            sheet[XLSX.CellRef(cell_n,8)] = JuMP.value.(FUCR_genOnOff[g,t])
            sheet[XLSX.CellRef(cell_n,9)] = JuMP.value.(FUCR_genShutDown[g,t])
            sheet[XLSX.CellRef(cell_n,10)] = JuMP.value.(FUCR_genStartUp[g,t])
        end # ends the loop
    end # ends "do"

    if day == 1
        open(".//OOutputs//csv//FUCR_GenOutputs.csv", FILE_ACCESS_OVER) do io
            writedlm(io, permutedims(FUCR_GenOutputs_header), ',')
            for t in 1:N_Hrs_FUCR, g=1:N_Gens
                writedlm(io, hcat(day, t + INITIAL_HR_FUCR, g,
                    DF_Generators.MinPowerOut[g], DF_Generators.MaxPowerOut[g],
                    JuMP.value.(FUCR_genOut[g,t]),JuMP.value.(FUCR_genOnOff[g,t]),
                    JuMP.value.(FUCR_genShutDown[g,t]), JuMP.value.(FUCR_genStartUp[g,t]) ), ',')
            end # ends the loop
        end; # closes file
    end # end if

    if day > 1
        open(".//OOutputs//csv//FUCR_GenOutputs.csv", FILE_ACCESS_APPEND) do io
            for t in 1:N_Hrs_FUCR, g=1:N_Gens
                writedlm(io, hcat(day, t + INITIAL_HR_FUCR, g,
                    DF_Generators.MinPowerOut[g], DF_Generators.MaxPowerOut[g],
                    JuMP.value.(FUCR_genOut[g,t]),JuMP.value.(FUCR_genOnOff[g,t]),
                    JuMP.value.(FUCR_genShutDown[g,t]), JuMP.value.(FUCR_genStartUp[g,t]) ), ',')
            end # ends the loop
        end; # closes file
    end


#TODO: Delete this Excel output
# Writing storage units' optimal schedules into spreadsheets
    #XLSX.openxlsx(".\\OOutputs\\StorageOutputs.xlsx", mode="w") do xf
    XLSX.openxlsx(".\\OOutputs\\FUCR_StorageOutputs.xlsx", mode="rw") do xf
        sheet = xf[1]
        #XLSX.rename!(sheet, "new_sheet")
        for t in 1:N_Hrs_FUCR, p=1:N_StorgUs
            cell_n = ((day-1)*(N_Hrs_FUCR*N_StorgUs))+((t-1)*N_StorgUs)+p+1
            # In the above line, we should also make  usre +1 is only applied to the first day so the results are not printed on labels
            sheet[XLSX.CellRef(cell_n,1)] = day
            sheet[XLSX.CellRef(cell_n,2)] =  t+INITIAL_HR_FUCR
            sheet[XLSX.CellRef(cell_n,3)] = p
            sheet[XLSX.CellRef(cell_n,4)] = DF_Storage.Power[p]
            sheet[XLSX.CellRef(cell_n,5)] = DF_Storage.Power[p]/DF_Storage.PowerToEnergRatio[p]
            sheet[XLSX.CellRef(cell_n,6)] = JuMP.value.(FUCR_storgChrg[p,t])
            sheet[XLSX.CellRef(cell_n,7)] = JuMP.value.(FUCR_storgDisc[p,t])
            sheet[XLSX.CellRef(cell_n,8)] = JuMP.value.(FUCR_storgIdle[p,t])
            sheet[XLSX.CellRef(cell_n,9)] = JuMP.value.(FUCR_storgChrgPwr[p,t])
            sheet[XLSX.CellRef(cell_n,10)] = JuMP.value.(FUCR_storgDiscPwr[p,t])
            sheet[XLSX.CellRef(cell_n,11)] = JuMP.value.(FUCR_storgSOC[p,t])
            sheet[XLSX.CellRef(cell_n,12)] = JuMP.value.(FUCR_storgResUp[p,t])
            sheet[XLSX.CellRef(cell_n,13)] = JuMP.value.(FUCR_storgResDn[p,t])
        end # ends the loop
    end # ends "do"


    if day == 1
            open(".//OOutputs//csv//FUCR_StorageOutputs.csv", FILE_ACCESS_OVER) do io
                writedlm(io, permutedims(FUCR_StorageOutputs_header), ',')
                for t in 1:N_Hrs_FUCR, p=1:N_StorgUs
    				writedlm(io, hcat(day, t+INITIAL_HR_FUCR, p, DF_Storage.Power[p], DF_Storage.Power[p]/DF_Storage.PowerToEnergRatio[p],
    					JuMP.value.(FUCR_storgChrg[p,t]), JuMP.value.(FUCR_storgDisc[p,t]), JuMP.value.(FUCR_storgIdle[p,t]),
    					JuMP.value.(FUCR_storgChrgPwr[p,t]), JuMP.value.(FUCR_storgDiscPwr[p,t]), JuMP.value.(FUCR_storgSOC[p,t]),
    					JuMP.value.(FUCR_storgResUp[p,t]), JuMP.value.(FUCR_storgResDn[p,t]) ), ',')
                end # ends the loop
            end; # closes file
        end # end if

        if day > 1
            open(".//OOutputs//csv//FUCR_StorageOutputs.csv", FILE_ACCESS_APPEND) do io
                for t in 1:N_Hrs_FUCR, p=1:N_StorgUs
    				writedlm(io, hcat(day, t+INITIAL_HR_FUCR, p, DF_Storage.Power[p], DF_Storage.Power[p]/DF_Storage.PowerToEnergRatio[p],
    					JuMP.value.(FUCR_storgChrg[p,t]), JuMP.value.(FUCR_storgDisc[p,t]), JuMP.value.(FUCR_storgIdle[p,t]),
    					JuMP.value.(FUCR_storgChrgPwr[p,t]), JuMP.value.(FUCR_storgDiscPwr[p,t]), JuMP.value.(FUCR_storgSOC[p,t]),
    					JuMP.value.(FUCR_storgResUp[p,t]), JuMP.value.(FUCR_storgResDn[p,t]) ), ',')
                end # ends the loop
            end; # closes file
        end

# Writing the transmission flow schedules into spreadsheets
    #XLSX.openxlsx(".\\OOutputs\\TranFlowOutputs.xlsx", mode="w") do tf
    XLSX.openxlsx(".\\OOutputs\\FUCR_TranFlowOutputs.xlsx", mode="rw") do xf
        sheet = xf[1]
            #XLSX.rename!(sheet, "new_sheet")
        for t in 1:N_Hrs_FUCR, n=1:N_Zones, m=1:M_Zones
            cell_n = ((day-1)*(N_Hrs_FUCR*N_Zones*M_Zones))+((t-1)*N_Zones*M_Zones)+((n-1)*N_Zones)+m+1
            # In the above line, we should also make  usre +1 is only applied to the first day so the results are not printed on labels
            sheet[XLSX.CellRef(cell_n,1)] = day
            sheet[XLSX.CellRef(cell_n,2)] =  t+INITIAL_HR_FUCR
            sheet[XLSX.CellRef(cell_n,3)] = n
            sheet[XLSX.CellRef(cell_n,4)] = m
            sheet[XLSX.CellRef(cell_n,5)] = JuMP.value.(FUCR_powerFlow[n,m,t])
            sheet[XLSX.CellRef(cell_n,6)] = TranC[n,m]
        end # ends the loop
    end # ends "do"

    if day == 1
         open(".//OOutputs//csv//FUCR_TranFlowOutputs.csv", FILE_ACCESS_OVER) do io
             writedlm(io, permutedims(FUCR_TranFlowOutputs_header), ',')
             for t in 1:N_Hrs_FUCR, n=1:N_Zones, m=1:M_Zones
 				writedlm(io, hcat(day, t+INITIAL_HR_FUCR, n, m,
 				JuMP.value.(FUCR_powerFlow[n,m,t]), TranC[n,m] ), ',')
             end # ends the loop
         end; # closes file
     end # end if

     if day > 1
         open(".//OOutputs//csv//FUCR_TranFlowOutputs.csv", FILE_ACCESS_APPEND) do io
             for t in 1:N_Hrs_FUCR, n=1:N_Zones, m=1:M_Zones
 				writedlm(io, hcat(day, t+INITIAL_HR_FUCR, n, m,
 				JuMP.value.(FUCR_powerFlow[n,m,t]), TranC[n,m] ), ',')
             end # ends the loop
         end; # closes file
     end

###########################################################################
# Initilization of the next UC Run

##### When the BAUC is included,we don't need to update the initial commitment values at the end of FUCR
#### We can do this at the end of second BUCR that runs after SUCR
#### In fact, the first BUCR is initialized by the final outcomes of the second BUCR
# This must be updated later when we run two WAUCs every day and then RTUCs
#=        for g=1:N_Gens
            DF_Generators.StatusInit[g]=JuMP.value.(FUCR_genOnOff[g,INITIAL_HR_SUCR-INITIAL_HR_FUCR]);
            DF_Generators.PowerInit[g]=JuMP.value.(FUCR_genOut[g,INITIAL_HR_SUCR-INITIAL_HR_FUCR]);
        end
        for p=1:N_StorgUs
            DF_Storage.SOCInit[p]=JuMP.value.(FUCR_storgSOC[p,INITIAL_HR_SUCR-INITIAL_HR_FUCR]);
        end
=#
#***************************
# Create and save the following parameters to be passed to BUCR1
    for h=1:INITIAL_HR_SUCR-INITIAL_HR_FUCR
        for g=1:N_Gens
            global FUCRtoBUCR1_genOnOff[g,h]=JuMP.value.(FUCR_genOnOff[g,h]);
            global FUCRtoBUCR1_genOut[g,h]=JuMP.value.(FUCR_genOut[g,h]);
            global FUCRtoBUCR1_genStartUp[g,h]=JuMP.value.(FUCR_genStartUp[g,h]);
            global FUCRtoBUCR1_genShutDown[g,h]=JuMP.value.(FUCR_genShutDown[g,h]);
            for b=1:N_Blocks
                FUCRtoBUCR1_genOut_Block[g,b,h]=JuMP.value.(FUCR_genOut_Block[g,b,h]);
            end
        end
        for p=1:N_StorgUs
            global FUCRtoBUCR1_storgChrg[p,h]=JuMP.value.(FUCR_storgChrg[p,h]);
            global FUCRtoBUCR1_storgDisc[p,h]=JuMP.value.(FUCR_storgDisc[p,h]);
            global FUCRtoBUCR1_storgIdle[p,h]=JuMP.value.(FUCR_storgIdle[p,h]);
            global FUCRtoBUCR1_storgChrgPwr[p,h]=JuMP.value.(FUCR_storgChrgPwr[p,h]);
            global FUCRtoBUCR1_storgDiscPwr[p,h]=JuMP.value.(FUCR_storgDiscPwr[p,h]);
            global FUCRtoBUCR1_storgSOC[p,h]=JuMP.value.(FUCR_storgSOC[p,h]);
        end
    end
## This block models the Balancing Unit Commitment Runs between the morning and evening UC Runs
    for h=1:INITIAL_HR_SUCR-INITIAL_HR_FUCR # number of BUCR periods in between FUCR and SUCR
        # Pre-processing demand variables
        print("this period is hour: ", h)

        D_Rng_BUCR1 = ((day-1)*24)+INITIAL_HR_FUCR+h  # Bottom cell of the demand data needed for running the first WAUC run at 6 am with 7-day look-ahead horizon
        BUCR1_Hr_Demand = BUCR_Demands[D_Rng_BUCR1, :]
        BUCR1_Hr_SolarG = BUCR_SolarGs[D_Rng_BUCR1, :]
        BUCR1_Hr_WindG = BUCR_WindGs[D_Rng_BUCR1, :]
        BUCR1_Hr_HydroG = BUCR_HydroGs[D_Rng_BUCR1, :]

        # Preprocessing module that fixes the commitment of slow-start units to their FUCR's outcome and determines the binary commitment bounds for fast-start units dependent to their initial up/down time and minimum up/down time limits
        for g=1:N_Gens
            if DF_Generators.FastStart[g]==0 # if the units are slow their BAUC's commitment is fixed to their FUCR's schedule
                if FUCRtoBUCR1_genOnOff[g,h]==0
                    global BUCR1_Commit_LB[g] = 0;
                    global BUCR1_Commit_UB[g] = 0;
                else
                    global BUCR1_Commit_LB[g] = 1;
                    global BUCR1_Commit_UB[g] = 1;
                end
            else # if the units are fast their BAUC's commitment could be fixed to 0 or 1 or vary between 0 or 1 dependent to their initial up/down time and minimum up/down time
                if BUCR1_Init_DownTime[g]==0
                    if BUCR1_Init_UpTime[g]<DF_Generators.MinUpTime[g]
                        global BUCR1_Commit_LB[g] = 1;
                        global BUCR1_Commit_UB[g] = 1;
                    else
                        global BUCR1_Commit_LB[g] = 0;
                        global BUCR1_Commit_UB[g] = 1;
                    end
                elseif BUCR1_Init_DownTime[g]<DF_Generators.MinDownTime[g]
                    global BUCR1_Commit_LB[g] = 0;
                    global BUCR1_Commit_UB[g] = 0;
                else
                    global BUCR1_Commit_LB[g] = 0;
                    global BUCR1_Commit_UB[g] = 1;
                end
            end
        end #


        #BUCR1model=Model(with_optimizer(CPLEX.Optimizer))
        BUCR1model = direct_model(CPLEX.Optimizer())
        #set_optimizer_attribute(BUCR1model, "CPX_PARAM_EPINT", 1e-5)
        #set_optimizer_attribute(BUCR1model, "CPX_PARAM_EPINT", 0.2)
        #set_optimizer_attribute(BUCR1model, "CPX_PARAM_EPGAP", 0.00001)

        # Declaring the decision variables for conventional generators
        @variable(BUCR1model, BUCR1_genOnOff[1:N_Gens], Bin) #Bin
        @variable(BUCR1model, BUCR1_genStartUp[1:N_Gens], Bin) # startup variable
        @variable(BUCR1model, BUCR1_genShutDown[1:N_Gens], Bin) # shutdown variable
        @variable(BUCR1model, BUCR1_genOut[1:N_Gens]>=0) # Generator's output schedule
        @variable(BUCR1model, BUCR1_genOut_Block[1:N_Gens, 1:N_Blocks]>=0) # Generator's output schedule from each block (block rfers to IHR curve blocks/segments)

        #@variable(BUCR1model, BUCR1_genResUp[1:N_Gens]>=0) # Generators' up reserve schedule
        #@variable(BUCR1model, BUCR1_genResDn[1:N_Gens]>=0) # Generator's down rserve schedule

        # declaring decision variables for storage Units
        @variable(BUCR1model, BUCR1_storgChrg[1:N_StorgUs], Bin) #Bin variable equal to 1 if unit runs in the charging mode
        @variable(BUCR1model, BUCR1_storgDisc[1:N_StorgUs], Bin) #Bin variable equal to 1 if unit runs in the discharging mode
        @variable(BUCR1model, BUCR1_storgIdle[1:N_StorgUs], Bin) ##Bin variable equal to 1 if unit runs in the idle mode
        @variable(BUCR1model, BUCR1_storgChrgPwr[1:N_StorgUs]>=0) #Chargung power
        @variable(BUCR1model, BUCR1_storgDiscPwr[1:N_StorgUs]>=0) # Discharging Power
        @variable(BUCR1model, BUCR1_storgSOC[1:N_StorgUs]>=0) # state of charge (stored energy level for storage unit at time t)
        #@variable(BUCR1model, BUCR1_storgResUp[1:N_StorgUs]>=0) # Scheduled up reserve
        #@variable(BUCR1model, BUCR1_storgResDn[1:N_StorgUs]>=0) # Scheduled down reserve

        # declaring decision variables for renewable generation
        @variable(BUCR1model, BUCR1_solarG[1:N_Zones]>=0) # solar energy schedules
        @variable(BUCR1model, BUCR1_windG[1:N_Zones]>=0) # wind energy schedules
        @variable(BUCR1model, BUCR1_hydroG[1:N_Zones]>=0) # hydro energy schedules
        @variable(BUCR1model, BUCR1_solarGSpil[1:N_Zones]>=0) # solar energy schedules
        @variable(BUCR1model, BUCR1_windGSpil[1:N_Zones]>=0) # wind energy schedules
        @variable(BUCR1model, BUCR1_hydroGSpil[1:N_Zones]>=0) # hydro energy schedules


        # declaring variables for transmission system
        @variable(BUCR1model, BUCR1_voltAngle[1:N_Zones]) #voltage angle at zone/bus n in t//
        @variable(BUCR1model, BUCR1_powerFlow[1:N_Zones, 1:M_Zones]) #transmission Flow from zone n to zone m//

        # Defining the objective function that minimizes the overal cost of supplying electricity (=total variable, no-load, startup, and shutdown costs)

        #@objective(BUCR1model, Min, sum(sum(DF_Generators.VariableCost[g]*BUCR1_genOut[g]+DF_Generators.NoLoadCost[g]*BUCR1_genOnOff[g] +DF_Generators.StartUpCost[g]*BUCR1_genStartUp[g] + DF_Generators.ShutdownCost[g]*BUCR1_genShutDown[g] for g in 1:N_Gens)))
        @objective(BUCR1model, Min, sum(sum(DF_Generators.IHRC_B1_HR[g]*FuelPrice[g,day]*(BUCR1_genOut_Block[g,1]-FUCRtoBUCR1_genOut_Block[g,1,h])
                                           +DF_Generators.IHRC_B2_HR[g]*FuelPrice[g,day]*(BUCR1_genOut_Block[g,2]-FUCRtoBUCR1_genOut_Block[g,2,h])
                                           +DF_Generators.IHRC_B3_HR[g]*FuelPrice[g,day]*(BUCR1_genOut_Block[g,3]-FUCRtoBUCR1_genOut_Block[g,3,h])
                                           +DF_Generators.IHRC_B4_HR[g]*FuelPrice[g,day]*(BUCR1_genOut_Block[g,4]-FUCRtoBUCR1_genOut_Block[g,4,h])
                                           +DF_Generators.IHRC_B5_HR[g]*FuelPrice[g,day]*(BUCR1_genOut_Block[g,5]-FUCRtoBUCR1_genOut_Block[g,5,h])
                                           +DF_Generators.IHRC_B6_HR[g]*FuelPrice[g,day]*(BUCR1_genOut_Block[g,6]-FUCRtoBUCR1_genOut_Block[g,6,h])
                                           +DF_Generators.IHRC_B7_HR[g]*FuelPrice[g,day]*(BUCR1_genOut_Block[g,7]-FUCRtoBUCR1_genOut_Block[g,7,h])
                                           +DF_Generators.NoLoadHR[g]*FuelPrice[g,day]*(BUCR1_genOnOff[g]-FUCRtoBUCR1_genOnOff[g,h]) +((DF_Generators.FixedSUCost[g]+(DF_Generators.StartUpHR[g]*FuelPrice[g,day]))*(BUCR1_genStartUp[g]-FUCRtoBUCR1_genStartUp[g,h]))
                                           +DF_Generators.ShutdownCost[g]*(BUCR1_genShutDown[g]-FUCRtoBUCR1_genShutDown[g,h]) for g in 1:N_Gens) for t in 1:N_Hrs_FUCR))

        # Constraints representing technical limits of conventional generators
        #Status transition trajectory of
        @constraint(BUCR1model, conStartUpAndDn[g=1:N_Gens], (BUCR1_genOnOff[g] - BUCR1_Init_genOnOff[g] - BUCR1_genStartUp[g] + BUCR1_genShutDown[g])==0)
        # Max Power generation limit in Block 1
        @constraint(BUCR1model, conMaxPowBlock1[g=1:N_Gens],  BUCR1_genOut_Block[g,1] <= DF_Generators.IHRC_B1_Q[g]*BUCR1_genOnOff[g] )
        # Max Power generation limit in Block 2
        @constraint(BUCR1model, conMaxPowBlock2[g=1:N_Gens],  BUCR1_genOut_Block[g,2] <= DF_Generators.IHRC_B2_Q[g]*BUCR1_genOnOff[g] )
        # Max Power generation limit in Block 3
        @constraint(BUCR1model, conMaxPowBlock3[g=1:N_Gens],  BUCR1_genOut_Block[g,3] <= DF_Generators.IHRC_B3_Q[g]*BUCR1_genOnOff[g] )
        # Max Power generation limit in Block 4
        @constraint(BUCR1model, conMaxPowBlock4[g=1:N_Gens],  BUCR1_genOut_Block[g,4] <= DF_Generators.IHRC_B4_Q[g]*BUCR1_genOnOff[g] )
        # Max Power generation limit in Block 5
        @constraint(BUCR1model, conMaxPowBlock5[g=1:N_Gens],  BUCR1_genOut_Block[g,5] <= DF_Generators.IHRC_B5_Q[g]*BUCR1_genOnOff[g] )
        # Max Power generation limit in Block 6
        @constraint(BUCR1model, conMaxPowBlock6[g=1:N_Gens],  BUCR1_genOut_Block[g,6] <= DF_Generators.IHRC_B6_Q[g]*BUCR1_genOnOff[g] )
        # Max Power generation limit in Block 7
        @constraint(BUCR1model, conMaxPowBlock7[g=1:N_Gens],  BUCR1_genOut_Block[g,7] <= DF_Generators.IHRC_B7_Q[g]*BUCR1_genOnOff[g] )
        # Total Production of each generation equals the sum of generation from its all blocks
        @constraint(BUCR1model, conTotalGen[g=1:N_Gens],  BUCR1_genOut[g] == sum(BUCR1_genOut_Block[g,b] for b=1:N_Blocks))
        #Max power generation limit
        @constraint(BUCR1model, conMaxPow[g=1:N_Gens],  BUCR1_genOut[g] <= DF_Generators.MaxPowerOut[g]*BUCR1_genOnOff[g])
        # Min power generation limit
        @constraint(BUCR1model, conMinPow[g=1:N_Gens],  BUCR1_genOut[g] >= DF_Generators.MinPowerOut[g]*BUCR1_genOnOff[g])

        #Up ramp rate limit
        @constraint(BUCR1model, conRampRateUp[g=1:N_Gens], (BUCR1_genOut[g] - BUCR1_Init_genOut[g] <=(DF_Generators.RampUpLimit[g]*BUCR1_Init_genOnOff[g]) + (DF_Generators.RampStartUpLimit[g]*BUCR1_genStartUp[g])))

        # Down ramp rate limit
        @constraint(BUCR1model, conRampRateDown[g=1:N_Gens], (BUCR1_Init_genOut[g] - BUCR1_genOut[g] <=(DF_Generators.RampDownLimit[g]*BUCR1_genOnOff[g]) + (DF_Generators.RampShutDownLimit[g]*BUCR1_genShutDown[g])))
        # Min Up Time limit with alternative formulation


        #The next twyo constraints enforce limits on binary commitment variables of slow and fast generators
        # scheduled slow units are forced to remain on, offline slow units remain off, and fast start units could change their commitment dependent on their MUT and MDT
        @constraint(BUCR1model, conCommitmentUB[g=1:N_Gens], (BUCR1_genOnOff[g] <= BUCR1_Commit_UB[g]))

        # if the generator is slow start and scheduled "on" in the FUCR,  is fixed by the following constraint
        @constraint(BUCR1model, conCommitmentLB[g=1:N_Gens], (BUCR1_genOnOff[g] >= BUCR1_Commit_LB[g]))

        # Renewable generation constraints
        @constraint(BUCR1model, conSolarLimit[n=1:N_Zones], BUCR1_solarG[n] + BUCR1_solarGSpil[n]<=BUCR1_Hr_SolarG[n])
        @constraint(BUCR1model, conWindLimit[n=1:N_Zones], BUCR1_windG[n] + BUCR1_windGSpil[n]<=BUCR1_Hr_WindG[n])
        @constraint(BUCR1model, conHydroLimit[n=1:N_Zones], BUCR1_hydroG[n] + BUCR1_hydroGSpil[n]<=BUCR1_Hr_HydroG[n])

        # Constraints representing technical characteristics of storage units
        # the next three constraints fix the balancing charging/discharging/Idle status to their optimal outcomes as determined by FUCR
        @constraint(BUCR1model, conStorgChrgStatusFixed[p=1:N_StorgUs], (BUCR1_storgChrg[p]==FUCRtoBUCR1_storgChrg[p,h]))
        @constraint(BUCR1model, conStorgDisChrgStatusFixed[p=1:N_StorgUs], (BUCR1_storgDisc[p]==FUCRtoBUCR1_storgDisc[p,h]))
        @constraint(BUCR1model, conStorgIdleStatusFixed[p=1:N_StorgUs], (BUCR1_storgIdle[p]==FUCRtoBUCR1_storgIdle[p,h]))

        # charging power limit
        @constraint(BUCR1model, conStrgChargPowerLimit[p=1:N_StorgUs], (BUCR1_storgChrgPwr[p])<=DF_Storage.Power[p]*BUCR1_storgChrg[p])
        # Discharging power limit
        @constraint(BUCR1model, conStrgDisChgPowerLimit[p=1:N_StorgUs], (BUCR1_storgDiscPwr[p])<=DF_Storage.Power[p]*BUCR1_storgDisc[p])
        # State of charge at t
        @constraint(BUCR1model, conStorgSOC[p=1:N_StorgUs], BUCR1_storgSOC[p]==BUCR1_Init_storgSOC[p]-(BUCR1_storgDiscPwr[p]/DF_Storage.TripEfficDown[p])+(BUCR1_storgChrgPwr[p]*DF_Storage.TripEfficUp[p])-(BUCR1_storgSOC[p]*DF_Storage.SelfDischarge[p]))
        # minimum energy limit
        @constraint(BUCR1model, conMinEnrgStorgLimi[p=1:N_StorgUs], BUCR1_storgSOC[p]>=0)
        # Maximum energy limit
        @constraint(BUCR1model, conMaxEnrgStorgLimi[p=1:N_StorgUs], BUCR1_storgSOC[p]<=(DF_Storage.Power[p]/DF_Storage.PowerToEnergRatio[p]))


        # Constraints representing transmission grid capacity constraints
        # DC Power Flow Calculation
        @constraint(BUCR1model, conDCPowerFlowPos[n=1:N_Zones, m=1:N_Zones], BUCR1_powerFlow[n,m]-(TranS[n,m]*(BUCR1_voltAngle[n]-BUCR1_voltAngle[m])) ==0)
        @constraint(BUCR1model, conDCPowerFlowNeg[n=1:N_Zones, m=1:N_Zones], BUCR1_powerFlow[n,m]+BUCR1_powerFlow[m,n]==0)
        # Tranmission flow bounds (from n to m and from m to n)
        #    @constraint(BUCR1model, conPosFlowLimit[t=1:N_Hrs_BUCR, n=1:N_Zones, m=1:N_Zones], powerFlow[n,m,t]<=TranC[n,m])
        #    @constraint(BUCR1model, conNegFlowLimit[t=1:N_Hrs_BUCR, n=1:N_Zones, m=1:N_Zones], powerFlow[m,n,t]>=-TranC[n,m])
        # Voltage Angle bounds and reference point
        @constraint(BUCR1model, conVoltAnglUB[n=1:N_Zones], BUCR1_voltAngle[n]<=π)
        @constraint(BUCR1model, conVoltAnglLB[n=1:N_Zones], BUCR1_voltAngle[n]>=-π)
        @constraint(BUCR1model, conVoltAngRef, BUCR1_voltAngle[1]==0)

        # System-wide Constraints
        #nodal balance constraint
        @constraint(BUCR1model, conNodBalanc[n=1:N_Zones], sum((BUCR1_genOut[g]*Map_Gens[g,n]) for g=1:N_Gens) + sum((BUCR1_storgDiscPwr[p]*Map_Storage[p,n]) for p=1:N_StorgUs) - sum((BUCR1_storgChrgPwr[p]*Map_Storage[p,n]) for p=1:N_StorgUs) +BUCR1_solarG[n] +BUCR1_windG[n] +BUCR1_hydroG[n] - BUCR1_Hr_Demand[n] == sum(BUCR1_powerFlow[n,m] for m=1:M_Zones))
        # Minimum up reserve requirement
        #    @constraint(BUCR1model, conMinUpReserveReq[t=1:N_Hrs_BUCR], sum(genResUp[g,t] for g=1:N_Gens) + sum(storgResUp[p,t] for p=1:N_StorgUs) >= Reserve_Req_Up[t] )

        # Minimum down reserve requirement
        #    @constraint(BUCR1model, conMinDnReserveReq[t=1:N_Hrs_BUCR], sum(genResDn[g,t] for g=1:N_Gens) + sum(storgResDn[p,t] for p=1:N_StorgUs) >= Reserve_Req_Dn[t] )

        # solve the First WAUC model (BUCR)
        JuMP.optimize!(BUCR1model)

        # Pricing general results in the terminal window
        println("Objective value: ", JuMP.objective_value(BUCR1model))

        println("------------------------------------")
        println("------- BAUC1 OBJECTIVE VALUE -------")
        println("Objective value for day", day, "and hour ", h+INITIAL_HR_FUCR,"is:", JuMP.objective_value(BUCR1model))
        println("------------------------------------")
        println("------- BAUC1 PRIMAL STATUS -------")
        println(primal_status(BUCR1model))
        println("------------------------------------")
        println("------- BAUC1 DUAL STATUS -------")
        println(JuMP.dual_status(BUCR1model))
        println("for Day:", day, " and hour ", h+INITIAL_HR_FUCR, ": solved")
        println("---------------------------")

#########################################################
# Write the optimal outcomes into spreadsheets###########
############# Later we need to include a variable for day so the cell number in which the results are printed is updated accordingly

        # Write the conventional generators' schedules
        #XLSX.openxlsx(".\\OOutputs\\GenOutputs.xlsx", mode="w") do xf
        XLSX.openxlsx(".\\OOutputs\\BUCR_GenOutputs.xlsx", mode="rw") do xf
            sheet = xf[1]
            #XLSX.rename!(sheet, "new_sheet")
            #sheet["A1:I1"] = ["Hour" "GeneratorID" "VariableCost" "MinPowerOut" "MaxPowerOut" "Output" "On/off" "ShutDown" "Startup"]
            for g=1:N_Gens
                cell_n = ((((day-1)*24)+INITIAL_HR_FUCR)*N_Gens)+((h-1)*N_Gens)+g+1
                # In the above line, we should also make  usre +1 is only applied to the first day so the results are not printed on labels
                sheet[XLSX.CellRef(cell_n,1)] = day
                sheet[XLSX.CellRef(cell_n,2)] = h+INITIAL_HR_FUCR
                sheet[XLSX.CellRef(cell_n,3)] = g
                #sheet[XLSX.CellRef(cell_n,4)] = DF_Generators.VariableCost[g]
                sheet[XLSX.CellRef(cell_n,5)] = DF_Generators.MinPowerOut[g]
                sheet[XLSX.CellRef(cell_n,6)] = DF_Generators.MaxPowerOut[g]
                sheet[XLSX.CellRef(cell_n,7)] = JuMP.value.(BUCR1_genOut[g])
                sheet[XLSX.CellRef(cell_n,8)] = JuMP.value.(BUCR1_genOnOff[g])
                sheet[XLSX.CellRef(cell_n,9)] = JuMP.value.(BUCR1_genShutDown[g])
                sheet[XLSX.CellRef(cell_n,10)] = JuMP.value.(BUCR1_genStartUp[g])
            end # ends the loop
        end # ends "do"

        if day == 1
            open(".//OOutputs//csv//BUCR_GenOutputs.csv", FILE_ACCESS_OVER) do io
                writedlm(io, permutedims(BUCR_GenOutputs_header), ',')
                for g=1:N_Gens
    				writedlm(io, hcat(day, h+INITIAL_HR_FUCR, g,
    						DF_Generators.MinPowerOut[g], DF_Generators.MaxPowerOut[g],
    						JuMP.value.(BUCR1_genOut[g]), JuMP.value.(BUCR1_genOnOff[g]),
    						JuMP.value.(BUCR1_genShutDown[g]), JuMP.value.(BUCR1_genStartUp[g]) ), ',')
                end # ends the loop
            end; # closes file
        end # end if

        if day > 1
            open(".//OOutputs//csv//BUCR_GenOutputs.csv", FILE_ACCESS_APPEND) do io
                for g=1:N_Gens
    				writedlm(io, hcat(day, h+INITIAL_HR_FUCR, g,
    						DF_Generators.MinPowerOut[g], DF_Generators.MaxPowerOut[g],
    						JuMP.value.(BUCR1_genOut[g]), JuMP.value.(BUCR1_genOnOff[g]),
    						JuMP.value.(BUCR1_genShutDown[g]), JuMP.value.(BUCR1_genStartUp[g]) ), ',')
                end # ends the loop
            end; # closes file
        end

        # Writing storage units' optimal schedules into spreadsheets
        #XLSX.openxlsx(".\\OOutputs\\StorageOutputs.xlsx", mode="w") do xf
        XLSX.openxlsx(".\\OOutputs\\BUCR_StorageOutputs.xlsx", mode="rw") do xf
            sheet = xf[1]
            #XLSX.rename!(sheet, "new_sheet")
            for p=1:N_StorgUs
                cell_n = ((((day-1)*24)+INITIAL_HR_FUCR)*N_StorgUs)+((h-1)*N_StorgUs)+p+1
                # In the above line, we should also make  usre +1 is only applied to the first day so the results are not printed on labels
                sheet[XLSX.CellRef(cell_n,1)] = day
                sheet[XLSX.CellRef(cell_n,2)] = h+INITIAL_HR_FUCR
                sheet[XLSX.CellRef(cell_n,3)] = p
                sheet[XLSX.CellRef(cell_n,4)] = DF_Storage.Power[p]
                sheet[XLSX.CellRef(cell_n,5)] = DF_Storage.Power[p]/DF_Storage.PowerToEnergRatio[p]
                sheet[XLSX.CellRef(cell_n,6)] = JuMP.value.(BUCR1_storgChrg[p])
                sheet[XLSX.CellRef(cell_n,7)] = JuMP.value.(BUCR1_storgDisc[p])
                sheet[XLSX.CellRef(cell_n,8)] = JuMP.value.(BUCR1_storgIdle[p])
                sheet[XLSX.CellRef(cell_n,9)] = JuMP.value.(BUCR1_storgChrgPwr[p])
                sheet[XLSX.CellRef(cell_n,10)] = JuMP.value.(BUCR1_storgDiscPwr[p])
                sheet[XLSX.CellRef(cell_n,11)] = JuMP.value.(BUCR1_storgSOC[p])
                #sheet[XLSX.CellRef(cell_n,12)] = JuMP.value.(BUCR1_storgResUp[p])
                #sheet[XLSX.CellRef(cell_n,13)] = JuMP.value.(BUCR1_storgResDn[p])
            end # ends the loop
        end # ends "do"

        if day == 1
            open(".//OOutputs//csv//BUCR_StorageOutputs.csv", FILE_ACCESS_OVER) do io
                writedlm(io, permutedims(BUCR_StorageOutputs_header), ',')
                for p=1:N_StorgUs
    				writedlm(io, hcat(day, h+INITIAL_HR_FUCR, p, DF_Storage.Power[p],
    						DF_Storage.Power[p]/DF_Storage.PowerToEnergRatio[p],
    						JuMP.value.(BUCR1_storgChrg[p]), JuMP.value.(BUCR1_storgDisc[p]),
    						JuMP.value.(BUCR1_storgIdle[p]), JuMP.value.(BUCR1_storgChrgPwr[p]),
    						JuMP.value.(BUCR1_storgDiscPwr[p]), JuMP.value.(BUCR1_storgSOC[p]) ), ',')
                end # ends the loop
            end; # closes file
        end # end if

        if day > 1
            open(".//OOutputs//csv//BUCR_StorageOutputs.csv", FILE_ACCESS_APPEND) do io
                for p=1:N_StorgUs
    				writedlm(io, hcat(day, h+INITIAL_HR_FUCR, p, DF_Storage.Power[p],
    						DF_Storage.Power[p]/DF_Storage.PowerToEnergRatio[p],
    						JuMP.value.(BUCR1_storgChrg[p]), JuMP.value.(BUCR1_storgDisc[p]),
    						JuMP.value.(BUCR1_storgIdle[p]), JuMP.value.(BUCR1_storgChrgPwr[p]),
    						JuMP.value.(BUCR1_storgDiscPwr[p]), JuMP.value.(BUCR1_storgSOC[p]) ), ',')
                end # ends the loop
            end; # closes file
        end


        # Writeing the transmission flow schedules into spreadsheets
        #XLSX.openxlsx(".\\OOutputs\\TranFlowOutputs.xlsx", mode="w") do tf
        XLSX.openxlsx(".\\OOutputs\\BUCR_TranFlowOutputs.xlsx", mode="rw") do xf
            sheet = xf[1]
                #XLSX.rename!(sheet, "new_sheet")
                for n=1:N_Zones, m=1:M_Zones
                    cell_n = ((((day-1)*24)+INITIAL_HR_FUCR)*N_Zones*M_Zones)+((h-1)*N_Zones*M_Zones)+m+1
                    # In the above line, we should also make  usre +1 is only applied to the first day so the results are not printed on labels
                    sheet[XLSX.CellRef(cell_n,1)] = day
                    sheet[XLSX.CellRef(cell_n,2)] =  h+INITIAL_HR_FUCR
                    sheet[XLSX.CellRef(cell_n,3)] = n
                    sheet[XLSX.CellRef(cell_n,4)] = m
                    sheet[XLSX.CellRef(cell_n,5)] = JuMP.value.(BUCR1_powerFlow[n,m])
                sheet[XLSX.CellRef(cell_n,6)] = TranC[n,m]
            end # ends the loop
        end # ends "do"

        if day == 1
            open(".//OOutputs//csv//BUCR_TranFlowOutputs.csv", FILE_ACCESS_OVER) do io
                writedlm(io, permutedims(BUCR_TranFlowOutputs_header), ',')
                for n=1:N_Zones, m=1:M_Zones
    				writedlm(io, hcat(day, h+INITIAL_HR_FUCR, n, m,
    						JuMP.value.(BUCR1_powerFlow[n,m]), TranC[n,m] ), ',')
                end # ends the loop
            end; # closes file
        end # end if

        if day > 1
            open(".//OOutputs//csv//BUCR_TranFlowOutputs.csv", FILE_ACCESS_APPEND) do io
                for n=1:N_Zones, m=1:M_Zones
    				writedlm(io, hcat(day, h+INITIAL_HR_FUCR, n, m,
    						JuMP.value.(BUCR1_powerFlow[n,m]), TranC[n,m] ), ',')
                end # ends the loop
            end; # closes file
        end

##
    # Initilization of the next UC Run
    # This must be updated later when we run two WAUCs every day and then RTUCs
    # Setting initial values for BUCR1 (next hour), SUCR1, and BUCR2
        for g=1:N_Gens
            global BUCR1_Init_genOnOff[g] = JuMP.value.(BUCR1_genOnOff[g]);
            global BUCR1_Init_genOut[g] = JuMP.value.(BUCR1_genOut[g]);
            if h==(INITIAL_HR_SUCR-INITIAL_HR_FUCR)
                global BUCR2_Init_genOnOff[g] = JuMP.value.(BUCR1_genOnOff[g]);
                global BUCR2_Init_genOut[g] = JuMP.value.(BUCR1_genOut[g]);
                global SUCR_Init_genOnOff[g] = JuMP.value.(BUCR1_genOnOff[g]);
                global SUCR_Init_genOut[g] = JuMP.value.(BUCR1_genOut[g]);
            end
        end
        for p=1:N_StorgUs
            BUCR1_Init_storgSOC[p]=JuMP.value.(BUCR1_storgSOC[p]);
            if h==(INITIAL_HR_SUCR-INITIAL_HR_FUCR)
                global BUCR2_Init_storgSOC[p] = JuMP.value.(BUCR1_storgSOC[p]);
                global SUCR_Init_storgSOC[p] = JuMP.value.(BUCR1_storgSOC[p]);
            end
        end

        for g=1:N_Gens
            if (JuMP.value.(BUCR1_genStartUp[g]))==1
                global BUCR1_Init_UpTime[g]= 1;
                global BUCR1_Init_DownTime[g] = 0;
            elseif (JuMP.value.(BUCR1_genShutDown[g]))==1
                global BUCR1_Init_UpTime[g]= 0;
                global BUCR1_Init_DownTime[g]= 1;
            else
                if (JuMP.value.(BUCR1_genOnOff[g]))==1
                    global BUCR1_Init_UpTime[g]= BUCR1_Init_UpTime[g]+1;
                    global BUCR1_Init_DownTime[g]= 0;
                else
                    global BUCR1_Init_UpTime[g]= 0;
                    global BUCR1_Init_DownTime[g]= BUCR1_Init_DownTime[g]+1;
                end
            end
            if h==(INITIAL_HR_SUCR-INITIAL_HR_FUCR)
                global BUCR2_Init_UpTime[g]= BUCR1_Init_UpTime[g];
                global BUCR2_Init_DownTime[g]= BUCR1_Init_DownTime[g];
                global SUCR_Init_UpTime[g]= BUCR1_Init_UpTime[g];
                global SUCR_Init_DownTime[g]= BUCR1_Init_DownTime[g];
            end
        end

    end # ends the loop that runs hourly BUCR1 between [INITIAL_HR_FUCR and INITIAL_HR_SUCR)

## This block models the second UC optimization that is run in the evening
    #SUCRmodel=Model(with_optimizer(CPLEX.Optimizer))
    SUCRmodel = direct_model(CPLEX.Optimizer())
    #set_optimizer_attribute(SUCRmodel, "CPX_PARAM_EPINT", 1e-5)
    #set_optimizer_attribute(SUCRmodel, "CPX_PARAM_EPINT", 0.2)
    set_optimizer_attribute(SUCRmodel, "CPX_PARAM_EPGAP", 0.00001)

# Declaring the decision variables for conventional generators
    @variable(SUCRmodel, SUCR_genOnOff[1:N_Gens, 0:N_Hrs_SUCR], Bin) #Bin
    @variable(SUCRmodel, SUCR_genStartUp[1:N_Gens, 1:N_Hrs_SUCR], Bin) # startup variable
    @variable(SUCRmodel, SUCR_genShutDown[1:N_Gens, 1:N_Hrs_SUCR], Bin) # shutdown variable
    @variable(SUCRmodel, SUCR_genOut[1:N_Gens, 0:N_Hrs_SUCR]>=0) # Generator's output schedule
    @variable(SUCRmodel, SUCR_genOut_Block[1:N_Gens, 1:N_Blocks, 1:N_Hrs_SUCR]>=0) # Generator's output schedule from each block (block rfers to IHR curve blocks/segments)
    @variable(SUCRmodel, SUCR_genResUp[1:N_Gens, 1:N_Hrs_SUCR]>=0) # Generators' up reserve schedule
    @variable(SUCRmodel, SUCR_genResDn[1:N_Gens, 1:N_Hrs_SUCR]>=0) # Generator's down rserve schedule

# declaring decision variables for storage Units
    @variable(SUCRmodel, SUCR_storgChrg[1:N_StorgUs, 1:N_Hrs_SUCR], Bin) #Bin variable equal to 1 if unit runs in the charging mode
    @variable(SUCRmodel, SUCR_storgDisc[1:N_StorgUs, 1:N_Hrs_SUCR], Bin) #Bin variable equal to 1 if unit runs in the discharging mode
    @variable(SUCRmodel, SUCR_storgIdle[1:N_StorgUs, 1:N_Hrs_SUCR], Bin) ##Bin variable equal to 1 if unit runs in the idle mode
    @variable(SUCRmodel, SUCR_storgChrgPwr[1:N_StorgUs, 0:N_Hrs_SUCR]>=0) #Chargung power
    @variable(SUCRmodel, SUCR_storgDiscPwr[1:N_StorgUs, 0:N_Hrs_SUCR]>=0) # Discharging Power
    @variable(SUCRmodel, SUCR_storgSOC[1:N_StorgUs, 0:N_Hrs_SUCR]>=0) # state of charge (stored energy level for storage unit at time t)
    @variable(SUCRmodel, SUCR_storgResUp[1:N_StorgUs, 0:N_Hrs_SUCR]>=0) # Scheduled up reserve
    @variable(SUCRmodel, SUCR_storgResDn[1:N_StorgUs, 0:N_Hrs_SUCR]>=0) # Scheduled down reserve

    # declaring decision variables for renewable generation
    @variable(SUCRmodel, SUCR_solarG[1:N_Zones, 1:N_Hrs_SUCR]>=0) # solar energy schedules
    @variable(SUCRmodel, SUCR_windG[1:N_Zones, 1:N_Hrs_SUCR]>=0) # wind energy schedules
    @variable(SUCRmodel, SUCR_hydroG[1:N_Zones, 1:N_Hrs_SUCR]>=0) # hydro energy schedules
    @variable(SUCRmodel, SUCR_solarGSpil[1:N_Zones, 1:N_Hrs_SUCR]>=0) # solar energy schedules
    @variable(SUCRmodel, SUCR_windGSpil[1:N_Zones, 1:N_Hrs_SUCR]>=0) # wind energy schedules
    @variable(SUCRmodel, SUCR_hydroGSpil[1:N_Zones, 1:N_Hrs_SUCR]>=0) # hydro energy schedules

# declaring variables for transmission system
    @variable(SUCRmodel, SUCR_voltAngle[1:N_Zones, 1:N_Hrs_SUCR]) #voltage angle at zone/bus n in t//
    @variable(SUCRmodel, SUCR_powerFlow[1:N_Zones, 1:M_Zones, 1:N_Hrs_SUCR]) #transmission Flow from zone n to zone m//

# Defining the objective function that minimizes the overal cost of supplying electricity (=total variable, no-load, startup, and shutdown costs)

    @objective(SUCRmodel, Min, sum(sum(DF_Generators.IHRC_B1_HR[g]*FuelPrice[g,day]*SUCR_genOut_Block[g,1,t]
                                                   +DF_Generators.IHRC_B2_HR[g]*FuelPrice[g,day]*SUCR_genOut_Block[g,2,t]
                                                   +DF_Generators.IHRC_B3_HR[g]*FuelPrice[g,day]*SUCR_genOut_Block[g,3,t]
                                                   +DF_Generators.IHRC_B4_HR[g]*FuelPrice[g,day]*SUCR_genOut_Block[g,4,t]
                                                   +DF_Generators.IHRC_B5_HR[g]*FuelPrice[g,day]*SUCR_genOut_Block[g,5,t]
                                                   +DF_Generators.IHRC_B6_HR[g]*FuelPrice[g,day]*SUCR_genOut_Block[g,6,t]
                                                   +DF_Generators.IHRC_B7_HR[g]*FuelPrice[g,day]*SUCR_genOut_Block[g,7,t]
                                                   +DF_Generators.NoLoadHR[g]*FuelPrice[g,day]*SUCR_genOnOff[g,t] +((DF_Generators.FixedSUCost[g]+(DF_Generators.StartUpHR[g]*FuelPrice[g,day]))*SUCR_genStartUp[g,t])
                                                   +DF_Generators.ShutdownCost[g]*SUCR_genShutDown[g, t] for g in 1:N_Gens) for t in 1:N_Hrs_SUCR))


#Initialization of commitment and dispatch variables at t=0 (representing the last hour of previous scheduling horizon day=day-1 and t=24)
    @constraint(SUCRmodel, conInitGenOnOff[g=1:N_Gens], SUCR_genOnOff[g,0]==SUCR_Init_genOnOff[g]) # initial generation level for generator g at t=0
    @constraint(SUCRmodel, conInitGenOut[g=1:N_Gens], SUCR_genOut[g,0]==SUCR_Init_genOut[g]) # initial on/off status for generators g at t=0
    @constraint(SUCRmodel, conInitSOC[p=1:N_StorgUs], SUCR_storgSOC[p,0]==SUCR_Init_storgSOC[p]) # SOC for storage unit p at t=0

# Constraints representing technical limits of conventional generators
#Status transition trajectory of
    @constraint(SUCRmodel, conStartUpAndDn[t=1:N_Hrs_SUCR, g=1:N_Gens], (SUCR_genOnOff[g,t] - SUCR_genOnOff[g,t-1] - SUCR_genStartUp[g,t] + SUCR_genShutDown[g,t])==0)
# Max Power generation limit in Block 1
    @constraint(SUCRmodel, conMaxPowBlock1[t=1:N_Hrs_SUCR, g=1:N_Gens],  SUCR_genOut_Block[g,1,t] <= DF_Generators.IHRC_B1_Q[g]*SUCR_genOnOff[g,t] )
# Max Power generation limit in Block 2
    @constraint(SUCRmodel, conMaxPowBlock2[t=1:N_Hrs_SUCR, g=1:N_Gens],  SUCR_genOut_Block[g,2,t] <= DF_Generators.IHRC_B2_Q[g]*SUCR_genOnOff[g,t] )
# Max Power generation limit in Block 3
    @constraint(SUCRmodel, conMaxPowBlock3[t=1:N_Hrs_SUCR, g=1:N_Gens],  SUCR_genOut_Block[g,3,t] <= DF_Generators.IHRC_B3_Q[g]*SUCR_genOnOff[g,t] )
# Max Power generation limit in Block 4
    @constraint(SUCRmodel, conMaxPowBlock4[t=1:N_Hrs_SUCR, g=1:N_Gens],  SUCR_genOut_Block[g,4,t] <= DF_Generators.IHRC_B4_Q[g]*SUCR_genOnOff[g,t] )
# Max Power generation limit in Block 5
    @constraint(SUCRmodel, conMaxPowBlock5[t=1:N_Hrs_SUCR, g=1:N_Gens],  SUCR_genOut_Block[g,5,t] <= DF_Generators.IHRC_B5_Q[g]*SUCR_genOnOff[g,t] )
# Max Power generation limit in Block 6
    @constraint(SUCRmodel, conMaxPowBlock6[t=1:N_Hrs_SUCR, g=1:N_Gens],  SUCR_genOut_Block[g,6,t] <= DF_Generators.IHRC_B6_Q[g]*SUCR_genOnOff[g,t] )
# Max Power generation limit in Block 7
    @constraint(SUCRmodel, conMaxPowBlock7[t=1:N_Hrs_SUCR, g=1:N_Gens],  SUCR_genOut_Block[g,7,t] <= DF_Generators.IHRC_B7_Q[g]*SUCR_genOnOff[g,t] )
# Total Production of each generation equals the sum of generation from its all blocks
    @constraint(SUCRmodel, conTotalGen[t=1:N_Hrs_SUCR, g=1:N_Gens],  SUCR_genOut[g,t] == sum(SUCR_genOut_Block[g,b,t] for b=1:N_Blocks))

#Max power generation limit
    @constraint(SUCRmodel, conMaxPow[t=1:N_Hrs_SUCR, g=1:N_Gens],  SUCR_genOut[g,t]+SUCR_genResUp[g,t] <= DF_Generators.MaxPowerOut[g]*SUCR_genOnOff[g,t] )
# Min power generation limit
    @constraint(SUCRmodel, conMinPow[t=1:N_Hrs_SUCR, g=1:N_Gens],  SUCR_genOut[g,t]-SUCR_genResDn[g,t] >= DF_Generators.MinPowerOut[g]*SUCR_genOnOff[g,t] )
# Up reserve provision limit
    @constraint(SUCRmodel, conMaxResUp[t=1:N_Hrs_SUCR, g=1:N_Gens], SUCR_genResUp[g,t] <= DF_Generators.UpReserveLimit[g]*SUCR_genOnOff[g,t] )
#Down reserve provision limit
    @constraint(SUCRmodel, conMaxResDown[t=1:N_Hrs_SUCR, g=1:N_Gens],  SUCR_genResDn[g,t] <= DF_Generators.DownReserveLimit[g]*SUCR_genOnOff[g,t] )
#Up ramp rate limit
    @constraint(SUCRmodel, conRampRateUp[t=1:N_Hrs_SUCR, g=1:N_Gens], (SUCR_genOut[g,t] - SUCR_genOut[g,t-1] <=(DF_Generators.RampUpLimit[g]*SUCR_genOnOff[g, t-1]) + (DF_Generators.RampStartUpLimit[g]*SUCR_genStartUp[g,t])))
# Down ramp rate limit
    @constraint(SUCRmodel, conRampRateDown[t=1:N_Hrs_SUCR, g=1:N_Gens], (SUCR_genOut[g,t-1] - SUCR_genOut[g,t] <=(DF_Generators.RampDownLimit[g]*SUCR_genOnOff[g,t]) + (DF_Generators.RampShutDownLimit[g]*SUCR_genShutDown[g,t])))
# Min Up Time limit with alternative formulation
    @constraint(SUCRmodel, conUpTime[t=1:N_Hrs_SUCR, g=1:N_Gens], (sum(SUCR_genStartUp[g,k] for k=lb_MUT[g,t]:t)<=SUCR_genOnOff[g,t]))
# Min down Time limit with alternative formulation
    @constraint(SUCRmodel, conDownTime[t=1:N_Hrs_SUCR, g=1:N_Gens], (1-sum(SUCR_genShutDown[g,i] for i=lb_MDT[g,t]:t)>=SUCR_genOnOff[g,t]))

    # Renewable generation constraints
    @constraint(SUCRmodel, conSolarLimit[t=1:N_Hrs_SUCR, n=1:N_Zones], SUCR_solarG[n, t] + SUCR_solarGSpil[n,t]<=SUCR_WA_SolarG[t,n])
    @constraint(SUCRmodel, conWindLimit[t=1:N_Hrs_SUCR, n=1:N_Zones], SUCR_windG[n, t] + SUCR_windGSpil[n,t]<=SUCR_WA_WindG[t,n])
    @constraint(SUCRmodel, conHydroLimit[t=1:N_Hrs_SUCR, n=1:N_Zones], SUCR_hydroG[n, t] + SUCR_hydroGSpil[n,t]<=SUCR_WA_HydroG[t,n])
#

# Constraints representing technical characteristics of storage units
# status transition of storage units between charging, discharging, and idle modes
    @constraint(SUCRmodel, conStorgStatusTransition[t=1:N_Hrs_SUCR, p=1:N_StorgUs], (SUCR_storgChrg[p,t]+SUCR_storgDisc[p,t]+SUCR_storgIdle[p,t])==1)
# charging power limit
    @constraint(SUCRmodel, conStrgChargPowerLimit[t=1:N_Hrs_SUCR, p=1:N_StorgUs], (SUCR_storgChrgPwr[p,t] - SUCR_storgResDn[p,t])<=DF_Storage.Power[p]*SUCR_storgChrg[p,t])
# Discharging power limit
    @constraint(SUCRmodel, conStrgDisChgPowerLimit[t=1:N_Hrs_SUCR, p=1:N_StorgUs], (SUCR_storgDiscPwr[p,t] + SUCR_storgResUp[p,t])<=DF_Storage.Power[p]*SUCR_storgDisc[p,t])
# Down reserve provision limit
    @constraint(SUCRmodel, conStrgDownResrvMax[t=1:N_Hrs_SUCR, p=1:N_StorgUs], SUCR_storgResDn[p,t]<=DF_Storage.Power[p]*SUCR_storgChrg[p,t])
# Up reserve provision limit`
    @constraint(SUCRmodel, conStrgUpResrvMax[t=1:N_Hrs_SUCR, p=1:N_StorgUs], SUCR_storgResUp[p,t]<=DF_Storage.Power[p]*SUCR_storgDisc[p,t])
# State of charge at t
    @constraint(SUCRmodel, conStorgSOC[t=1:N_Hrs_SUCR, p=1:N_StorgUs], SUCR_storgSOC[p,t]==SUCR_storgSOC[p,t-1]-(SUCR_storgDiscPwr[p,t]/DF_Storage.TripEfficDown[p])+(SUCR_storgChrgPwr[p,t]*DF_Storage.TripEfficUp[p])-(SUCR_storgSOC[p,t]*DF_Storage.SelfDischarge[p]))
# minimum energy limit
    @constraint(SUCRmodel, conMinEnrgStorgLimi[t=1:N_Hrs_SUCR, p=1:N_StorgUs], SUCR_storgSOC[p,t]-(SUCR_storgResUp[p,t]/DF_Storage.TripEfficDown[p])+(SUCR_storgResDn[p,t]/DF_Storage.TripEfficUp[p])>=0)
# Maximum energy limit
    @constraint(SUCRmodel, conMaxEnrgStorgLimi[t=1:N_Hrs_SUCR, p=1:N_StorgUs], SUCR_storgSOC[p,t]-(SUCR_storgResUp[p,t]/DF_Storage.TripEfficDown[p])+(SUCR_storgResDn[p,t]/DF_Storage.TripEfficUp[p])<=(DF_Storage.Power[p]/DF_Storage.PowerToEnergRatio[p]))
# Constraints representing transmission grid capacity constraints
# DC Power Flow Calculation
    @constraint(SUCRmodel, conDCPowerFlowPos[t=1:N_Hrs_SUCR, n=1:N_Zones, m=1:N_Zones], SUCR_powerFlow[n,m,t]-(TranS[n,m]*(SUCR_voltAngle[n,t]-SUCR_voltAngle[m,t])) ==0)
    @constraint(SUCRmodel, conDCPowerFlowNeg[t=1:N_Hrs_SUCR, n=1:N_Zones, m=1:N_Zones], SUCR_powerFlow[n,m,t]+SUCR_powerFlow[m,n,t]==0)
# Tranmission flow bounds (from n to m and from m to n)
#    @constraint(SUCRmodel, conPosFlowLimit[t=1:N_Hrs_SUCR, n=1:N_Zones, m=1:N_Zones], powerFlow[n,m,t]<=TranC[n,m])
#    @constraint(SUCRmodel, conNegFlowLimit[t=1:N_Hrs_SUCR, n=1:N_Zones, m=1:N_Zones], powerFlow[m,n,t]>=-TranC[n,m])
# Voltage Angle bounds and reference point
    @constraint(SUCRmodel, conVoltAnglUB[t=1:N_Hrs_SUCR, n=1:N_Zones], SUCR_voltAngle[n,t]<=π)
    @constraint(SUCRmodel, conVoltAnglLB[t=1:N_Hrs_SUCR, n=1:N_Zones], SUCR_voltAngle[n,t]>=-π)
    @constraint(SUCRmodel, conVoltAngRef[t=1:N_Hrs_SUCR], SUCR_voltAngle[1,t]==0)

# System-wide Constraints
#nodal balance constraint
    @constraint(SUCRmodel, conNodBalanc[t=1:N_Hrs_SUCR, n=1:N_Zones], sum((SUCR_genOut[g,t]*Map_Gens[g,n]) for g=1:N_Gens) + sum((SUCR_storgDiscPwr[p,t]*Map_Storage[p,n]) for p=1:N_StorgUs) - sum((SUCR_storgChrgPwr[p,t]*Map_Storage[p,n]) for p=1:N_StorgUs) +SUCR_solarG[n, t] +SUCR_windG[n, t] +SUCR_hydroG[n, t] - SUCR_WA_Demand[t,n] == sum(SUCR_powerFlow[n,m,t] for m=1:M_Zones))

# Minimum zonal up reserve requirement, if there are more than two zones, we should  define reserve regions for DEC and DEP
#    @constraint(SUCRmodel, conMinUpReserveReq[t=1:N_Hrs_SUCR, n=1:N_Zones], sum((SUCR_genResUp[g,t]*Map_Gens[g,n]) for g=1:N_Gens) + sum((SUCR_storgResUp[p,t]*Map_Storage[p,n]) for p=1:N_StorgUs) >= Reserve_Req_Up[n] )

# Minimum down reserve requirement
#    @constraint(SUCRmodel, conMinDnReserveReq[t=1:N_Hrs_SUCR], sum(genResDn[g,t] for g=1:N_Gens) + sum(storgResDn[p,t] for p=1:N_StorgUs) >= Reserve_Req_Dn[t] )

# solve the First WAUC model (SUCR)
    JuMP.optimize!(SUCRmodel)

# Pricing general results in the terminal window
    println("Objective value: ", JuMP.objective_value(SUCRmodel))

    println("------------------------------------")
    println("------- SURC OBJECTIVE VALUE -------")
    println("Objective value for day", day, ":", JuMP.objective_value(SUCRmodel))
    println("------------------------------------")
    println("------- SURC PRIMAL STATUS -------")
    println(primal_status(SUCRmodel))
    println("------------------------------------")
    println("------- SURC DUAL STATUS -------")
    println(JuMP.dual_status(SUCRmodel))
    println("Day:", day, ": solved")
    println("---------------------------")

#########################################################
# Write the optimal outcomes into spreadsheets###########
############# Later we need to include a variable for day so the cell number in which the results are printed is updated accordingly

# Write the conventional generators' schedules
    #XLSX.openxlsx(".\\OOutputs\\GenOutputs.xlsx", mode="w") do xf
    XLSX.openxlsx(".\\OOutputs\\SUCR_GenOutputs.xlsx", mode="rw") do xf
        sheet = xf[1]
        #XLSX.rename!(sheet, "new_sheet")
        #sheet["A1:I1"] = ["Hour" "GeneratorID" "VariableCost" "MinPowerOut" "MaxPowerOut" "Output" "On/off" "ShutDown" "Startup"]
        for t in 1:N_Hrs_SUCR, g=1:N_Gens
            cell_n = ((day-1)*(N_Hrs_SUCR*N_Gens))+((t-1)*N_Gens)+g+1
        # In the above line, we should also make  usre +1 is only applied to the first day so the results are not printed on labels
            sheet[XLSX.CellRef(cell_n,1)] = day
            sheet[XLSX.CellRef(cell_n,2)] = t+INITIAL_HR_SUCR
            sheet[XLSX.CellRef(cell_n,3)] = g
            #sheet[XLSX.CellRef(cell_n,4)] = DF_Generators.VariableCost[g]
            sheet[XLSX.CellRef(cell_n,5)] = DF_Generators.MinPowerOut[g]
            sheet[XLSX.CellRef(cell_n,6)] = DF_Generators.MaxPowerOut[g]
            sheet[XLSX.CellRef(cell_n,7)] = JuMP.value.(SUCR_genOut[g,t])
            sheet[XLSX.CellRef(cell_n,8)] = JuMP.value.(SUCR_genOnOff[g,t])
            sheet[XLSX.CellRef(cell_n,9)] = JuMP.value.(SUCR_genShutDown[g,t])
            sheet[XLSX.CellRef(cell_n,10)] = JuMP.value.(SUCR_genStartUp[g,t])
        end # ends the loop
    end # ends "do"

    if day == 1
         open(".//OOutputs//csv//SUCR_GenOutputs.csv", FILE_ACCESS_OVER) do io
             writedlm(io, permutedims(SUCR_GenOutputs_header), ',')
             for t in 1:N_Hrs_SUCR, g=1:N_Gens
 			 writedlm(io, hcat(day, t+INITIAL_HR_SUCR, g,
 					DF_Generators.MinPowerOut[g], DF_Generators.MaxPowerOut[g],
 					JuMP.value.(SUCR_genOut[g,t]), JuMP.value.(SUCR_genOnOff[g,t]),
 					JuMP.value.(SUCR_genShutDown[g,t]), JuMP.value.(SUCR_genStartUp[g,t]) ), ',')
             end # ends the loop
         end; # closes file
     end # end if

     if day > 1
         open(".//OOutputs//csv//SUCR_GenOutputs.csv", FILE_ACCESS_APPEND) do io
             for t in 1:N_Hrs_SUCR, g=1:N_Gens
 			 writedlm(io, hcat(day, t+INITIAL_HR_SUCR, g,
 					DF_Generators.MinPowerOut[g], DF_Generators.MaxPowerOut[g],
 					JuMP.value.(SUCR_genOut[g,t]), JuMP.value.(SUCR_genOnOff[g,t]),
 					JuMP.value.(SUCR_genShutDown[g,t]), JuMP.value.(SUCR_genStartUp[g,t]) ), ',')
             end # ends the loop
         end; # closes file
     end


# Writing storage units' optimal schedules into spreadsheets
    #XLSX.openxlsx(".\\OOutputs\\StorageOutputs.xlsx", mode="w") do xf
    XLSX.openxlsx(".\\OOutputs\\SUCR_StorageOutputs.xlsx", mode="rw") do xf
        sheet = xf[1]
        #XLSX.rename!(sheet, "new_sheet")
        for t in 1:N_Hrs_SUCR, p=1:N_StorgUs
            cell_n = ((day-1)*(N_Hrs_SUCR*N_StorgUs))+((t-1)*N_StorgUs)+p+1
            # In the above line, we should also make  usre +1 is only applied to the first day so the results are not printed on labels
            sheet[XLSX.CellRef(cell_n,1)] = day
            sheet[XLSX.CellRef(cell_n,2)] =  t+INITIAL_HR_SUCR
            sheet[XLSX.CellRef(cell_n,3)] = p
            sheet[XLSX.CellRef(cell_n,4)] = DF_Storage.Power[p]
            sheet[XLSX.CellRef(cell_n,5)] = DF_Storage.Power[p]/DF_Storage.PowerToEnergRatio[p]
            sheet[XLSX.CellRef(cell_n,6)] = JuMP.value.(SUCR_storgChrg[p,t])
            sheet[XLSX.CellRef(cell_n,7)] = JuMP.value.(SUCR_storgDisc[p,t])
            sheet[XLSX.CellRef(cell_n,8)] = JuMP.value.(SUCR_storgIdle[p,t])
            sheet[XLSX.CellRef(cell_n,9)] = JuMP.value.(SUCR_storgChrgPwr[p,t])
            sheet[XLSX.CellRef(cell_n,10)] = JuMP.value.(SUCR_storgDiscPwr[p,t])
            sheet[XLSX.CellRef(cell_n,11)] = JuMP.value.(SUCR_storgSOC[p,t])
            sheet[XLSX.CellRef(cell_n,12)] = JuMP.value.(SUCR_storgResUp[p,t])
            sheet[XLSX.CellRef(cell_n,13)] = JuMP.value.(SUCR_storgResDn[p,t])
        end # ends the loop
    end # ends "do"

    if day == 1
         open(".//OOutputs//csv//SUCR_StorageOutputs.csv", FILE_ACCESS_OVER) do io
             writedlm(io, permutedims(SUCR_StorageOutputs_header), ',')
             for t in 1:N_Hrs_SUCR, p=1:N_StorgUs
 				writedlm(io, hcat(day, t+INITIAL_HR_SUCR,p,DF_Storage.Power[p],
 						DF_Storage.Power[p]/DF_Storage.PowerToEnergRatio[p],
 						JuMP.value.(SUCR_storgChrg[p,t]), JuMP.value.(SUCR_storgDisc[p,t]),
 						JuMP.value.(SUCR_storgIdle[p,t]), JuMP.value.(SUCR_storgChrgPwr[p,t]),
 						JuMP.value.(SUCR_storgDiscPwr[p,t]), JuMP.value.(SUCR_storgSOC[p,t]),
 						JuMP.value.(SUCR_storgResUp[p,t]),JuMP.value.(SUCR_storgResDn[p,t]) ), ',')
             end # ends the loop
         end; # closes file
     end # end if

     if day > 1
         open(".//OOutputs//csv//SUCR_StorageOutputs.csv", FILE_ACCESS_APPEND) do io
             for t in 1:N_Hrs_SUCR, p=1:N_StorgUs
 				writedlm(io, hcat(day, t+INITIAL_HR_SUCR,p,DF_Storage.Power[p],
 						DF_Storage.Power[p]/DF_Storage.PowerToEnergRatio[p],
 						JuMP.value.(SUCR_storgChrg[p,t]), JuMP.value.(SUCR_storgDisc[p,t]),
 						JuMP.value.(SUCR_storgIdle[p,t]), JuMP.value.(SUCR_storgChrgPwr[p,t]),
 						JuMP.value.(SUCR_storgDiscPwr[p,t]), JuMP.value.(SUCR_storgSOC[p,t]),
 						JuMP.value.(SUCR_storgResUp[p,t]),JuMP.value.(SUCR_storgResDn[p,t]) ), ',')
             end # ends the loop
         end; # closes file
     end

# Writeing the transmission flow schedules into spreadsheets
    #XLSX.openxlsx(".\\OOutputs\\TranFlowOutputs.xlsx", mode="w") do tf
    XLSX.openxlsx(".\\OOutputs\\SUCR_TranFlowOutputs.xlsx", mode="rw") do xf
        sheet = xf[1]
            #XLSX.rename!(sheet, "new_sheet")
        for t in 1:N_Hrs_SUCR, n=1:N_Zones, m=1:M_Zones
            cell_n = ((day-1)*(N_Hrs_SUCR*N_Zones*M_Zones))+((t-1)*N_Zones*M_Zones)+((n-1)*N_Zones)+m+1
            # In the above line, we should also make  usre +1 is only applied to the first day so the results are not printed on labels
            sheet[XLSX.CellRef(cell_n,1)] = day
            sheet[XLSX.CellRef(cell_n,2)] =  t+INITIAL_HR_SUCR
            sheet[XLSX.CellRef(cell_n,3)] = n
            sheet[XLSX.CellRef(cell_n,4)] = m
            sheet[XLSX.CellRef(cell_n,5)] = JuMP.value.(SUCR_powerFlow[n,m,t])
            sheet[XLSX.CellRef(cell_n,6)] = TranC[n,m]
        end # ends the loop
    end # ends "do"

    if day == 1
         open(".//OOutputs//csv//SUCR_TranFlowOutputs.csv", FILE_ACCESS_OVER) do io
             writedlm(io, permutedims(SUCR_TranFlowOutputs_header), ',')
             for t in 1:N_Hrs_SUCR, n=1:N_Zones, m=1:M_Zones
 				writedlm(io, hcat(day, t+INITIAL_HR_SUCR, n, m,
 						JuMP.value.(SUCR_powerFlow[n,m,t]), TranC[n,m] ), ',')
             end # ends the loop
         end; # closes file
     end # end if

     if day > 1
         open(".//OOutputs//csv//SUCR_TranFlowOutputs.csv", FILE_ACCESS_APPEND) do io
             for t in 1:N_Hrs_SUCR, n=1:N_Zones, m=1:M_Zones
 				writedlm(io, hcat(day, t+INITIAL_HR_SUCR, n, m,
 						JuMP.value.(SUCR_powerFlow[n,m,t]), TranC[n,m] ), ',')
             end # ends the loop
         end; # closes file
     end

    # Create and save the following parameters, which are transeferred to BAUC2
        for h=1:24-INITIAL_HR_SUCR+INITIAL_HR_FUCR
            for g=1:N_Gens
                global SUCRtoBUCR2_genOnOff[g,h]=JuMP.value.(SUCR_genOnOff[g,h]);
                global SUCRtoBUCR2_genOut[g,h]=JuMP.value.(SUCR_genOut[g,h]);
                global SUCRtoBUCR2_genStartUp[g,h]=JuMP.value.(SUCR_genStartUp[g,h]);
                global SUCRtoBUCR2_genShutDown[g,h]=JuMP.value.(SUCR_genShutDown[g,h]);
                for b=1:N_Blocks
                    SUCRtoBUCR2_genOut_Block[g,b,h]=JuMP.value.(SUCR_genOut_Block[g,b,h]);
                end
            end
            for p=1:N_StorgUs
                global SUCRtoBUCR2_storgChrg[p,h]=JuMP.value.(SUCR_storgChrg[p,h]);
                global SUCRtoBUCR2_storgDisc[p,h]=JuMP.value.(SUCR_storgDisc[p,h]);
                global SUCRtoBUCR2_storgIdle[p,h]=JuMP.value.(SUCR_storgIdle[p,h]);
                global SUCRtoBUCR2_storgChrgPwr[p,h]=JuMP.value.(SUCR_storgChrgPwr[p,h]);
                global SUCRtoBUCR2_storgDiscPwr[p,h]=JuMP.value.(SUCR_storgDiscPwr[p,h]);
                global SUCRtoBUCR2_storgSOC[p,h]=JuMP.value.(SUCR_storgSOC[p,h]);
            end
        end

###########################################################################
# Initilization of the next UC Run
#=
    # This must be updated later when we run two WAUCs every day and then RTUCs
        for g=1:N_Gens
            DF_Generators.StatusInit[g]=JuMP.value.(SUCR_genOnOff[g,24-INITIAL_HR_SUCR+INITIAL_HR_FUCR]);
            DF_Generators.PowerInit[g]=JuMP.value.(SUCR_genOut[g,24-INITIAL_HR_SUCR+INITIAL_HR_FUCR]);
        end
        for p=1:N_StorgUs
            DF_Storage.SOCInit[p]=JuMP.value.(SUCR_storgSOC[p,24-INITIAL_HR_SUCR+INITIAL_HR_FUCR]);
        end
=#

## This block models the second Balancing Unit Commitment Run, which is for the time range between the morning and evening UC Runs
    for h=1:24-INITIAL_HR_SUCR+INITIAL_HR_FUCR # number of BUCR periods in between FUCR and SUCR
        if h==24-INITIAL_HR_SUCR+INITIAL_HR_FUCR
            println("this period is hour: ", h)
        end

        # Preprocessing the demand data
        D_Rng_BUCR2 = ((day-1)*24)+INITIAL_HR_SUCR+h  # cell of the demand data needed for running the first WAUC run at 6 am with 7-day look-ahead horizon
        BUCR2_Hr_Demand = BUCR_Demands[D_Rng_BUCR2, :]
        BUCR2_Hr_SolarG = BUCR_SolarGs[D_Rng_BUCR2, :]
        BUCR2_Hr_WindG = BUCR_WindGs[D_Rng_BUCR2, :]
        BUCR2_Hr_HydroG = BUCR_HydroGs[D_Rng_BUCR2, :]

        # Preprocessing module that fixes the commitment of slow-start units to their FUCR's outcome and determines the binary commitment bounds for fast-start units dependent to their initial up/down time and minimum up/down time limits
        for g=1:N_Gens
            if DF_Generators.FastStart[g]==0 # if the units are slow their BAUC's commitment is fixed to their FUCR's schedule
                if SUCRtoBUCR2_genOnOff[g,h]==0
                    global BUCR2_Commit_LB[g] = 0;
                    global BUCR2_Commit_UB[g] = 0;
                else
                    global BUCR2_Commit_LB[g] = 1;
                    global BUCR2_Commit_UB[g] = 1;
                end
            else # if the units are fast their BAUC's commitment could be fixed to 0 or 1 or vary between 0 or 1 dependent to their initial up/down time and minimum up/down time
                if BUCR2_Init_DownTime[g]==0
                    if BUCR2_Init_UpTime[g]<DF_Generators.MinUpTime[g]
                        global BUCR2_Commit_LB[g] = 1;
                        global BUCR2_Commit_UB[g] = 1;
                    else
                        global BUCR2_Commit_LB[g] = 0;
                        global BUCR2_Commit_UB[g] = 1;
                    end
                elseif BUCR2_Init_DownTime[g]<DF_Generators.MinDownTime[g]
                    global BUCR2_Commit_LB[g] = 0;
                    global BUCR2_Commit_UB[g] = 0;
                else
                    global BUCR2_Commit_LB[g] = 0;
                    global BUCR2_Commit_UB[g] = 1;
                end
            end
        end #


        BUCR2model = direct_model(CPLEX.Optimizer())
        #BUCR2model=Model(with_optimizer(CPLEX.Optimizer))
        #set_optimizer_attribute(BUCR2model, "CPX_PARAM_EPINT", 1e-5)
        #set_optimizer_attribute(BUCR2model, "CPX_PARAM_EPINT", 0.2)
        set_optimizer_attribute(BUCR2model, "CPX_PARAM_EPGAP", 0.00001)

        # Declaring the decision variables for conventional generators
        @variable(BUCR2model, BUCR2_genOnOff[1:N_Gens], Bin) #Bin
        @variable(BUCR2model, BUCR2_genStartUp[1:N_Gens], Bin) # startup variable
        @variable(BUCR2model, BUCR2_genShutDown[1:N_Gens], Bin) # shutdown variable
        @variable(BUCR2model, BUCR2_genOut[1:N_Gens]>=0) # Generator's output schedule
        @variable(BUCR2model, BUCR2_genOut_Block[1:N_Gens, 1:N_Blocks]>=0) # Generator's output schedule from each block (block rfers to IHR curve blocks/segments)

        #@variable(BUCR2model, BUCR2_genResUp[1:N_Gens]>=0) # Generators' up reserve schedule
        #@variable(BUCR2model, BUCR2_genResDn[1:N_Gens]>=0) # Generator's down rserve schedule

        # declaring decision variables for storage Units
        @variable(BUCR2model, BUCR2_storgChrg[1:N_StorgUs], Bin) #Bin variable equal to 1 if unit runs in the charging mode
        @variable(BUCR2model, BUCR2_storgDisc[1:N_StorgUs], Bin) #Bin variable equal to 1 if unit runs in the discharging mode
        @variable(BUCR2model, BUCR2_storgIdle[1:N_StorgUs], Bin) ##Bin variable equal to 1 if unit runs in the idle mode
        @variable(BUCR2model, BUCR2_storgChrgPwr[1:N_StorgUs]>=0) #Chargung power
        @variable(BUCR2model, BUCR2_storgDiscPwr[1:N_StorgUs]>=0) # Discharging Power
        @variable(BUCR2model, BUCR2_storgSOC[1:N_StorgUs]>=0) # state of charge (stored energy level for storage unit at time t)
        #@variable(BUCR2model, BUCR2_storgResUp[1:N_StorgUs]>=0) # Scheduled up reserve
        #@variable(BUCR2model, BUCR2_storgResDn[1:N_StorgUs]>=0) # Scheduled down reserve

        # declaring decision variables for renewable generation
        @variable(BUCR2model, BUCR2_solarG[1:N_Zones]>=0) # solar energy schedules
        @variable(BUCR2model, BUCR2_windG[1:N_Zones]>=0) # wind energy schedules
        @variable(BUCR2model, BUCR2_hydroG[1:N_Zones]>=0) # hydro energy schedules
        @variable(BUCR2model, BUCR2_solarGSpil[1:N_Zones]>=0) # solar energy schedules
        @variable(BUCR2model, BUCR2_windGSpil[1:N_Zones]>=0) # wind energy schedules
        @variable(BUCR2model, BUCR2_hydroGSpil[1:N_Zones]>=0) # hydro energy schedules


        # declaring variables for transmission system
        @variable(BUCR2model, BUCR2_voltAngle[1:N_Zones]) #voltage angle at zone/bus n in t//
        @variable(BUCR2model, BUCR2_powerFlow[1:N_Zones, 1:M_Zones]) #transmission Flow from zone n to zone m//

        # Defining the objective function that minimizes the overal cost of supplying electricity (=total variable, no-load, startup, and shutdown costs)

        @objective(BUCR2model, Min, sum(sum(DF_Generators.IHRC_B1_HR[g]*FuelPrice[g,day]*(BUCR2_genOut_Block[g,1]-SUCRtoBUCR2_genOut_Block[g,1,h])
                                           +DF_Generators.IHRC_B2_HR[g]*FuelPrice[g,day]*(BUCR2_genOut_Block[g,2]-SUCRtoBUCR2_genOut_Block[g,2,h])
                                           +DF_Generators.IHRC_B3_HR[g]*FuelPrice[g,day]*(BUCR2_genOut_Block[g,3]-SUCRtoBUCR2_genOut_Block[g,3,h])
                                           +DF_Generators.IHRC_B4_HR[g]*FuelPrice[g,day]*(BUCR2_genOut_Block[g,4]-SUCRtoBUCR2_genOut_Block[g,4,h])
                                           +DF_Generators.IHRC_B5_HR[g]*FuelPrice[g,day]*(BUCR2_genOut_Block[g,5]-SUCRtoBUCR2_genOut_Block[g,5,h])
                                           +DF_Generators.IHRC_B6_HR[g]*FuelPrice[g,day]*(BUCR2_genOut_Block[g,6]-SUCRtoBUCR2_genOut_Block[g,6,h])
                                           +DF_Generators.IHRC_B7_HR[g]*FuelPrice[g,day]*(BUCR2_genOut_Block[g,7]-SUCRtoBUCR2_genOut_Block[g,7,h])
                                           +DF_Generators.NoLoadHR[g]*FuelPrice[g,day]*(BUCR2_genOnOff[g]-SUCRtoBUCR2_genOnOff[g,h]) +((DF_Generators.FixedSUCost[g]+(DF_Generators.StartUpHR[g]*FuelPrice[g,day]))*(BUCR2_genStartUp[g]-SUCRtoBUCR2_genStartUp[g,h]))
                                           +DF_Generators.ShutdownCost[g]*(BUCR2_genShutDown[g]-SUCRtoBUCR2_genShutDown[g,h]) for g in 1:N_Gens) for t in 1:N_Hrs_SUCR))


        # Constraints representing technical limits of conventional generators
        #Status transition trajectory of
        @constraint(BUCR2model, conStartUpAndDn[g=1:N_Gens], (BUCR2_genOnOff[g] - BUCR2_Init_genOnOff[g] - BUCR2_genStartUp[g] + BUCR2_genShutDown[g])==0)
        # Max Power generation limit in Block 1
        @constraint(BUCR2model, conMaxPowBlock1[g=1:N_Gens],  BUCR2_genOut_Block[g,1] <= DF_Generators.IHRC_B1_Q[g]*BUCR2_genOnOff[g] )
        # Max Power generation limit in Block 2
        @constraint(BUCR2model, conMaxPowBlock2[g=1:N_Gens],  BUCR2_genOut_Block[g,2] <= DF_Generators.IHRC_B2_Q[g]*BUCR2_genOnOff[g] )
        # Max Power generation limit in Block 3
        @constraint(BUCR2model, conMaxPowBlock3[g=1:N_Gens],  BUCR2_genOut_Block[g,3] <= DF_Generators.IHRC_B3_Q[g]*BUCR2_genOnOff[g] )
        # Max Power generation limit in Block 4
        @constraint(BUCR2model, conMaxPowBlock4[g=1:N_Gens],  BUCR2_genOut_Block[g,4] <= DF_Generators.IHRC_B4_Q[g]*BUCR2_genOnOff[g] )
        # Max Power generation limit in Block 5
        @constraint(BUCR2model, conMaxPowBlock5[g=1:N_Gens],  BUCR2_genOut_Block[g,5] <= DF_Generators.IHRC_B5_Q[g]*BUCR2_genOnOff[g] )
        # Max Power generation limit in Block 6
        @constraint(BUCR2model, conMaxPowBlock6[g=1:N_Gens],  BUCR2_genOut_Block[g,6] <= DF_Generators.IHRC_B6_Q[g]*BUCR2_genOnOff[g] )
        # Max Power generation limit in Block 7
        @constraint(BUCR2model, conMaxPowBlock7[g=1:N_Gens],  BUCR2_genOut_Block[g,7] <= DF_Generators.IHRC_B7_Q[g]*BUCR2_genOnOff[g] )
        # Total Production of each generation equals the sum of generation from its all blocks
        @constraint(BUCR2model, conTotalGen[g=1:N_Gens],  BUCR2_genOut[g] == sum(BUCR2_genOut_Block[g,b] for b=1:N_Blocks))
        #Max power generation limit
        @constraint(BUCR2model, conMaxPow[g=1:N_Gens],  BUCR2_genOut[g] <= DF_Generators.MaxPowerOut[g]*BUCR2_genOnOff[g])
        # Min power generation limit
        @constraint(BUCR2model, conMinPow[g=1:N_Gens],  BUCR2_genOut[g] >= DF_Generators.MinPowerOut[g]*BUCR2_genOnOff[g])

        #Up ramp rate limit
        @constraint(BUCR2model, conRampRateUp[g=1:N_Gens], (BUCR2_genOut[g] - BUCR2_Init_genOut[g] <=(DF_Generators.RampUpLimit[g]*BUCR2_Init_genOnOff[g]) + (DF_Generators.RampStartUpLimit[g]*BUCR2_genStartUp[g])))

        # Down ramp rate limit
        @constraint(BUCR2model, conRampRateDown[g=1:N_Gens], (BUCR2_Init_genOut[g] - BUCR2_genOut[g] <=(DF_Generators.RampDownLimit[g]*BUCR2_genOnOff[g]) + (DF_Generators.RampShutDownLimit[g]*BUCR2_genShutDown[g])))
        # Min Up Time limit with alternative formulation


        #The next twyo constraints enforce limits on binary commitment variables of slow and fast generators
        # scheduled slow units are forced to remain on, offline slow units remain off, and fast start units could change their commitment dependent on their MUT and MDT
        @constraint(BUCR2model, conCommitmentUB[g=1:N_Gens], (BUCR2_genOnOff[g] <= BUCR2_Commit_UB[g]))

        # if the generator is slow start and scheduled "on" in the SUCR,  is fixed by the following constraint
        @constraint(BUCR2model, conCommitmentLB[g=1:N_Gens], (BUCR2_genOnOff[g] >= BUCR2_Commit_LB[g]))

        # Renewable generation constraints
        @constraint(BUCR2model, conSolarLimit[n=1:N_Zones], BUCR2_solarG[n] + BUCR2_solarGSpil[n]<=BUCR2_Hr_SolarG[n])
        @constraint(BUCR2model, conWindLimit[n=1:N_Zones], BUCR2_windG[n] + BUCR2_windGSpil[n]<=BUCR2_Hr_WindG[n])
        @constraint(BUCR2model, conHydroLimit[n=1:N_Zones], BUCR2_hydroG[n] + BUCR2_hydroGSpil[n]<=BUCR2_Hr_HydroG[n])

        # Constraints representing technical characteristics of storage units
        # the next three constraints fix the balancing charging/discharging/Idle status to their optimal outcomes as determined by SUCR
        @constraint(BUCR2model, conStorgChrgStatusFixed[p=1:N_StorgUs], (BUCR2_storgChrg[p]==SUCRtoBUCR2_storgChrg[p,h]))
        @constraint(BUCR2model, conStorgDisChrgStatusFixed[p=1:N_StorgUs], (BUCR2_storgDisc[p]==SUCRtoBUCR2_storgDisc[p,h]))
        @constraint(BUCR2model, conStorgIdleStatusFixed[p=1:N_StorgUs], (BUCR2_storgIdle[p]==SUCRtoBUCR2_storgIdle[p,h]))

        # charging power limit
        @constraint(BUCR2model, conStrgChargPowerLimit[p=1:N_StorgUs], (BUCR2_storgChrgPwr[p] )<=DF_Storage.Power[p]*BUCR2_storgChrg[p])
        # Discharging power limit
        @constraint(BUCR2model, conStrgDisChgPowerLimit[p=1:N_StorgUs], (BUCR2_storgDiscPwr[p])<=DF_Storage.Power[p]*BUCR2_storgDisc[p])
        # State of charge at t
        @constraint(BUCR2model, conStorgSOC[p=1:N_StorgUs], BUCR2_storgSOC[p]==BUCR2_Init_storgSOC[p]-(BUCR2_storgDiscPwr[p]/DF_Storage.TripEfficDown[p])+(BUCR2_storgChrgPwr[p]*DF_Storage.TripEfficUp[p])-(BUCR2_storgSOC[p]*DF_Storage.SelfDischarge[p]))
        # minimum energy limit
        @constraint(BUCR2model, conMinEnrgStorgLimi[p=1:N_StorgUs], BUCR2_storgSOC[p]>=0)
        # Maximum energy limit
        @constraint(BUCR2model, conMaxEnrgStorgLimi[p=1:N_StorgUs], BUCR2_storgSOC[p]<=(DF_Storage.Power[p]/DF_Storage.PowerToEnergRatio[p]))


        # Constraints representing transmission grid capacity constraints
        # DC Power Flow Calculation
        @constraint(BUCR2model, conDCPowerFlowPos[n=1:N_Zones, m=1:N_Zones], BUCR2_powerFlow[n,m]-(TranS[n,m]*(BUCR2_voltAngle[n]-BUCR2_voltAngle[m])) ==0)
        @constraint(BUCR2model, conDCPowerFlowNeg[n=1:N_Zones, m=1:N_Zones], BUCR2_powerFlow[n,m]+BUCR2_powerFlow[m,n]==0)
        # Tranmission flow bounds (from n to m and from m to n)
        #    @constraint(BUCR2model, conPosFlowLimit[t=1:N_Hrs_BUCR, n=1:N_Zones, m=1:N_Zones], powerFlow[n,m,t]<=TranC[n,m])
        #    @constraint(BUCR2model, conNegFlowLimit[t=1:N_Hrs_BUCR, n=1:N_Zones, m=1:N_Zones], powerFlow[m,n,t]>=-TranC[n,m])
        # Voltage Angle bounds and reference point
        @constraint(BUCR2model, conVoltAnglUB[n=1:N_Zones], BUCR2_voltAngle[n]<=π)
        @constraint(BUCR2model, conVoltAnglLB[n=1:N_Zones], BUCR2_voltAngle[n]>=-π)
        @constraint(BUCR2model, conVoltAngRef, BUCR2_voltAngle[1]==0)

        # System-wide Constraints
        #nodal balance constraint
        @constraint(BUCR2model, conNodBalanc[n=1:N_Zones], sum((BUCR2_genOut[g]*Map_Gens[g,n]) for g=1:N_Gens) + sum((BUCR2_storgDiscPwr[p]*Map_Storage[p,n]) for p=1:N_StorgUs) - sum((BUCR2_storgChrgPwr[p]*Map_Storage[p,n]) for p=1:N_StorgUs) +BUCR2_solarG[n] +BUCR2_windG[n] +BUCR2_hydroG[n] - BUCR2_Hr_Demand[n] == sum(BUCR2_powerFlow[n,m] for m=1:M_Zones))
        # Minimum up reserve requirement
        #    @constraint(BUCR2model, conMinUpReserveReq[t=1:N_Hrs_BUCR], sum(genResUp[g,t] for g=1:N_Gens) + sum(storgResUp[p,t] for p=1:N_StorgUs) >= Reserve_Req_Up[t] )

        # Minimum down reserve requirement
        #    @constraint(BUCR2model, conMinDnReserveReq[t=1:N_Hrs_BUCR], sum(genResDn[g,t] for g=1:N_Gens) + sum(storgResDn[p,t] for p=1:N_StorgUs) >= Reserve_Req_Dn[t] )

        # solve the First WAUC model (BUCR)
        JuMP.optimize!(BUCR2model)

        # Pricing general results in the terminal window
        println("Objective value: ", JuMP.objective_value(BUCR2model))

        println("------------------------------------")
        println("------- BAUC2 OBJECTIVE VALUE -------")
        println("Objective value for day", day, "and hour ", h+INITIAL_HR_SUCR,"is:", JuMP.objective_value(BUCR2model))
        println("------------------------------------")
        println("------- BAUC2 PRIMAL STATUS -------")
        println(primal_status(BUCR2model))
        println("------------------------------------")
        println("------- BAUC2 DUAL STATUS -------")
        println(JuMP.dual_status(BUCR2model))
        println("For Day:", day, "and hour ", h+INITIAL_HR_SUCR, ": solved")
        println("---------------------------")

#########################################################
# Write the optimal outcomes into spreadsheets###########
############# Later we need to include a variable for day so the cell number in which the results are printed is updated accordingly

        # Write the conventional generators' schedules
        #XLSX.openxlsx(".\\OOutputs\\GenOutputs.xlsx", mode="w") do xf
        XLSX.openxlsx(".\\OOutputs\\BUCR_GenOutputs.xlsx", mode="rw") do xf
            sheet = xf[1]
            #XLSX.rename!(sheet, "new_sheet")
            #sheet["A1:I1"] = ["Hour" "GeneratorID" "VariableCost" "MinPowerOut" "MaxPowerOut" "Output" "On/off" "ShutDown" "Startup"]
            for g=1:N_Gens
                cell_n = ((((day-1)*24)+INITIAL_HR_SUCR)*N_Gens)+((h-1)*N_Gens)+g+1
                # In the above line, we should also make  usre +1 is only applied to the first day so the results are not printed on labels
                sheet[XLSX.CellRef(cell_n,1)] = day
                sheet[XLSX.CellRef(cell_n,2)] = h+INITIAL_HR_SUCR
                sheet[XLSX.CellRef(cell_n,3)] = g
                #sheet[XLSX.CellRef(cell_n,4)] = DF_Generators.VariableCost[g]
                sheet[XLSX.CellRef(cell_n,5)] = DF_Generators.MinPowerOut[g]
                sheet[XLSX.CellRef(cell_n,6)] = DF_Generators.MaxPowerOut[g]
                sheet[XLSX.CellRef(cell_n,7)] = JuMP.value.(BUCR2_genOut[g])
                sheet[XLSX.CellRef(cell_n,8)] = JuMP.value.(BUCR2_genOnOff[g])
                sheet[XLSX.CellRef(cell_n,9)] = JuMP.value.(BUCR2_genShutDown[g])
                sheet[XLSX.CellRef(cell_n,10)] = JuMP.value.(BUCR2_genStartUp[g])
            end # ends the loop
        end # ends "do"

        if day == 1
             open(".//OOutputs//csv//BUCR_GenOutputs.csv", FILE_ACCESS_OVER) do io
                 writedlm(io, permutedims(BUCR_GenOutputs_header), ',')
                 for g=1:N_Gens
     				writedlm(io, hcat(day, h+INITIAL_HR_SUCR, g,
						DF_Generators.MinPowerOut[g], DF_Generators.MaxPowerOut[g],
						JuMP.value.(BUCR2_genOut[g]), JuMP.value.(BUCR2_genOnOff[g]),
						JuMP.value.(BUCR2_genShutDown[g]), JuMP.value.(BUCR2_genStartUp[g])), ',')
                 end # ends the loop
             end; # closes file
         end # end if

         if day > 1
             open(".//OOutputs//csv//BUCR_GenOutputs.csv", FILE_ACCESS_APPEND) do io
                 for g=1:N_Gens
     				writedlm(io, hcat(day, h+INITIAL_HR_SUCR, g,
						DF_Generators.MinPowerOut[g], DF_Generators.MaxPowerOut[g],
						JuMP.value.(BUCR2_genOut[g]), JuMP.value.(BUCR2_genOnOff[g]),
						JuMP.value.(BUCR2_genShutDown[g]), JuMP.value.(BUCR2_genStartUp[g])), ',')
                 end # ends the loop
             end; # closes file
         end

        # Writing storage units' optimal schedules into spreadsheets
        #XLSX.openxlsx(".\\OOutputs\\StorageOutputs.xlsx", mode="w") do xf
        XLSX.openxlsx(".\\OOutputs\\BUCR_StorageOutputs.xlsx", mode="rw") do xf
            sheet = xf[1]
            #XLSX.rename!(sheet, "new_sheet")
            for p=1:N_StorgUs
                cell_n = ((((day-1)*24)+INITIAL_HR_SUCR)*N_StorgUs)+((h-1)*N_StorgUs)+p+1
                # In the above line, we should also make  usre +1 is only applied to the first day so the results are not printed on labels
                sheet[XLSX.CellRef(cell_n,1)] = day
                sheet[XLSX.CellRef(cell_n,2)] = h+INITIAL_HR_SUCR
                sheet[XLSX.CellRef(cell_n,3)] = p
                sheet[XLSX.CellRef(cell_n,4)] = DF_Storage.Power[p]
                sheet[XLSX.CellRef(cell_n,5)] = DF_Storage.Power[p]/DF_Storage.PowerToEnergRatio[p]
                sheet[XLSX.CellRef(cell_n,6)] = JuMP.value.(BUCR2_storgChrg[p])
                sheet[XLSX.CellRef(cell_n,7)] = JuMP.value.(BUCR2_storgDisc[p])
                sheet[XLSX.CellRef(cell_n,8)] = JuMP.value.(BUCR2_storgIdle[p])
                sheet[XLSX.CellRef(cell_n,9)] = JuMP.value.(BUCR2_storgChrgPwr[p])
                sheet[XLSX.CellRef(cell_n,10)] = JuMP.value.(BUCR2_storgDiscPwr[p])
                sheet[XLSX.CellRef(cell_n,11)] = JuMP.value.(BUCR2_storgSOC[p])
                #sheet[XLSX.CellRef(cell_n,12)] = JuMP.value.(BUCR2_storgResUp[p])
                #sheet[XLSX.CellRef(cell_n,13)] = JuMP.value.(BUCR2_storgResDn[p])
            end # ends the loop
        end # ends "do"

        if day == 1
             open(".//OOutputs//csv//BUCR_StorageOutputs.csv", FILE_ACCESS_OVER) do io
                 writedlm(io, permutedims(BUCR_StorageOutputs_header), ',')
                 for p=1:N_StorgUs
     				writedlm(io, hcat(day, h+INITIAL_HR_SUCR, p, DF_Storage.Power[p],
     						DF_Storage.Power[p]/DF_Storage.PowerToEnergRatio[p], JuMP.value.(BUCR2_storgChrg[p]),
     						JuMP.value.(BUCR2_storgDisc[p]), JuMP.value.(BUCR2_storgIdle[p]), JuMP.value.(BUCR2_storgChrgPwr[p]),
     						JuMP.value.(BUCR2_storgDiscPwr[p]), JuMP.value.(BUCR2_storgSOC[p]) ), ',')

                 end # ends the loop
             end; # closes file
         end # end if

         if day > 1
             open(".//OOutputs//csv//BUCR_StorageOutputs.csv", FILE_ACCESS_APPEND) do io
                 for p=1:N_StorgUs
     				writedlm(io, hcat(day, h+INITIAL_HR_SUCR, p, DF_Storage.Power[p],
     						DF_Storage.Power[p]/DF_Storage.PowerToEnergRatio[p], JuMP.value.(BUCR2_storgChrg[p]),
     						JuMP.value.(BUCR2_storgDisc[p]), JuMP.value.(BUCR2_storgIdle[p]), JuMP.value.(BUCR2_storgChrgPwr[p]),
     						JuMP.value.(BUCR2_storgDiscPwr[p]), JuMP.value.(BUCR2_storgSOC[p]) ), ',')
                 end # ends the loop
             end; # closes file
         end

        # Writeing the transmission flow schedules into spreadsheets
        #XLSX.openxlsx(".\\OOutputs\\TranFlowOutputs.xlsx", mode="w") do tf
        XLSX.openxlsx(".\\OOutputs\\BUCR_TranFlowOutputs.xlsx", mode="rw") do xf
            sheet = xf[1]
                #XLSX.rename!(sheet, "new_sheet")
                for n=1:N_Zones, m=1:M_Zones
                    cell_n = ((((day-1)*24)+INITIAL_HR_SUCR)*N_Zones*M_Zones)+((h-1)*N_Zones*M_Zones)+m+1
                    # In the above line, we should also make  usre +1 is only applied to the first day so the results are not printed on labels
                    sheet[XLSX.CellRef(cell_n,1)] = day
                    sheet[XLSX.CellRef(cell_n,2)] = h+INITIAL_HR_SUCR
                    sheet[XLSX.CellRef(cell_n,3)] = n
                    sheet[XLSX.CellRef(cell_n,4)] = m
                    sheet[XLSX.CellRef(cell_n,5)] = JuMP.value.(BUCR2_powerFlow[n,m])
                sheet[XLSX.CellRef(cell_n,6)] = TranC[n,m]
            end # ends the loop
        end # ends "do"

        if day == 1
            open(".//OOutputs//csv//BUCR_TranFlowOutputs.csv", FILE_ACCESS_OVER) do io
                writedlm(io, permutedims(BUCR_TranFlowOutputs_header), ',')
                for n=1:N_Zones, m=1:M_Zones
    				writedlm(io, hcat(day, h+INITIAL_HR_SUCR, n, m, JuMP.value.(BUCR2_powerFlow[n,m]), TranC[n,m]), ',')
                end # ends the loop
            end; # closes file
        end # end if

        if day > 1
            open(".//OOutputs//csv//BUCR_TranFlowOutputs.csv", FILE_ACCESS_APPEND) do io
                for n=1:N_Zones, m=1:M_Zones
    				writedlm(io, hcat(day, h+INITIAL_HR_SUCR, n, m, JuMP.value.(BUCR2_powerFlow[n,m]), TranC[n,m]), ',')
                end # ends the loop
            end; # closes file
        end


## Initilization of the next UC Run
    # Setting initial values for BUCR2 (next hour), FUCR, and BUCR1
        for g=1:N_Gens
            # set the initiali values to be fed to the next hour BUCR2
            global BUCR2_Init_genOnOff[g] = JuMP.value.(BUCR2_genOnOff[g]); #
            global BUCR2_Init_genOut[g] = JuMP.value.(BUCR2_genOut[g]);
            # Set the initial values fed to the next FUCR and BUCR1

        #    if h==(24-INITIAL_HR_SUCR+INITIAL_HR_FUCR)
            global BUCR1_Init_genOnOff[g] = JuMP.value.(BUCR2_genOnOff[g]);
            global BUCR1_Init_genOut[g] = JuMP.value.(BUCR2_genOut[g]);
            global FUCR_Init_genOnOff[g] = JuMP.value.(BUCR2_genOnOff[g]);
            global FUCR_Init_genOut[g] = JuMP.value.(BUCR2_genOut[g]);
        #    end
        end
        print(h)
        for p=1:N_StorgUs
            # Set the initial values to be fed to the next hour BUCR2
            global BUCR2_Init_storgSOC[p]=JuMP.value.(BUCR2_storgSOC[p]);
            # set the initiali values to be fed to the next hour BUCR2
            #if h==(24-INITIAL_HR_SUCR+INITIAL_HR_FUCR)
            global BUCR1_Init_storgSOC[p] = JuMP.value.(BUCR2_storgSOC[p]);
            global FUCR_Init_storgSOC[p] = JuMP.value.(BUCR2_storgSOC[p]);
            #end
        end

        #Update the up and down times for individual generators
        for g=1:N_Gens
            #Update the total up-time or down-time for each individual generator to be fed into BUCR2
            if (JuMP.value.(BUCR2_genStartUp[g]))==1
                global BUCR2_Init_UpTime[g]= 1;
                global BUCR2_Init_DownTime[g] = 0;
            elseif (JuMP.value.(BUCR2_genShutDown[g]))==1
                global BUCR2_Init_UpTime[g]= 0;
                global BUCR2_Init_DownTime[g]= 1;
            else
                if (JuMP.value.(BUCR2_genOnOff[g]))==1
                    global BUCR2_Init_UpTime[g]=BUCR2_Init_UpTime[g]+1;
                    global BUCR2_Init_DownTime[g]= 0;
                else
                    global BUCR2_Init_UpTime[g]= 0;
                    global BUCR2_Init_DownTime[g]= BUCR2_Init_DownTime[g]+1;
                end
            end
            #Update the total up and down times to be fed into FUCR and BUCR1
            if h==(INITIAL_HR_SUCR-INITIAL_HR_FUCR)
                global BUCR1_Init_UpTime[g]= BUCR2_Init_UpTime[g];
                global BUCR1_Init_DownTime[g]= BUCR2_Init_DownTime[g];
                global FUCR_Init_UpTime[g]= BUCR2_Init_UpTime[g];
                global FUCR_Init_DownTime[g]= BUCR2_Init_DownTime[g];
            end
        end


    end # ends the loop that runs hourly BUCR between [INITIAL_HR_FUCR and INITIAL_HR_SUCR)

##
end # ends the foor loop that runs the UC model on  a daily basis

t2 = time_ns()
elapsedTime = (t2 -t1)/1.0e9;

print("Whole program time execution (s):\t $elapsedTime\n")
write(io_log, "Whole program time execution (s):\t $elapsedTime\n")
close(io_log);
