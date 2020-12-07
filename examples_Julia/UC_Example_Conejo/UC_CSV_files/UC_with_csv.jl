using DataFrames
using CSV, DelimitedFiles
using JuMP, CPLEX

#Preparing optimization model
model = Model(CPLEX.Optimizer)
set_optimizer_attribute(model, "CPX_PARAM_EPINT", 1e-8)

const N_GEN = 3
const N_HRS = 4

dfGenerator = CSV.read("data_generators.csv", DataFrame)
dfDemand = CSV.read("demand_reserves.csv", DataFrame)

#println(dfGenerator);
#println(dfDemand);
for g=1:N_GEN
  println("\t Generator at Time $g: ", dfGenerator.Uini[g])
end

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
@constraint(model, constDemand[t=1:N_HRS], sum(genOut[g, t] for g=1:N_GEN) == dfDemand.DemandNode01[t])
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
@constraint(model, constReserves[t=1:N_HRS], sum(dfGenerator.MaxPowerOut[g]*genOnOff[g,t] for g=1:N_GEN) >= (dfDemand.DemandNode01[t] + dfDemand.Reserves[t]))

optimize!(model)


println("------------------------------------")
println("------- OPTIMAL SOLUTION -------")
for t=1:N_HRS
  print("Hour $t","\t")
end
println("")
for g=1:N_GEN
  for t=1:N_HRS
    print(round(JuMP.value(genOut[g,t]); digits=3 ),"\t")
  #  println(round(pi; digits = 3))

  end
  println("\t Generator: $g")
end

println("------------------------------------")
println("------- GENERATORS COMMITED --------")
for t=1:N_HRS
  print("Hour $t","\t")
end
println("")

for g=1:N_GEN
  for t=1:N_HRS
    #print(JuMP.value(genOnOff[g,t]),"\t")
    print(convert(Int32, JuMP.value(genOnOff[g,t])),"\t")
  end
  println("\t Generator: $g")
end
