using JuMP, CPLEX

#Preparing optimization model
model = Model(CPLEX.Optimizer)
set_optimizer_attribute(model, "CPX_PARAM_EPINT", 1e-8)

const N_GEN = 3
const N_HRS = 4

fixedCost = [5 7 6];
variableCost = [0.100 0.125 0.150];
startUpCost = [20 18 5];
shutdownCost = [0.5 0.3 1.0];

minPowerOut = [50 80 40];
maxPowerOut = [350 200 140];
rampDownLimit = [300 150 100];
rampShutDownLimit = [300 150 100];
rampUpLimit = [200 100 100];
rampStartUpLimit = [200 100 100];

demand = [100; 160; 500; 400];
reserves = [0; 16; 50; 40];

@variable(model, genOnOff[1:N_GEN, 1:N_HRS], Bin)
@variable(model, genOut[1:N_GEN, 1:N_HRS] >= 0)
@variable(model, genStartUp[1:N_GEN, 1:N_HRS], Bin)
@variable(model, genShutDown[1:N_GEN, 1:N_HRS], Bin)

#Setting the objective function
@objective(model, Min, sum(sum( fixedCost[g]*genOnOff[g,t] + variableCost[g]*genOut[g,t] + startUpCost[g]*genStartUp[g,t] + shutdownCost[g]*genShutDown[g, t] for g in 1:N_GEN) for t in 1:N_HRS) )

#Generator #1 should be ON at t=0
@constraint(model, constInit[t=1, g=3], genOnOff[g,t] == 1)

#Initial constraints
@constraint(model, constShutDn[g=1:N_GEN], genShutDown[g,1] == 0)
@constraint(model, constShutDn[g=1:N_GEN], genStartUp[g,1] == 0)

#Demand constraint
#for t in 1:N_HRS
@constraint(model, constDemand[t=1:N_HRS], sum(genOut[g, t] for g=1:N_GEN) == demand[t])
#end

#Power bounds
@constraint(model, constMaxPow[t=1:N_HRS, g=1:N_GEN],  genOut[g,t] <= maxPowerOut[g]*genOnOff[g,t] )
@constraint(model, constMinPow[t=1:N_HRS, g=1:N_GEN],  genOut[g,t] >= minPowerOut[g]*genOnOff[g,t] )

#Logical Conditions
@constraint(model, constLog1[t=2:N_HRS, g=1:N_GEN], (genStartUp[g,t] - genShutDown[g,t]) == (genOnOff[g,t] - genOnOff[g,t-1]))
@constraint(model, constLog2[t=1:N_HRS, g=1:N_GEN], genStartUp[g,t] + genShutDown[g, t] <= 1)

#Ramp limits
@constraint(model, constRampUp[t=2:N_HRS, g=1:N_GEN], genOut[g,t] - genOut[g,t-1] <= rampUpLimit[g]*genOnOff[g, t-1] + rampStartUpLimit[g]*genStartUp[g,t])
@constraint(model, constRampDown[t=2:N_HRS, g=1:N_GEN], (genOut[g,t-1] - genOut[g,t]) <= (rampDownLimit[g]*genOnOff[g,t] + rampShutDownLimit[g]*genShutDown[g,t]))

#Reserves
@constraint(model, constReserves[t=1:N_HRS], sum(maxPowerOut[g]*genOnOff[g,t] for g=1:N_GEN) >= (demand[t] + reserves[t]))

optimize!(model)

println("------------------------------------")
println("------- Optimal Solutions -------")
for g=1:N_GEN
  for t=1:N_HRS
    print(JuMP.value(genOut[g,t]),"\t")
  end
  println("\t Generator: $g")
end

println("------------------------------------")
println("------- GENERATORS COMMITED --------")

for g=1:N_GEN
  for t=1:N_HRS
    print(JuMP.value(genOnOff[g,t]),"\t")
  end
  println("\t Generator: $g")
end
