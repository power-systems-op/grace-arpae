#Reference: https://jump.dev/JuMP.jl/0.17/refexpr.html
using CSV, DelimitedFiles, DataFrames

const N_GEN = 144
const N_HRS = 100

const NUCLEAR_CAPACITY = 11463.10 # in MW
const NUCLEAR_CF = 0.87 # Reported in Bandar's Paper

dfDemand = CSV.read(".//inputs//demand_reserves.csv", DataFrame)

dfDemand.DemandNode01 = dfDemand.DemandNode01 - NUCLEAR_CF * NUCLEAR_CF
