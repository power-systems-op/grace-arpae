using CSV
using DataFrames
using DelimitedFiles

include("constants.jl")

path_dat = "C://Users//rapiduser//Documents//GitHub//grace-arpae//UnitCommitment_BAU"
cd(path_dat)

##
# Importing input data from the input spreadsheets
# Generators' specifications
DF_Generators = CSV.read(".//inputs//csv//data_generators.csv", DataFrame);
# Generators location map: if a generator g is located in zone z Map_Gens[g,z]=1; and 0 otherwise
Map_Gens = readdlm(".//inputs//csv//location_generators.csv", ','; header = true);

#Peaker Units' specifications and location
DF_Peakers = CSV.read(".//inputs//csv//data_peakers.csv", DataFrame);
# Peakers location map: if a peaker p is located in zone z Map_Gens[p,z]=1; # and 0 otherwise
Map_Peakers = readdlm(".//inputs//csv//location_peakers.csv", ','; header = true);

# Storage Units' specification and location
DF_Storage = CSV.read(".//inputs//csv//data_storage.csv", DataFrame);
Map_Storage = readdlm(".//inputs//csv//location_storage.csv", ','; header = true);

# Energy demand at each location
FUCR_Demands = readdlm(".//inputs//csv//data_demand.csv", ','; header = true);
SUCR_Demands = readdlm(".//inputs//csv//data_demand_updated.csv", ','; header = true);
BUCR_Demands = readdlm(".//inputs//csv//data_demand_actual.csv", ','; header = true);

# solar generation data at each location
FUCR_SolarGs = readdlm(".//inputs//csv//data_solar.csv", ','; header = true);
SUCR_SolarGs = readdlm(".//inputs//csv//data_solar_updated.csv", ','; header = true);
BUCR_SolarGs = readdlm(".//inputs//csv//data_solar_actual.csv", ','; header = true);

# wind energy data for each location
FUCR_WindGs = readdlm(".//inputs//csv//data_wind.csv", ','; header = true);
SUCR_WindGs = readdlm(".//inputs//csv//data_wind_updated.csv", ','; header = true);
BUCR_WindGs = readdlm(".//inputs//csv//data_wind_actual.csv", ','; header = true);

#hydro generation data for each location
FUCR_HydroGs = readdlm(".//inputs//csv//data_hydro.csv", ','; header = true);
SUCR_HydroGs = readdlm(".//inputs//csv//data_hydro_updated.csv", ','; header = true);
BUCR_HydroGs = readdlm(".//inputs//csv//data_hydro_actual.csv", ','; header = true);

#nuclear generation timeseries for each location
FUCR_NuclearGs = readdlm(".//inputs//csv//data_nuclear.csv", ','; header = true);
SUCR_NuclearGs = readdlm(".//inputs//csv//data_nuclear_updated.csv", ','; header = true);
BUCR_NuclearGs = readdlm(".//inputs//csv//data_nuclear_actual.csv", ','; header = true);

#Cogenerators' generation timeseries for each location
FUCR_CogenGs = readdlm(".//inputs//csv//data_cogen.csv", ','; header = true);
SUCR_CogenGs = readdlm(".//inputs//csv//data_cogen_updated.csv", ','; header = true);
BUCR_CogenGs = readdlm(".//inputs//csv//data_cogen_actual.csv", ','; header = true);

TranC = readdlm(".//inputs//csv//LineCapacity.csv", ','; header = true);
TranS = readdlm(".//inputs//csv//LineSusceptance.csv", ','; header = true);
Reserve_Reqs = readdlm(".//inputs//csv//data_reserve_reqs.csv", ','; header = true);

FuelPrice = readdlm(".//inputs//csv//data_fuel_price.csv", ','; header = true);
FuelPricePeakers = readdlm(".//inputs//csv//data_fuel_price_peakers.csv", ','; header = true);

FuelPrice_head = FuelPrice[2];
FuelPrice = FuelPrice[1];
FuelPrice = FuelPrice[2:GENS+1, 4:368];

FuelPricePeakers_head = FuelPricePeakers[2];
FuelPricePeakers = FuelPricePeakers[1];
FuelPricePeakers = FuelPricePeakers[2:PEAKERS+1, 4:368];

# Reorganize data
FUCR_Demands_head = FUCR_Demands[2];
FUCR_Demands = FUCR_Demands[1];
FUCR_Demands = Array{Int64}(FUCR_Demands[1:60313, 4:(4+N_ZONES-1)]);

SUCR_Demands_head = SUCR_Demands[2];
SUCR_Demands = SUCR_Demands[1];
SUCR_Demands = Array{Int64}(SUCR_Demands[1:60313, 4:(4+N_ZONES-1)]);

BUCR_Demands_head = BUCR_Demands[2];
BUCR_Demands = BUCR_Demands[1];
BUCR_Demands = BUCR_Demands[1:8760, 3:(3+N_ZONES-1)];
BUCR_Demands = Array{Int64}(BUCR_Demands);

# Solar
FUCR_SolarGs_head = FUCR_SolarGs[2];
FUCR_SolarGs = FUCR_SolarGs[1];
FUCR_SolarGs = Array{Int64}(FUCR_SolarGs[1:8760, 3:(3+N_ZONES-1)]);

SUCR_SolarGs_head = SUCR_SolarGs[2];
SUCR_SolarGs = SUCR_SolarGs[1];
SUCR_SolarGs = SUCR_SolarGs[1:8760, 3:(3+N_ZONES-1)];
SUCR_SolarGs = Array{Int64}(SUCR_SolarGs);

BUCR_SolarGs_head = BUCR_SolarGs[2];
BUCR_SolarGs = BUCR_SolarGs[1];
BUCR_SolarGs = Array{Int64}(BUCR_SolarGs[1:8760, 3:(3+N_ZONES-1)]);

#Wind
FUCR_WindGs_head = FUCR_WindGs[2];
FUCR_WindGs = FUCR_WindGs[1];
FUCR_WindGs = Array{Int64}(FUCR_WindGs[1:8760, 3:(3+N_ZONES-1)]);

SUCR_WindGs_head = SUCR_WindGs[2];
SUCR_WindGs = SUCR_WindGs[1];
SUCR_WindGs = Array{Int64}(SUCR_WindGs[1:8760, 3:(3+N_ZONES-1)]);

BUCR_WindGs_head = BUCR_WindGs[2];
BUCR_WindGs = BUCR_WindGs[1];
BUCR_WindGs = Array{Int64}(BUCR_WindGs[1:8760, 3:(3+N_ZONES-1)]);

#Hydro
FUCR_HydroGs_head = FUCR_HydroGs[2];
FUCR_HydroGs = FUCR_HydroGs[1];
FUCR_HydroGs = Array{Int64}(FUCR_HydroGs[1:8760, 2:(2+N_ZONES-1)]);

SUCR_HydroGs_head = SUCR_HydroGs[2];
SUCR_HydroGs = SUCR_HydroGs[1];
SUCR_HydroGs = Array{Int64}(SUCR_HydroGs[1:8760, 2:(2+N_ZONES-1)]);

BUCR_HydroGs_head = BUCR_HydroGs[2];
BUCR_HydroGs = BUCR_HydroGs[1];
BUCR_HydroGs = Array{Int64}(BUCR_HydroGs[1:8760, 2:(2+N_ZONES-1)]);

#Nuclear
FUCR_NuclearGs_head = FUCR_NuclearGs[2];
FUCR_NuclearGs = FUCR_NuclearGs[1];
FUCR_NuclearGs = Array{Int64}(FUCR_NuclearGs[1:8760, 3:(3+N_ZONES-1)]);

SUCR_NuclearGs_head = SUCR_NuclearGs[2];
SUCR_NuclearGs = SUCR_NuclearGs[1];
SUCR_NuclearGs = Array{Int64}(SUCR_NuclearGs[1:8760, 3:(3+N_ZONES-1)]);

BUCR_NuclearGs_head = BUCR_NuclearGs[2];
BUCR_NuclearGs = BUCR_NuclearGs[1];
BUCR_NuclearGs = Array{Int64}(BUCR_NuclearGs[1:8760, 3:(3+N_ZONES-1)]);

#Cogen
FUCR_CogenGs_head = FUCR_CogenGs[2];
FUCR_CogenGs = FUCR_CogenGs[1];
FUCR_CogenGs = Array{Int64}(FUCR_CogenGs[1:8760, 3:(3+N_ZONES-1)]);

SUCR_CogenGs_head = SUCR_CogenGs[2];
SUCR_CogenGs = SUCR_CogenGs[1];
SUCR_CogenGs = Array{Int64}(SUCR_CogenGs[1:8760, 3:(3+N_ZONES-1)]);

BUCR_CogenGs_head = BUCR_CogenGs[2];
BUCR_CogenGs = BUCR_CogenGs[1];
BUCR_CogenGs = Array{Int64}(BUCR_CogenGs[1:8760, 3:(3+N_ZONES-1)]);

Map_Gens_head = Map_Gens[2];
Map_Gens = Map_Gens[1];
Map_Gens = Array{Int64}(Map_Gens[:,3:N_ZONES+2]);

Map_Peakers_head = Map_Peakers[2];
Map_Peakers = Map_Peakers[1];
Map_Peakers = Array{Int64}(Map_Peakers[:,3:N_ZONES+2]);

Map_Storage_head = Map_Storage[2];
Map_Storage = Map_Storage[1];
Map_Storage = Array{Int64}(Map_Storage[:,2:N_ZONES+1])

TranC_head = TranC[2];
TranC = TranC[1];
TranC = Array{Float64}(TranC[1:N_ZONES,2:(2+N_ZONES-1)]);

TranS_head = TranS[2];
TranS = TranS[1];
TranS = Array{Float64}(TranS[1:N_ZONES,2:(2+N_ZONES-1)]);

Reserve_Reqs_head = Reserve_Reqs[2];
Reserve_Reqs = Reserve_Reqs[1];
Reserve_Req_Up = Array{Float64}(Reserve_Reqs)
