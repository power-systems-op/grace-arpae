#using Queryverse
using XLSX
using DataFrames
using Dates
using DelimitedFiles
using CSV

# Parameters

const N_Gens =  132 # number of conventional generators
const N_StorgUs = 2 # number of storage units
const N_Zones = 2
const M_Zones = 2
const N_Blocks =7
const INITIAL_DAY = 1
const FINAL_DAY = 3
const INITIAL_HR_FUCR = 6 # represents the running time for the first WA unit commitment run. INITIAL_HR_FUCR=0 means the FUCR's optimal outcomes are ready at 00:00
const INITIAL_HR_SUCR = 17 # represents the running time for the second WA unit commitment run. INITIAL_HR_SUCR=17 means the SUCR's optimal outcomes are ready at 17:00
const N_Hrs_FUCR = 162 # N_Hrs_FUCR = 168-INITIAL_HR_FUCR, and INITIAL_HR_FUCR runs from 0 to 23; INITIAL_HR_FUCR=6 ==> N_Hrs_FUCR =162
const N_Hrs_SUCR = 151  # N_Hrs_SUCR = 168-INITIAL_HR_SUCR, and INITIAL_HR_SUCR runs from 17 to 23; INITIAL_HR_SUCR=17 ==> N_Hrs_FUCR =168

const FILE_ACCESS_OVER = "w+"
const FILE_ACCESS_APPEND = "a+"

##
########################### Importing input data from the input spreadsheets
# Generators' specification
# Logging file
io_log = open(
    string(
        ".//outputs//log//ReadInputs_",
        Dates.format(now(), "yyyy-mm-dd_HH-MM-SS"),
        ".txt",
    ),
    FILE_ACCESS_APPEND,
)

t1 = time_ns()

DF_Generators = CSV.read(".//inputs//csv//data_generators.csv", DataFrame);
Map_Gens = readdlm(".//inputs//csv//location_generators.csv", ','; header = true);
DF_Storage = CSV.read(".//inputs//csv//data_storage.csv", DataFrame);
Map_Storage = readdlm(".//inputs//csv//location_storage.csv", ','; header = true);

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

tranC = readdlm(".//inputs//csv//LineCapacity.csv", ','; header = true);
tranS = readdlm(".//inputs//csv//LineSusceptance.csv", ','; header = true);
reserve_reqs = readdlm(".//inputs//csv//data_reserve_reqs.csv", ','; header = true);

fuelPrice = readdlm(".//inputs//csv//data_fuel_price.csv", ','; header = true);

fuelPrice_head = fuelPrice[2];
fuelPrice = fuelPrice[1];
fuelPrice = fuelPrice[2:N_Gens+1, 4:368];
#FuelPrice = XLSX.readdata(".\\inputs\\data_generators.XLSX", "data_fuel_price", "D3:ND134")

# Reorganize data
FUCR_Demands_head = FUCR_Demands[2];
FUCR_Demands = FUCR_Demands[1];
FUCR_Demands = FUCR_Demands[1:53999, 4:(4+N_Zones-1)];

SUCR_Demands_head = SUCR_Demands[2];
SUCR_Demands = SUCR_Demands[1];
SUCR_Demands = SUCR_Demands[1:53999, 4:(4+N_Zones-1)];

BUCR_Demands_head = BUCR_Demands[2];
BUCR_Demands = BUCR_Demands[1];
BUCR_Demands = BUCR_Demands[1:7728, 3:(3+N_Zones-1)];

# Solar
FUCR_SolarGs_head = FUCR_SolarGs[2];
FUCR_SolarGs = FUCR_SolarGs[1];
FUCR_SolarGs = FUCR_SolarGs[1:7728, 3:(3+N_Zones-1)];

SUCR_SolarGs_head = SUCR_SolarGs[2];
SUCR_SolarGs = SUCR_SolarGs[1];
SUCR_SolarGs = SUCR_SolarGs[1:7728, 3:(3+N_Zones-1)];

BUCR_SolarGs_head = BUCR_SolarGs[2];
BUCR_SolarGs = BUCR_SolarGs[1];
BUCR_SolarGs = BUCR_SolarGs[1:7728, 3:(3+N_Zones-1)];

#Wind
FUCR_WindGs_head = FUCR_WindGs[2];
FUCR_WindGs = FUCR_WindGs[1];
FUCR_WindGs = FUCR_WindGs[1:7728, 3:(3+N_Zones-1)];

SUCR_WindGs_head = SUCR_WindGs[2];
SUCR_WindGs = SUCR_WindGs[1];
SUCR_WindGs = SUCR_WindGs[1:7728, 3:(3+N_Zones-1)];

BUCR_WindGs_head = BUCR_WindGs[2];
BUCR_WindGs = BUCR_WindGs[1];
BUCR_WindGs = BUCR_WindGs[1:7728, 3:(3+N_Zones-1)];

#Hydro
FUCR_HydroGs_head = FUCR_HydroGs[2];
FUCR_HydroGs = FUCR_HydroGs[1];
FUCR_HydroGs = FUCR_HydroGs[1:7728, 2:(2+N_Zones-1)];

SUCR_HydroGs_head = SUCR_HydroGs[2];
SUCR_HydroGs = SUCR_HydroGs[1];
SUCR_HydroGs = SUCR_HydroGs[1:7728, 2:(2+N_Zones-1)];

BUCR_HydroGs_head = BUCR_HydroGs[2];
BUCR_HydroGs = BUCR_HydroGs[1];
BUCR_HydroGs = BUCR_HydroGs[1:7728, 2:(2+N_Zones-1)];

Map_Gens_head = Map_Gens[2];
Map_Gens = Map_Gens[1];
Map_Gens = Map_Gens[:,3:N_Zones+2]


Map_Storage_head = map_storage[2];
Map_Storage = Map_Storage[1];
Map_Storage = Map_Storage[:,2:N_Zones+1]
#map_storage = convert(Array{Int32,2}, map_storage[:,2:N_Zones+1]);

tranC_head = tranC[2];
tranC = tranC[1];
tranC = tranC[1:N_Zones,2:(2+N_Zones-1)];

tranS_head = tranS[2];
tranS = tranS[1];
tranS = tranS[1:N_Zones,2:(2+N_Zones-1)];

reserve_reqs_head = reserve_reqs[2];
reserve_reqs = reserve_reqs[1];
reserve_req_up = reserve_reqs
#reserve_req_dn = reserve_reqs[:,3];

##
# Importing input data from the input spreadsheets
# Generators' specification
#DF_Generators = DataFrame(XLSX.readtable(".\\inputs\\data_generators.XLSX", "data_generators")...)

# Generators location map: if a generator g is located in zone z Map_Gens[g,z]=1; and 0 otherwise
#DF_Map_Gens = DataFrame(XLSX.readtable(".\\inputs\\data_generators.XLSX", "location_generators")...)
#Map_Gens = convert(Matrix, DF_Map_Gens[:,3:N_Zones+2])

# Storage Units' specification and location
#DF_Storage = DataFrame(XLSX.readtable(".\\inputs\\data_storage.XLSX", "data_storage")...) # storage specs
#DF_Map_Storage = DataFrame(XLSX.readtable(".\\inputs\\data_storage.XLSX", "location_storage")...) # storage location as a dataframe
#Map_Storage = convert(Matrix, DF_Map_Storage[:,2:N_Zones+1]) # convert storage location data to  a matrix

# energy demand at each location
#DF_Dems = DataFrame(XLSX.readtable(".\\Inputs\\data_demand.XLSX", "data_demand")...)
#FUCR_Demands = XLSX.readdata(".\\inputs\\data_demand.XLSX", "data_demand", "D2:E54000")
#SUCR_Demands = XLSX.readdata(".\\inputs\\data_demand.XLSX", "data_demand_updated", "D2:E54000")
#BUCR_Demands = XLSX.readdata(".\\inputs\\data_demand.XLSX", "data_demand_actual", "C2:D7729")
# There is no map for the demand data. Instead we take the input demand data for each zone. In other words, Demand[t,z] represents demand at zone z and time t

# solar generation data at each location
#FUCR_SolarGs = XLSX.readdata(".\\inputs\\data_solar.XLSX", "data_solar", "C2:D7729")
#SUCR_SolarGs = XLSX.readdata(".\\inputs\\data_solar.XLSX", "data_solar_updated", "C2:D7729")
#BUCR_SolarGs = XLSX.readdata(".\\inputs\\data_solar.XLSX", "data_solar_actual", "C2:D7729")

# wind energy data for each location
#FUCR_WindGs = XLSX.readdata(".\\inputs\\data_wind.XLSX", "data_wind", "C2:D7729")
#SUCR_WindGs = XLSX.readdata(".\\inputs\\data_wind.XLSX", "data_wind_updated", "C2:D7729")
#BUCR_WindGs = XLSX.readdata(".\\inputs\\data_wind.XLSX", "data_wind_actual", "C2:D7729")

#hydro generation data for each location
#FUCR_HydroGs = XLSX.readdata(".\\inputs\\data_hydro.XLSX", "data_hydro", "B2:C7729")
#SUCR_HydroGs = XLSX.readdata(".\\inputs\\data_hydro.XLSX", "data_hydro_updated", "B2:C7729")
#BUCR_HydroGs = XLSX.readdata(".\\inputs\\data_hydro.XLSX", "data_hydro_actual", "B2:C7729")

#Zonal Reserve Targets
#Reserve_Req_Up = XLSX.readdata(".\\inputs\\data_reserve_reqs.XLSX", "data_reserve_reqs", "A2:B2")

# Transmission system data (Capacity and Susceptance)
#TranC = XLSX.readdata(".\\inputs\\data_tranSmission.XLSX", "LineCapacity","B2:C3") # Transmission line capacity
#TranS = XLSX.readdata(".\\inputs\\data_tranSmission.XLSX", "LineSusceptance","B2:C3")# Transmission line susceptance

# Daily Fuel Price data
#FuelPrice = XLSX.readdata(".\\inputs\\data_generators.XLSX", "data_fuel_price", "D3:ND134")

##
t2 = time_ns()
elapsedTime = (t2 -t1)/1.0e9;

write(io_log, "Whole program time execution (s):\t $elapsedTime\n")
close(io_log);
