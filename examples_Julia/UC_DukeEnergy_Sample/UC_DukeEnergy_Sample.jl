#Reference: https://jump.dev/JuMP.jl/0.17/refexpr.html
using CSV, DelimitedFiles, DataFrames
using JuMP, CPLEX

#Preparing optimization model
model = Model(CPLEX.Optimizer)
set_optimizer_attribute(model, "CPX_PARAM_EPINT", 1e-5)

const N_GEN = 145
const N_HRS = 24

dfGenerator = CSV.read(".//inputs//data_generators.csv", DataFrame)
dfDemand = CSV.read(".//inputs//demand_reserves.csv", DataFrame)

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
@constraint(model, constDemand[t=1:N_HRS], sum(genOut[g, t] for g=1:N_GEN) == dfDemand.Demand[t])
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
@constraint(model, constReserves[t=1:N_HRS], sum(dfGenerator.MaxPowerOut[g]*genOnOff[g,t] for g=1:N_GEN) >= (dfDemand.Demand[t] + dfDemand.Reserves[t]))

mystatus = optimize!(model)

println("------------------------------------")
println("------- TERMINATION STATUS -------")
if termination_status(model) == MOI.OPTIMAL
    optimal_solution = value.(genOnOff)
    optimal_objective = objective_value(model)
    println("Optimal result")
elseif termination_status(model) == MOI.TIME_LIMIT && has_values(model)
    suboptimal_solution = value.(genOnOff)
    suboptimal_objective = objective_value(model)
    println("Time limit was exceeded")
else
    error("The model was not solved correctly.")
end


#Printing general results
println("------------------------------------")
println("------- OBJECTIVE VALUE -------")
println("Objective value: ", JuMP.objective_value(model))

println("------------------------------------")
println("------- PRIMAL STATUS -------")
println(primal_status(model))

println("------------------------------------")
println("------- DUAL STATUS -------")
println(JuMP.dual_status(model))

#Storing decision variables results
#Store whole model (TBD)
#write_to_file(model, ".//outputs//my_model.mps")
typeFileAccess = "w+"

open(".//outputs//resultsGenOut.csv", typeFileAccess) do io
           #writedlm(io, [x y], ',')
           writedlm(io,  JuMP.value.(genOut), ',')
    end;

open(".//outputs//resultsGenCommit.csv", typeFileAccess) do io
               #writedlm(io, [x y], ',')
               writedlm(io, JuMP.value.(genOnOff), ',')
         end;

open(".//outputs//resultsGenStartUp.csv", typeFileAccess) do io
              #writedlm(io, [x y], ',')
              writedlm(io, JuMP.value.(genStartUp), ',')
        end;

open(".//outputs//resultsGenShutDown.csv", typeFileAccess) do io
              #writedlm(io, [x y], ',')
              writedlm(io, JuMP.value.(genShutDown), ',')
        end;

println("------------------------------------")
println("------- OPTIMAL SOLUTION -------")
num_print_hrs = min(10, N_HRS)
num_print_gen = min(20, N_GEN)

for t=1:num_print_hrs
  print("Hour ", t-1, "\t")
end
println("")
for g=1:num_print_gen
  for t=1:num_print_hrs
    print(round(JuMP.value(genOut[g,t]); digits=2 ),"\t")
  #  println(round(pi; digits = 3))

  end
  println("\t Generator: $g")
end

println("------------------------------------")
println("------- GENERATORS COMMITED --------")
for t=1:num_print_hrs
  print("Hour ", t-1, "\t")
end

for g=1:num_print_gen
  for t=1:num_print_hrs
    #print(JuMP.value(genOnOff[g,t]),"\t")
    print(convert(Int32, JuMP.value(genOnOff[g,t])),"\t")
  end
  println("\t Generator: $g")
end

println("-------------------------------")
println("----------LAST DAY GEN OFF/ON---------")
print(JuMP.value.(genOnOff[:,end]))


println("-------------------------------")
#Clean memory
GC.gc()
