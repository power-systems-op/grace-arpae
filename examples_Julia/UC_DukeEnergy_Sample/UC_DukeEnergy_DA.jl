"""
This algorithm evaluate and solve the Unit Commitment optimization.



Author: Mauricio Hernandez
Date: 12/15/2020
...
# Arguments
- `filePath::String`: the path if the CSV files with the generators information.
...

# Examples
```julia-repl
julia> solveUC("File name")
"Unit Commitment was solved correctly"
```
"""

"""
```math
f(a) = αβ∑_{1}^{2}
```
"""

#Reference: https://jump.dev/JuMP.jl/0.17/refexpr.html
using CSV, DelimitedFiles, DataFrames
using JuMP, CPLEX
using BenchmarkTools, Logging

const N_GEN = 145
const N_HRS = 24
const INITIAL_DAY = 1
const FINAL_DAY = 1

# Open a textfile for writing

io_log = open(".//outputs//log.txt", "w+")
logger = SimpleLogger(io_log)
flush(io_log)
#logger = SimpleLoger(io_log)
global_logger(logger)

@info("Log file for UC model for $N_GEN generators")

#Preparing optimization model

dfGenerator = CSV.read(".//inputs//data_generators.csv", DataFrame)
dfDemand = CSV.read(".//inputs//demand_reserves.csv", DataFrame)

@info("Data from generators and demand downloaded correcly")

typeFileAccess = "w+";


for day in INITIAL_DAY:FINAL_DAY
    println("Solving day: $day")
    println("---------------------------")

    dfDayDemand = dfDemand[(day-1)*N_HRS+1:(N_HRS*day)+1, [:Hour, :Demand, :Reserves]];

    pathTempDemandFile = string(".//outputs//demandTEMP_day", day, ".csv");
    CSV.write(pathTempDemandFile, dfDayDemand)

    model = Model(CPLEX.Optimizer)
    set_optimizer_attribute(model, "CPX_PARAM_EPINT", 1e-4)

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
    @constraint(model, constDemand[t=1:N_HRS], sum(genOut[g, t] for g=1:N_GEN) == dfDayDemand.Demand[t])

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

    write(io_log, "Optimization Execution for day $day: \n")
    @info "Time elapsed (s):" @elapsed optimize!(model);

    println("------------------------------------")
    println("------- TERMINATION STATUS -------")
    if termination_status(model) == MOI.OPTIMAL
        #optimal_solution = value.(genOnOff)
        @info "Optimization objective: " optimal_objective = JuMP.objective_value(model)
        println("Optimal result")
    elseif termination_status(model) == MOI.TIME_LIMIT && has_values(model)
        #suboptimal_solution = value.(genOnOff)
        suboptimal_objective = JuMP.objective_value(model)
        println("Time limit was exceeded")
    else
        error("The model was not solved correctly.")
    end

    #Printing general results
    println("------------------------------------")
    println("------- OBJECTIVE VALUE -------")
    println("Objective value for day $day: ", JuMP.objective_value(model))

    println("------------------------------------")
    println("------- PRIMAL STATUS -------")
    println(primal_status(model))

    println("------------------------------------")
    println("------- DUAL STATUS -------")
    println(JuMP.dual_status(model))

    println("Day: $day solved")
    println("---------------------------")

    #Storing decision variables results
    open(".//outputs//resultsObjective.csv", typeFileAccess) do io
               write(io,  string("Objective value for day: ", day, ",", JuMP.objective_value(model), "/n"))
               close(io)
        end;

    open(".//outputs//resultsGenOut.csv", typeFileAccess) do io
               writedlm(io,  transpose(JuMP.value.(genOut)), ',')
        end;

    open(".//outputs//resultsGenCommit.csv", typeFileAccess) do io
                   writedlm(io, transpose(JuMP.value.(genOnOff)), ',')
             end;

    open(".//outputs//resultsGenStartUp.csv", typeFileAccess) do io
                  writedlm(io, transpose(JuMP.value.(genStartUp)), ',')
            end;

    open(".//outputs//resultsGenShutDown.csv", typeFileAccess) do io
                  writedlm(io, transpose(JuMP.value.(genShutDown)), ',')
             end;

#=    arrGenOnOff = JuMP.value.(genOnOff)
    println("Type JuMP.value.(genOnOff)")
    println(typeof(arrGenOnOff))
    println("Number of columns")
    println(size(arrGenOnOff,2))
    println("DF Generator Size")
    println(size(JuMP.value.(genOnOff)))
    println("JuMP.value.(genOnOff) first column size")
    println(size(JuMP.value.(genOnOff)[:,size(arrGenOnOff,2)]))
=#
    dfGenerator.Uini = JuMP.value.(genOnOff)[:,size(JuMP.value.(genOnOff),2)]

  global typeFileAccess = "a+";
end

#close(ioGenOut)
#Releasing memory
GC.gc();
close(io_log);
