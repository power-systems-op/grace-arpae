#Reference: https://jump.dev/JuMP.jl/0.17/refexpr.html
using CSV, DelimitedFiles, DataFrames
using JuMP, CPLEX

#Preparing optimization model

const N_GEN = 145
const N_HRS = 24
const INITIAL_DAY = 1

dfGenerator = CSV.read(".//inputs//data_generators.csv", DataFrame)
dfDemand = CSV.read(".//inputs//demand_reserves.csv", DataFrame)

for day in 1:2
  local dfDayDemand = dfDemand[(day-1)*N_HRS+1:(N_HRS*day)+1, [:Hour, :Demand, :Reserves]];

    model = Model(CPLEX.Optimizer)
    set_optimizer_attribute(model, "CPX_PARAM_EPINT", 1e-5)

    @variable(model, genOnOff[1:N_GEN, 1:N_HRS], Bin)
    @variable(model, genOut[1:N_GEN, 1:N_HRS] >= 0)
    @variable(model, genStartUp[1:N_GEN, 1:N_HRS], Bin)
    @variable(model, genShutDown[1:N_GEN, 1:N_HRS], Bin)

    #Setting the objective function
    @objective(model, Min, sum(sum(dfGenerator.FixedCost[g]*genOnOff[g,t] + dfGenerator.VariableCost[g]*genOut[g,t] + dfGenerator.StartUpCost[g]*genStartUp[g,t] + dfGenerator.ShutdownCost[g]*genShutDown[g, t] for g in 1:N_GEN) for t in 1:N_HRS) )

    #Initial constraints
    #Generators should have an initial and defined value t=0
    @constraint(model, constInit[g=1:N_GEN], genOnOff[g,1] == dfGenerator.Uini[g])

    #Initial values of Generator shutdown and startup values should be defined
    @constraint(model, constShutDn[g=1:N_GEN], genShutDown[g,1] == 0)
    @constraint(model, constShutUp[g=1:N_GEN], genStartUp[g,1] == 0)

    #Demand constraint
    #for t in 1:N_HRS
    @constraint(model, constDemand[t=1:N_HRS], sum(genOut[g, t] for g=1:N_GEN) == dfDayDemand.Demand[t])
    #end

    #Power bounds
    @constraint(model, constMaxPow[t=1:N_HRS, g=1:N_GEN],  genOut[g,t] <= dfGenerator.MaxPowerOut[g]*genOnOff[g,t] )
    @constraint(model, constMinPow[t=1:N_HRS, g=1:N_GEN],  genOut[g,t] >= dfGenerator.MinPowerOut[g]*genOnOff[g,t] )

    #Logical Conditions
    @constraint(model, constLog1[t=2:N_HRS, g=1:N_GEN], (genStartUp[g,t] - genShutDown[g,t]) == (genOnOff[g,t] - genOnOff[g,t-1]))
    @constraint(model, constLog2[t=1:N_HRS, g=1:N_GEN], genStartUp[g,t] + genShutDown[g, t] <= 1)

    #Ramp limits
    @constraint(model, constRampUp[t=2:N_HRS, g=1:N_GEN], genOut[g,t] - genOut[g,t-1] <= dfGenerator.RampUpLimit[g]*genOnOff[g, t-1] + dfGenerator.RampStartUpLimit[g]*genStartUp[g,t])
    @constraint(model, constRampDown[t=2:N_HRS, g=1:N_GEN], (genOut[g,t-1] - genOut[g,t]) <= (dfGenerator.RampDownLimit[g]*genOnOff[g,t] + dfGenerator.RampShutDownLimit[g]*genShutDown[g,t]))

    #Reserves
    @constraint(model, constReserves[t=1:N_HRS], sum(dfGenerator.MaxPowerOut[g]*genOnOff[g,t] for g=1:N_GEN) >= (dfDayDemand.Demand[t] + dfDayDemand.Reserves[t]))

    mystatus = optimize!(model)

    #Printing general results
    println("------------------------------------")
    println("------- OBJECTIVE VALUE -------")
    println("Objective value: ", JuMP.objective_value(model))

  println("------- DATA TYPE -------")
    print(typeof(JuMP.value.(genOut)))
    genOutTrans = transpose(JuMP.value.(genOut))

    open(".//outputs//resultsTrans.csv", "w") do io
                  writedlm(io, genOutTrans, ',')
            end;

end
