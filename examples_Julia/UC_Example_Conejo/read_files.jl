using DataFrames
using CSV, DelimitedFiles

struct Generator
    Unit::Array{Float64}
    FixedCost::Array{Float64}
    VariableCost::Array{Float64}
    StartUpCost::Array{Float64}
    ShutdownCost::Array{Float64}
    MinPowerOut::Array{Float64}
    MaxPowerOut::Array{Float64}
    RampDownLimit::Array{Float64}
    RampShutDownLimit::Array{Float64}
    RampUpLimit::Array{Float64}
    RampStartUpLimit::Array{Float64}
    Uini::Array{Float64}
end


struct XGenerator
    Unit::Float64
    FixedCost::Float64
    VariableCost::Float64
    StartUpCost::Float64
    ShutdownCost::Float64
    MinPowerOut::Float64
    MaxPowerOut::Float64
    RampDownLimit::Float64
    RampShutDownLimit::Float64
    RampUpLimit::Float64
    RampStartUpLimit::Float64
    Uini::Float64
end

struct YGenerator
    Unit::Float64
    FixedCost::Float64
end

@timev dataGenerator = CSV.read("data_generators.csv", DataFrame)
@timev dataDemand = CSV.read("data_generators.csv", DataFrame)

println(df);

@timev data_generators = DelimitedFiles.readdlm("data_generators.csv", ',', header=true, Float64);
@timev data_demand = DelimitedFiles.readdlm("demand_reserves.csv", ',', header=true, Float64);

#println(data_generators)
#println(data_demand)

generators = data_generators[1]

#Generator 1
println("Size of generators[1,:]", size(generators) )

println(generators[1,:])
mydata =[1.0 5.0 0.1 20.0 0.5 50.0 350.0 300.0 300.0 200.0 200.0 0.0];
mydata2 =[1.0 5.0 0.1 20.0 0.5]
println("My data ",mydata[:, 1])

S = view(generators, 1:5)
println("S: ", S)

generator1 = YGenerator(1.0, 5.0)

println("Size of my data", size(mydata))
println("Size of my data2", size(mydata2))
