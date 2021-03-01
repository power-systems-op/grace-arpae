# set the Directory to the local folder
#cd("C://Users//Ali Nikpendar//Google Drive//Julia files//Grace//Temp_Projects//dataentry")

#using Queryverse
using XLSX, DataFrames, CSV
using JuMP, CPLEX




#const π
##
########################### Importing input data from the input spreadsheets
# Generators' specification
DF_Generators = DataFrame(XLSX.readtable(".\\inputs\\data_generators.XLSX", "data_generators")...)

# Generators location map: if a generator g is located in zone z Map_Gens[g,z]=1; and 0 otherwise
DF_Map_Gens = DataFrame(XLSX.readtable(".\\inputs\\data_generators.XLSX", "location_generators")...)
Map_Gens = convert(Matrix, DF_Map_Gens[:,2:N_Zones+1])

# Storage Units' specification and location
DF_Storage = DataFrame(XLSX.readtable(".\\inputs\\data_storage.XLSX", "data_storage")...) # storage specs
DF_Map_Storage = DataFrame(XLSX.readtable(".\\inputs\\data_storage.XLSX", "location_storage")...) # storage location as a dataframe
Map_Storage = convert(Matrix, DF_Map_Gens[:,2:N_Zones+1]) # convert storage location data to  a matrix

# energy demand at each location
#DF_Dems = DataFrame(XLSX.readtable(".\\Inputs\\data_demand.XLSX", "data_demand")...)
Demands = XLSX.readdata(".\\inputs\\data_demand.XLSX", "data_demand", "B2:K25")
# There is no map for the demand data. Instead we take the input demand data for each zone. In other words, Demand[t,z] represents demand at zone z and time t

# Transmission system data (Capacity and Susceptance)
TranC = XLSX.readdata(".\\inputs\\data_transmission.XLSX", "LineCapacity","B2:K11") # Transmission line capacity
TranS = XLSX.readdata(".\\inputs\\data_transmission.XLSX", "LineSusceptance","B2:K11")# Transmission line susceptance

# Up and down Reserve Requirements data
Reserve_Req_Up = XLSX.readdata(".\\inputs\\data_reserve_reqs.XLSX", "data_reserve_reqs","B2:B25") # Hourly Up Reserve requirement data
Reserve_Req_Dn = XLSX.readdata(".\\inputs\\data_reserve_reqs.XLSX", "data_reserve_reqs","C2:C25")# Hourly down reserve requirement data


# Parameters
const N_Gens =  24 # number of conventional generators
const N_StorgUs =  10 # number of storage units
const N_Zones = 10
const M_Zones = 10
const N_Blocks =7
const N_Hrs = 24
const INITIAL_DAY = 1
const FINAL_DAY = 1


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
lbu=zeros(N_Gens, N_Hrs)
for g in 1:N_Gens , t in 1:N_Hrs
    lbu[g,t]=t-DF_Generators.MinUpTime[g]+1
    if (lbu[g,t]<1)
        lbu[g,t]=1
    end
end

lb_MUT = round.(Int, lbu)

lbd=zeros(N_Gens,N_Hrs)
for g in 1:N_Gens , t in 1:N_Hrs
    lbd[g,t]=t-DF_Generators.MinUpTime[g]+1
    if (lbd[g,t]<1)
        lbd[g,t]=1
    end
end

lb_MDT = round.(Int, lbd)

## Defining the UC model
UCmodel=Model(with_optimizer(CPLEX.Optimizer))
set_optimizer_attribute(UCmodel, "CPX_PARAM_EPINT", 1e-5)

# Declaring the decision variables for conventional generators
@variable(UCmodel, genOnOff[1:N_Gens, 0:N_Hrs], Bin) #Bin
@variable(UCmodel, genStartUp[1:N_Gens, 1:N_Hrs], Bin) # startup variable
@variable(UCmodel, genShutDown[1:N_Gens, 1:N_Hrs], Bin) # shutdown variable
@variable(UCmodel, genOut[1:N_Gens, 0:N_Hrs]>=0) # Generator's output schedule
@variable(UCmodel, genResUp[1:N_Gens, 1:N_Hrs]>=0) # Generators' up reserve schedule
@variable(UCmodel, genResDn[1:N_Gens, 1:N_Hrs]>=0) # Generator's down rserve schedule

# declaring decision variables for storage Units
@variable(UCmodel, storgChrg[1:N_StorgUs, 1:N_Hrs], Bin) #Bin variable equal to 1 if unit runs in the charging mode
@variable(UCmodel, storgDisc[1:N_StorgUs, 1:N_Hrs], Bin) #Bin variable equal to 1 if unit runs in the discharging mode
@variable(UCmodel, storgIdle[1:N_StorgUs, 1:N_Hrs], Bin) ##Bin variable equal to 1 if unit runs in the idle mode
@variable(UCmodel, storgChrgPwr[1:N_StorgUs, 0:N_Hrs]>=0) #Chargung power
@variable(UCmodel, storgDiscPwr[1:N_StorgUs, 0:N_Hrs]>=0) # Discharging Power
@variable(UCmodel, storgSOC[1:N_StorgUs, 0:N_Hrs]>=0) # state of charge (stored energy level for storage unit at time t)
@variable(UCmodel, storgResUp[1:N_StorgUs, 0:N_Hrs]>=0) # Scheduled up reserve
@variable(UCmodel, storgResDn[1:N_StorgUs, 0:N_Hrs]>=0) # Scheduled down reserve


# declaring variables for transmission system
@variable(UCmodel, voltAngle[1:N_Zones, 1:N_Hrs]) #voltage angle at zone/bus n in t//
@variable(UCmodel, powerFlow[1:N_Zones, 1:M_Zones, 1:N_Hrs]) #transmission Flow from zone n to zone m//

# Defining the objective function that minimizes the overal cost of supplying electricity (=total variable, no-load, startup, and shutdown costs)

@objective(UCmodel, Min, sum(sum(DF_Generators.VariableCost[g]*genOut[g,t]+DF_Generators.NoLoadCost[g]*genOnOff[g,t] +DF_Generators.StartUpCost[g]*genStartUp[g,t] + DF_Generators.ShutdownCost[g]*genShutDown[g, t] for g in 1:N_Gens)
           for t in 1:N_Hrs))


#=
# Commitment variable upper bound
@constraint(UCmodel, conOnOffUB[t=1:N_Hrs, g=1:N_Gens],  genOnOff[g,t] <= 1)
@constraint(UCmodel, conGenSUUB[t=1:N_Hrs, g=1:N_Gens],  genStartUp[g,t] <= 1)
@constraint(UCmodel, conGenSDUB[t=1:N_Hrs, g=1:N_Gens],  genShutDown[g,t] <= 1)
=#

#Initialization of commitment and dispatch variables at t=0 (representing the last hour of previous scheduling horizon day=day-1 and t=24)
@constraint(UCmodel, conInitGenOnOff[g=1:N_Gens], genOnOff[g,0]==DF_Generators.StatusInit[g]) # initial generation level for generator g at t=0
@constraint(UCmodel, conInitGenOut[g=1:N_Gens], genOut[g,0]==DF_Generators.PowerInit[g]) # initial on/off status for generators g at t=0
@constraint(UCmodel, conInitSOC[p=1:N_StorgUs], storgSOC[p,0]==DF_Storage.SOCInit[p]) # SOC for storage unit p at t=0


## Constraints representing technical limits of conventional generators
#Status transition trajectory of
@constraint(UCmodel, conStartUpAndDn[t=1:N_Hrs, g=1:N_Gens], (genOnOff[g,t] - genOnOff[g,t-1] - genStartUp[g,t] + genShutDown[g,t])==0)
#Max power generation limit
@constraint(UCmodel, conMaxPow[t=1:N_Hrs, g=1:N_Gens],  genOut[g,t]+genResUp[g,t] <= DF_Generators.MaxPowerOut[g]*genOnOff[g,t] )
# Min power generation limit
@constraint(UCmodel, conMinPow[t=1:N_Hrs, g=1:N_Gens],  genOut[g,t]-genResDn[g,t] >= DF_Generators.MinPowerOut[g]*genOnOff[g,t] )
# Up reserve provision limit
@constraint(UCmodel, conMaxResUp[t=1:N_Hrs, g=1:N_Gens],  genResUp[g,t] <= DF_Generators.UpReserveLimit[g]*genOnOff[g,t] )
#Down reserve provision limit
@constraint(UCmodel, conMaxResDown[t=1:N_Hrs, g=1:N_Gens],  genResDn[g,t] <= DF_Generators.DownReserveLimit[g]*genOnOff[g,t] )
#Up ramp rate limit
@constraint(UCmodel, conRampRateUp[t=1:N_Hrs, g=1:N_Gens], (genOut[g,t] - genOut[g,t-1] <=(DF_Generators.RampUpLimit[g]*genOnOff[g, t-1]) + (DF_Generators.RampStartUpLimit[g]*genStartUp[g,t])))
# Down ramp rate limit
@constraint(UCmodel, conRampRateDown[t=1:N_Hrs, g=1:N_Gens], (genOut[g,t-1] - genOut[g,t] <=(DF_Generators.RampDownLimit[g]*genOnOff[g,t]) + (DF_Generators.RampShutDownLimit[g]*genShutDown[g,t])))
# Min Up Time limit with alternative formulation
@constraint(UCmodel, conUpTime[t=1:N_Hrs, g=1:N_Gens], (sum(genStartUp[g,k] for k=lb_MUT[g,t]:t)<=genOnOff[g,t]))
# Min down Time limit with alternative formulation
@constraint(UCmodel, conDownTime[t=1:N_Hrs, g=1:N_Gens], (1-sum(genShutDown[g,i] for i=lb_MDT[g,t]:t)>=genOnOff[g,t]))

## Constraints representing technical characteristics of storage units
# status transition of storage units between charging, discharging, and idle modes
@constraint(UCmodel, conStorgStatusTransition[t=1:N_Hrs, p=1:N_StorgUs], (storgChrg[p,t]+storgDisc[p,t]+storgIdle[p,t])==1)
# charging power limit
@constraint(UCmodel, conStrgChargPowerLimit[t=1:N_Hrs, p=1:N_StorgUs], (storgChrgPwr[p,t] - storgResDn[p,t])<=DF_Storage.Power[p]*storgChrg[p,t])
# Discharging power limit
@constraint(UCmodel, conStrgDisChgPowerLimit[t=1:N_Hrs, p=1:N_StorgUs], (storgDiscPwr[p,t] + storgResUp[p,t])<=DF_Storage.Power[p]*storgDisc[p,t])
# Down reserve provision limit
@constraint(UCmodel, conStrgDownResrvMax[t=1:N_Hrs, p=1:N_StorgUs], storgResDn[p,t]<=DF_Storage.Power[p]*storgChrg[p,t])
# Up reserve provision limit`
@constraint(UCmodel, conStrgUpResrvMax[t=1:N_Hrs, p=1:N_StorgUs], storgResUp[p,t]<=DF_Storage.Power[p]*storgDisc[p,t])
# State of charge at t
@constraint(UCmodel, conStorgSOC[t=1:N_Hrs, p=1:N_StorgUs], storgSOC[p,t]==storgSOC[p,t-1]-(storgDiscPwr[p,t]/DF_Storage.TripEfficDown[p])+(storgChrgPwr[p,t]*DF_Storage.TripEfficUp[p])-(storgSOC[p,t]*DF_Storage.SelfDischarge[p]))
# minimum energy limit
@constraint(UCmodel, conMinEnrgStorgLimi[t=1:N_Hrs, p=1:N_StorgUs], storgSOC[p,t]-(storgResUp[p,t]/DF_Storage.TripEfficDown[p])+(storgResDn[p,t]/DF_Storage.TripEfficUp[p])>=0)
# Maximum energy limit
@constraint(UCmodel, conMaxEnrgStorgLimi[t=1:N_Hrs, p=1:N_StorgUs], storgSOC[p,t]-(storgResUp[p,t]/DF_Storage.TripEfficDown[p])+(storgResDn[p,t]/DF_Storage.TripEfficUp[p])<=(DF_Storage.Power[p]/DF_Storage.PowerToEnergRatio[p]))
## Constraints representing transmission grid capacity constraints
# DC Power Flow Calculation
@constraint(UCmodel, conDCPowerFlowPos[t=1:N_Hrs, n=1:N_Zones, m=1:N_Zones], powerFlow[n,m,t]-(TranS[n,m]*(voltAngle[n,t]-voltAngle[m,t])) ==0)
@constraint(UCmodel, conDCPowerFlowNeg[t=1:N_Hrs, n=1:N_Zones, m=1:N_Zones], powerFlow[n,m,t]+powerFlow[m,n,t]==0)
# Tranmission flow bounds (from n to m and from m to n)
@constraint(UCmodel, conPosFlowLimit[t=1:N_Hrs, n=1:N_Zones, m=1:N_Zones], powerFlow[n,m,t]<=TranC[n,m])
@constraint(UCmodel, conNegFlowLimit[t=1:N_Hrs, n=1:N_Zones, m=1:N_Zones], powerFlow[m,n,t]>=-TranC[n,m])
# Voltage Angle bounds and reference point
@constraint(UCmodel, conVoltAnglUB[t=1:N_Hrs, n=1:N_Zones], voltAngle[n,t]<=π)
@constraint(UCmodel, conVoltAnglLB[t=1:N_Hrs, n=1:N_Zones], voltAngle[n,t]>=-π)
@constraint(UCmodel, conVoltAngRef[t=1:N_Hrs], voltAngle[1,t]==0)

## System-wide Constraints
#nodal balance constraint
@constraint(UCmodel, conNodBalanc[t=1:N_Hrs, n=1:N_Zones], sum((genOut[g,t]*Map_Gens[g,n]) for g=1:N_Gens) + sum((storgDiscPwr[p,t]*Map_Storage[p,n]) for p=1:N_StorgUs) - sum((storgChrgPwr[p,t]*Map_Storage[p,n]) for p=1:N_StorgUs)  - Demands[t,n] == sum(powerFlow[n,m,t] for m=1:M_Zones))
# Minimum up reserve requirement
@constraint(UCmodel, conMinUpReserveReq[t=1:N_Hrs], sum(genResUp[g,t] for g=1:N_Gens) + sum(storgResUp[p,t] for p=1:N_StorgUs) >= Reserve_Req_Up[t] )

# Minimum down reserve requirement
@constraint(UCmodel, conMinDnReserveReq[t=1:N_Hrs], sum(genResDn[g,t] for g=1:N_Gens) + sum(storgResDn[p,t] for p=1:N_StorgUs) >= Reserve_Req_Dn[t] )

JuMP.optimize!(UCmodel)
#optimize!(UCmodel)
println("Objective value: ", JuMP.objective_value(UCmodel))


    #Printing general results
    println("------------------------------------")
    println("------- OBJECTIVE VALUE -------")
    println("Objective value for day 1: ", JuMP.objective_value(UCmodel))

    println("------------------------------------")
    println("------- PRIMAL STATUS -------")
    println(primal_status(UCmodel))

    println("------------------------------------")
    println("------- DUAL STATUS -------")
    println(JuMP.dual_status(UCmodel))

    println("Day: 1 solved")
    println("---------------------------")

## Write the optimal outcomes into spreadsheets
############# Later we need to include a variable for day so the cell number in which the results are printed is updated accordingly

# Write the conventional generators' schedules
XLSX.openxlsx(".\\outputs\\GenOutputs.xlsx", mode="w") do xf
    sheet = xf[1]
    XLSX.rename!(sheet, "new_sheet")
    sheet["A1:I1"] = ["Hour" "GeneratorID" "VariableCost" "MinPowerOut" "MaxPowerOut" "Output" "On/off" "ShutDown" "Startup"]
    for t in 1:N_Hrs, g=1:N_Gens
        cell_n = ((t-1)*N_Gens)+g+1 # +1 is to start from the second row and leave the first row for typing
        # In the above line, we should also make  usre +1 is only applied to the first day so the results are not printed on labels
        sheet[XLSX.CellRef(cell_n,1)] = t
        sheet[XLSX.CellRef(cell_n,2)] = g
        sheet[XLSX.CellRef(cell_n,3)] = DF_Generators.VariableCost[g]
        sheet[XLSX.CellRef(cell_n,4)] = DF_Generators.MinPowerOut[g]
        sheet[XLSX.CellRef(cell_n,5)] = DF_Generators.MaxPowerOut[g]
        sheet[XLSX.CellRef(cell_n,6)] = JuMP.value.(genOut[g,t])
        sheet[XLSX.CellRef(cell_n,7)] = JuMP.value.(genOnOff[g,t])
        sheet[XLSX.CellRef(cell_n,8)] = JuMP.value.(genShutDown[g,t])
        sheet[XLSX.CellRef(cell_n,9)] = JuMP.value.(genStartUp[g,t])
    end # ends the loop

end # ends "do"

# Writhe storage units' schedules
XLSX.openxlsx(".\\outputs\\StorageOutputs.xlsx", mode="w") do xf
    sheet = xf[1]
    XLSX.rename!(sheet, "new_sheet")
    sheet["A1:L1"] = ["Hour" "StorageUniID" "Power" "EnergyLimit" "Charge_St" "Discharge_St" "Idle_St" "storgChrgPwr" "storgDiscPwr" "storgSOC" "storgResUp" "storgResDn"]
    for t in 1:N_Hrs, p=1:N_StorgUs
        cell_n = ((t-1)*N_StorgUs)+p+1 # +1 is to start from the second row and leave the first row for typing
        # In the above line, we should also make  usre +1 is only applied to the first day so the results are not printed on labels
        sheet[XLSX.CellRef(cell_n,1)] = t
        sheet[XLSX.CellRef(cell_n,2)] = p
        sheet[XLSX.CellRef(cell_n,3)] = DF_Storage.Power[p]
        sheet[XLSX.CellRef(cell_n,4)] = DF_Storage.Power[p]/DF_Storage.PowerToEnergRatio[p]
        sheet[XLSX.CellRef(cell_n,5)] = JuMP.value.(storgChrg[p,t])
        sheet[XLSX.CellRef(cell_n,6)] = JuMP.value.(storgDisc[p,t])
        sheet[XLSX.CellRef(cell_n,7)] = JuMP.value.(storgIdle[p,t])
        sheet[XLSX.CellRef(cell_n,8)] = JuMP.value.(storgChrgPwr[p,t])
        sheet[XLSX.CellRef(cell_n,9)] = JuMP.value.(storgDiscPwr[p,t])
        sheet[XLSX.CellRef(cell_n,10)] = JuMP.value.(storgSOC[p,t])
        sheet[XLSX.CellRef(cell_n,11)] = JuMP.value.(storgResUp[p,t])
        sheet[XLSX.CellRef(cell_n,12)] = JuMP.value.(storgResDn[p,t])
    end # ends the loop

end # ends "do"

# Write the transmission flow schedules
XLSX.openxlsx(".\\outputs\\TranFlowOutputs.xlsx", mode="w") do tf
    sheet = tf[1]
    XLSX.rename!(sheet, "new_sheet_II")
    sheet["A1:E1"] = ["Time period" "Source" "Sink" "Flow" "TransCap"]
    for t in 1:N_Hrs, n=1:N_Zones, m=1:M_Zones
        cell_n = ((t-1)*N_Zones*M_Zones)+((n-1)*N_Zones)+m+1 # +1 is to start from the second row and leave the first row for typing
        # In the above line, we should also make  usre +1 is only applied to the first day so the results are not printed on labels
        sheet[XLSX.CellRef(cell_n,1)] = t
        sheet[XLSX.CellRef(cell_n,2)] = n
        sheet[XLSX.CellRef(cell_n,3)] = m
        sheet[XLSX.CellRef(cell_n,4)] = JuMP.value.(powerFlow[n,m,t])
        sheet[XLSX.CellRef(cell_n,5)] = TranC[n,m]
    end # ends the loop
end # ends "do"
