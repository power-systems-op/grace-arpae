"""
This algorithm evaluate and solve the Unit Commitment optimization.

Author: Mauricio Hernandez
Date: 12/15/2020
References:
- https://jump.dev/JuMP.jl/0.17/refexpr.html

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

#
using CSV, DelimitedFiles, DataFrames
using JuMP, CPLEX
using BenchmarkTools, Logging, Dates

#Enabling debugging code, use ENV["JULIA_DEBUG"] = "" to desable Debugging code
ENV["JULIA_DEBUG"] = "all"

const N_GEN = 145
const N_HRS = 24
const INITIAL_DAY = 1
const FINAL_DAY = 1

#curentTime = Dates.format(now(), "yyyy-mm-dd_HH-MM-SS");
# Logging file
io_log = open(string(".//outputs//log//log_", Dates.format(now(), "yyyy-mm-dd_HH-MM-SS") ,".txt"), "w")
logger = SimpleLogger(io_log)
flush(io_log)

global_logger(logger)

@info("Log file for UC model for $N_GEN generators")

#Loading input data
dfGenerator = CSV.read(".//inputs//data_generators.csv", DataFrame)
dfDemand = CSV.read(".//inputs//demand_reserves.csv", DataFrame)

@info("Data from generators and demand downloaded correcly")

typeFileAccess = "w+";

t1 = time_ns()
@time begin
for day in INITIAL_DAY:FINAL_DAY
    println("---------------------------")
    @info println("Solving UC for day: $day")
    println("---------------------------")

    dfDayDemand = dfDemand[(day-1)*N_HRS+1:(N_HRS*day)+1, [:Hour, :Demand, :Reserves]];

    @debug begin
      pathTempDemandFile = string(".//outputs//demandTEMP_day", day, ".csv");
      CSV.write(pathTempDemandFile, dfDayDemand)
    end

    model = Model(CPLEX.Optimizer)
    set_optimizer_attribute(model, "CPX_PARAM_EPINT", 1e-5)

    @variable(model, genOnOff[1:N_GEN, 1:N_HRS], Bin)
    @variable(model, genOut[1:N_GEN, 1:N_HRS] >= 0) # Power bound constraint Equation 4
    @variable(model, genStartUp[1:N_GEN, 1:N_HRS], Bin)
    @variable(model, genShutDown[1:N_GEN, 1:N_HRS], Bin)

    #Setting objective function
    @objective(model, Min, sum(sum(dfGenerator.FixedCost[g]*genOnOff[g,t] + dfGenerator.VariableCost[g]*genOut[g,t] +
               dfGenerator.StartUpCost[g]*genStartUp[g,t] + dfGenerator.ShutdownCost[g]*genShutDown[g, t] for g in 1:N_GEN)
               for t in 1:N_HRS) )


    #Generators should have an initial and defined value at t=0
    @constraint(model, conInit[g=1:N_GEN], genOnOff[g,1] == dfGenerator.Uini[g])

    #Initial values of Generator shutdown and startup values should be defined
    if day == 1
      @constraint(model, conShutDn[g=1:N_GEN], genShutDown[g,1] == 0)
      @constraint(model, conShutUp[g=1:N_GEN], genStartUp[g,1] == 0)
    end

    #Logical Conditions
    @constraint(model, conLogical[t=1:N_HRS, g=1:N_GEN], genStartUp[g,t] + genShutDown[g, t] <= 1)

    #Start-up and Shut-down - Equation 3
    @constraint(model, conStartUpAndDn[t=2:N_HRS, g=1:N_GEN], (genStartUp[g,t] - genShutDown[g,t]) ==
               (genOnOff[g,t] - genOnOff[g,t-1]))


    #Power bounds - Equation 4
    @constraint(model, conMaxPow[t=1:N_HRS, g=1:N_GEN],  genOut[g,t] <= dfGenerator.MaxPowerOut[g]*genOnOff[g,t] )
    @constraint(model, conMinPow[t=1:N_HRS, g=1:N_GEN],  genOut[g,t] >= dfGenerator.MinPowerOut[g]*genOnOff[g,t] )

    #Ramping limits
    #Ramp Up - Equation 5
    @constraint(model, conRampUp[t=2:N_HRS, g=1:N_GEN], genOut[g,t] - genOut[g,t-1] <=
                dfGenerator.RampUpLimit[g]*genOnOff[g, t-1] + dfGenerator.RampStartUpLimit[g]*genStartUp[g,t])
    if day == 1
        @constraint(model, conIniRampUp[g=1:N_GEN], genOut[g,1] - dfGenerator.PowerIni[g] <=
                dfGenerator.RampUpLimit[g]*dfGenerator.Uini[g] + dfGenerator.RampStartUpLimit[g]*genStartUp[g,1])
    end

    #Ramp Down - Equation 6
    @constraint(model, conRampDown[t=2:N_HRS, g=1:N_GEN], (genOut[g,t-1] - genOut[g,t]) <=
               (dfGenerator.RampDownLimit[g]*genOnOff[g,t] + dfGenerator.RampShutDownLimit[g]*genShutDown[g,t]))

   if day == 1
      @constraint(model, conIniRampDown[g=1:N_GEN], dfGenerator.PowerIni[g] - genOut[g,1]  <=
              dfGenerator.RampDownLimit[g]*genOnOff[g,1] + dfGenerator.RampShutDownLimit[g]*genShutDown[g,1])
   end

    #Power balance - Equation 7
    @constraint(model, conDemand[t=1:N_HRS], sum(genOut[g, t] for g=1:N_GEN) == dfDayDemand.Demand[t])

    #Reserves - Equation 8
    @constraint(model, conReserves[t=1:N_HRS], sum(dfGenerator.MaxPowerOut[g]*genOnOff[g,t] for g=1:N_GEN) >= (dfDayDemand.Demand[t] + dfDayDemand.Reserves[t]))



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
        close(io_log)
    else
        error("The model was not solved correctly.")
        close(io_log)
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
end #time
#close(ioGenOut)
#Releasing memory

t2 = time_ns()
elapsedTime = (t2 -t1)/1.0e9;
@info "UC Optimization solved in (s):" elapsedTime = (t2 -t1)/1.0e9;

GC.gc();
close(io_log);
