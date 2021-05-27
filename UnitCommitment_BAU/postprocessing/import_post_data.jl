

df_gens = CSV.read(".//inputs//data_generators.csv", header=true, DataFrame);
df_peakers = CSV.read(".//inputs//data_peakers.csv", header=true, DataFrame);
df_fuel_gens = CSV.read(".//inputs//data_fuel_price.csv", header=true, DataFrame);
df_fuel_peakers = CSV.read(".//inputs//data_fuel_price_peakers.csv", header=true, DataFrame);
# Reads the schedules into a dataframe
df_gen_sch = CSV.read(".//inputs//UnitSchedule_(DEC-DEP 2019).csv",
                  dateformat="mm-dd-yyyy THH:MM:SS.000Z", header=true, copycols=true, DataFrame);

df_nox_winter = CSV.read(".//inputs//NOX_Breakpoints_Winter_Results.csv",
                  header=true, copycols=true, DataFrame);

df_so2_winter = CSV.read(".//inputs//SO2_Breakpoints_Winter_Results.csv",
            header=true, copycols=true, DataFrame);


# Source: https://www.eia.gov/electricity/annual/
df_eia_co2 = CSV.read(".//inputs//eia_co2_emiss_per_mmbtu.csv", header=true, DataFrame);

select!(df_gens, Not(:Cogen));
