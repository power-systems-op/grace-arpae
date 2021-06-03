#using Queryverse
using DataFrames
using DataFramesMeta
using Dates
using DelimitedFiles
using JuMP
using Logging
using CSV
using Query
using Statistics

# Parameters
const N_Gens =  64 # number of conventional generators
const N_Peakers =  80 # number of conventional generators
const N_StorgUs = 8 # number of storage units
const N_Blocks =7

const FILE_ACCESS_OVER = "w+"
const FILE_ACCESS_APPEND = "a+"
const POUNDS_TO_KG = 0.45359237

include("import_post_data.jl")

""""
Generators cost of unit i (variable cost)
Cost Unitᵢ[USD]= Avg. heat rate[mmbtu/MWh] * Avg. Fuel Price [USD/mmbtu] * Power Out[MWh]

    Power Out is obtained from:
    - UnitSchedule_(DEC-DEP 2019).csv

    Average Fuel Price is estimated from the data in the files:
    - data_fuel_price.csv & df_fuel_peakers.csv
    (both files are used as inputs of the UC model and the data comes from the
    files provided by Duke Energy, files UNIT_FUEL_PRICE(DEC 2019).csv and
    UNIT_FUEL_PRICE(DEP 2019).csv)

    Average heat rate is estimated from the data in the files:
    - df_gens.csv and df_peakers2.csv
    (both files are used as inputs of the UC model and the data comes from the
    files provided by Duke Energy, HR_Breakpoints_Summer_DEC-DEP_(2019) V2.csv &
    HR_Breakpoints_Winter_DEC-DEP_(2019) V2.csv)`

Parameters:
    df_gens:
    df_peakers:
    df_fuel_gens:
    df_fuel_peakers:
    df_gen_sch:
    ini_date: String with dateformat format 'MM/DD/YYYY HH:MM:SS', inclusive
    end_date: String with dateformat format 'MM/DD/YYYY HH:MM:SS', inclusive
"""
#TODO: Add summer data
function calc_model_costs(df_gens::DataFrame, df_peakers::DataFrame, df_fuel_gens::DataFrame,
    df_fuel_peakers::DataFrame, df_gen_sch::DataFrame, ini_date::String, end_date::String)

    #Combines the slow generators and peakers specs into one dataframe
    df_gens_all = vcat(df_gens, df_peakers);
    # Add the average heat rate data to the all gens' specs dataframe
    df_gens_all.Avg_HR =(df_gens_all.IHRC_B1_HR+df_gens_all.IHRC_B2_HR +
        df_gens_all.IHRC_B3_HR+df_gens_all.IHRC_B4_HR+df_gens_all.IHRC_B5_HR +
        df_gens_all.IHRC_B6_HR+df_gens_all.IHRC_B7_HR) / 7.0;

    #Combines the slow generators and peakers fuel data into one dataframe
    df_fuel_all = vcat(df_fuel_gens, df_fuel_peakers);
    # Adds the average fuel price to the fuel price dataframe as a new column
    insertcols!(df_fuel_all, 4, :avg_fuelprice => zeros(Float64), makeunique=true);

    #TODO: Check if instead of getting an average fuel price for the whole year
    # we could use  daily prices

    # Create a matrix of fuel prices to estimate the avg price and use it for cost calculatrion
    mat_fuelprice = Matrix(df_fuel_all[:,4:368]);
    avg_fuelprice = mean(mat_fuelprice, dims=2);
    df_avg_fuelprice = DataFrame(avg_fuelprice);

    rename!(df_avg_fuelprice,:x1 => :Avg_FP)
    df_fp_all = hcat(df_fuel_all, df_avg_fuelprice)

    # Adds the UNIT_ID that includes the cc key to the fuel price dataframe as a new column
    insertcols!(df_fp_all, 2, :UNIT_NAME => "", makeunique=true);

    for j in eachrow(df_fp_all)
        Idk = findall(x -> x == j.Column2, vec(df_gens_all.UNIT_ID));
        if isempty(Idk) == false
            j.UNIT_NAME = df_gens_all.UNIT_NAME[Idk[1]];
        end
    end

    # Filtering the Actual generation outcomes from UNIT_Schedules.csv
    # Reformats the date-time data given in column DATE
    #df_gen_sch.DATE = DateTime.(df_gen_sch.DATE, "mm/dd/yyyy HH:MM:SS p");

    # Call function
    #Selects a subset of schedules that fall into the months that users specify.
    # @where could be extended to include other month using the OR operation (||)
    ini_date = DateTime(ini_date, "mm/dd/yyyy HH:MM:SS");
    end_date = DateTime(end_date, "mm/dd/yyyy HH:MM:SS");

    df_convgen_sch = @from i in df_gen_sch begin
                @where DateTime(i.DATE) >= ini_date && DateTime(i.DATE) <= end_date
                @select {i.DATE, i.UNIT_ID, i.Output, i.On_off, i.ShutDown, i.Startup}
                @collect DataFrame
           end

    insertcols!(df_convgen_sch, size(df_convgen_sch,2), :Avg_HR => zeros(Float64));
    insertcols!(df_convgen_sch, size(df_convgen_sch,2), :Avg_FP => zeros(Float64));
    insertcols!(df_convgen_sch, 3, :UNIT_NAME => "");
    insertcols!(df_convgen_sch, size(df_convgen_sch,2), :TYPE_MAIN_FUEL => "");

    for row in eachrow(df_convgen_sch)
          Idx = findall(x -> x == row.UNIT_ID, vec(df_gens_all.UNIT_ID));
          if isempty(Idx) == false
                row.Avg_HR = df_gens_all.Avg_HR[Idx[1]];
                row.UNIT_NAME = df_gens_all.UNIT_NAME[Idx[1]];
          end
    end

    for row in eachrow(df_convgen_sch)
          Idx = findall(x -> x == row.UNIT_NAME, vec(df_fp_all.UNIT_NAME));
          if isempty(Idx) == false
                row.Avg_FP = df_fp_all.Avg_FP[Idx[1]];
                row.TYPE_MAIN_FUEL = df_fp_all.Column3[Idx[1]]; # Column3 = type of main fuel
          end
    end

    insertcols!(df_convgen_sch, size(df_convgen_sch,2), :GenCost => df_convgen_sch[!,:Output] .*df_convgen_sch[!,:Avg_HR] .* df_convgen_sch[!,:Avg_FP]);

    return df_convgen_sch;
end; # end function


"""
CO₂ emissions [metric ton] = avg. heat rate[mmbtu/MWh] * CO₂ emissions rate[kg/mmbu] * Power Out[MWh] * 10⁻³
 The CO₂ factor was obtained from the EIA site:
 [https://www.eia.gov/electricity/annual/html/epa_a_03.html]
"""
function calc_model_CO₂_emissions(df_co2::DataFrame, df_gen::DataFrame)
    # Calculating CO2 emissions for Peakers and CC units
    tonCO2_mmbtu = (@where(df_co2, occursin("NG").(:Fuel_code)).KgCO2_MMBTU ) / 1000.0;

    ng_tonCO2_mmbtu = (@where(df_co2, occursin("NG").(:Fuel_code)).KgCO2_MMBTU) / 1000.0;
    coal_tonCO2_mmbtu = (@where(df_co2, occursin("BIT").(:Fuel_code)).KgCO2_MMBTU)/ 1000.0;
    oil_tonCO2_mmbtu = (@where(df_co2, occursin("DFO").(:Fuel_code)).KgCO2_MMBTU)/ 1000.0;

    insertcols!(df_gen, size(df_gen,2), :EmissCO2_ton => zeros(Float64));

    #Options: COAL, CoGen, NGAS, Nuclear, and LOIL
    for unit in eachrow(df_gen)
        if (unit.TYPE_MAIN_FUEL == "COAL")
            unit.EmissCO2_ton = unit.Avg_HR * coal_tonCO2_mmbtu[1] * unit.Output;
        elseif (unit.TYPE_MAIN_FUEL == "NGAS")
            unit.EmissCO2_ton = unit.Avg_HR  * ng_tonCO2_mmbtu[1] * unit.Output;
        elseif (unit.TYPE_MAIN_FUEL == "LOIL")
            unit.EmissCO2_ton = unit.Avg_HR  * oil_tonCO2_mmbtu[1] * unit.Output;
      end;
    end

    return df_gen;
end


"""
NOₓ emissions [kg] = avg. heat rate [mmbtu/MWh] * avg NOₓ [lb/mmbu] * power out [MWh] * conv factor[Kg/lb]

The NOₓ factor is estimated form the files:
    - NOX_Breakpoints_Winter_Results.csv
    (the data  in this file comes from the files provided by Duke Energy,
    HR_Breakpoints_Summer_DEC-DEP_(2019) V2.csv &
    HR_Breakpoints_Winter_DEC-DEP_(2019) V2.csv)
"""
#TODO: Add summer data
function calc_model_NOx_emissions(df_nox::DataFrame, df_gen::DataFrame)
    df_nox.Avg_NOX = (df_nox.IHRC_B1_NOX + df_nox.IHRC_B2_NOX +
            df_nox.IHRC_B3_NOX + df_nox.IHRC_B4_NOX +
            df_nox.IHRC_B5_NOX + df_nox.IHRC_B6_NOX +
            df_nox.IHRC_B7_NOX) / 7.0;

    insertcols!(df_gen, size(df_gen,2), :Avg_NOX => zeros(Float64));

    for i in eachrow(df_gen)
        Idx = findall(x -> x == i.UNIT_NAME, vec(df_nox.UNIT_NAME));
        if isempty(Idx) == false
            i.Avg_NOX = df_nox.Avg_NOX[Idx[1]] * POUNDS_TO_KG;
        end
    end

    #  NOx Emissions
    insertcols!(df_gen, size(df_gen,2), :EmissNOx_kg => df_gen[!,:Avg_HR] .* df_gen[!,:Avg_NOX] .* df_gen[!,:Output]);

    return df_gen;
end


"""
SO₂ emissions [kg] = Avg. heat rate[mmbtu/MWh] * SO₂ factor[kg/mmbu] * Power Out[MWh]
The SO₂ factor was obtained from the data provided by Duke Energy in the files:
    - SO2_Breakpoints_Winter_Results.csv
    (the data  in this file from the files provided by Duke Energy,
    HR_Breakpoints_Summer_DEC-DEP_(2019) V2.csv &
    HR_Breakpoints_Winter_DEC-DEP_(2019) V2.csv)
"""
#TODO: Add summer data
function calc_model_SO₂_emissions(df_so2::DataFrame, df_gen::DataFrame)
    df_so2.Avg_SO2 = (df_so2.IHRC_B1_SO2 + df_so2.IHRC_B2_SO2 +
                df_so2.IHRC_B3_SO2 + df_so2.IHRC_B4_SO2 +
                df_so2.IHRC_B5_SO2 + df_so2.IHRC_B6_SO2 +
                df_so2.IHRC_B7_SO2) / 7.0;

    insertcols!(df_gen, size(df_gen,2), :Avg_SO2 => zeros(Float64));
    for i in eachrow(df_gen)
        Idx = findall(x -> x == i.UNIT_NAME, vec(df_so2.UNIT_NAME));
        if isempty(Idx) == false
            i.Avg_SO2 = df_so2.Avg_SO2[Idx[1]] * POUNDS_TO_KG;
        end
    end

    insertcols!(df_gen, size(df_gen,2), :EmissSO2_kg => df_gen[!,:Avg_HR] .* df_gen[!,:Avg_SO2] .* df_gen[!,:Output]);

    return df_gen;
end

df_bucr_gens_out = CSV.read(".//outputs//BUCR_GenOutputs.csv", header=true, DataFrame);
df_bucr_peakers_out = CSV.read(".//outputs//BUCR_PeakerOutputs.csv", header=true, DataFrame);

df_bucr_all_out = vcat(df_bucr_gens_out, df_bucr_peakers_out);

df_bucr_all_out = vcat(df_bucr_gens_out, df_bucr_peakers_out);

sim_year = 2019;

base_date = DateTime(sim_year, 1, 1, 00, 00, 00);
insertcols!(df_bucr_all_out, 1, :DATE => base_date);

for row in eachrow(df_bucr_all_out)
      if row.Hour >= 24
                row.Day = row.Day + 1;
                row.Hour = row.Hour - 24;
      end
      row.DATE = (row.DATE + Dates.Hour(row.Hour)) + Dates.Day(row.Day-1);
end

#insertcols!(df_bucr_all_out, 1, :DATE => (base_date + Dates.Hour.(df_bucr_all_out[!,:Hour])) + Dates.Day.(df_bucr_all_out[!,:Day]-1));
insertcols!(df_bucr_all_out, 2, :DATE_FORMAT => Dates.format.(df_bucr_all_out.DATE, "mm-dd-yyyy HH:MM:SS"));

rename!(df_bucr_all_out, Dict(Symbol("On/off") => "On_off"));
rename!(df_bucr_all_out, Dict(Symbol("UNIT_NAME") => "UNIT_ID"));

df_bucr_all_out = df_bucr_all_out[!, [:DATE, :DATE_FORMAT, :GeneratorID, :UNIT_ID,
    :MinPowerOut, :MaxPowerOut, :Output, :On_off, :ShutDown, :Startup, :TotalGenPosV,
    :TotalGenNegV, :MaxGenVio, :MinGenVio]];

CSV.write(".//outputs//postprocess//postproc_BUCR_Outputs.csv", df_bucr_all_out);

# Date format MM/DD/YYYY HH:MM:SS
Start_date = "01/01/2019 07:00:00"
#Final_date = "01/31/2019 23:00:00"
Final_date = "12/25/2019 06:00:00"

DF_Model_Results = DataFrame();

DF_Model_Results = calc_model_costs(df_gens, df_peakers, df_fuel_gens, df_fuel_peakers,
    df_bucr_all_out, Start_date, Final_date)

DF_Model_Results = calc_model_CO₂_emissions(df_eia_co2, DF_Model_Results);
#TODO: Add calculation for summer
DF_Model_Results = calc_model_NOx_emissions(df_nox_winter, DF_Model_Results);
DF_Model_Results = calc_model_SO₂_emissions(df_so2_winter, DF_Model_Results);


#Format strings to save csv file
Start_date = replace(Start_date, "/" => "-")
Final_date = replace(Final_date, "/" => "-")

Start_date = Start_date[1:findfirst(isequal(' '), Start_date)-1]
Final_date = Final_date[1:findfirst(isequal(' '), Final_date)-1]

CSV.write(".//outputs//postprocess//postproc_model_costs_$(Start_date)_$(Final_date).csv", DF_Model_Results)

#=
df_gens_cost_emiss = CSV.read(".//outputs//postprocess//postproc_gens_cost_emiss_01-01-2019_01-31-2019.csv", header=true, DataFrame);

#df_merge = innerjoin(df_bucr_all_out, df_gens_cost_emiss, on = [:DATE => :BEGIN_DATE, :UNIT_NAME => :UNIT_ID], makeunique=true);
df_merge = outerjoin(df_bucr_all_out, df_gens_cost_emiss,
            on = [:DATE => :BEGIN_DATE, :UNIT_ID => :UNIT_ID],
            validate=(true, true), makeunique=true);

CSV.write(".//outputs//postprocess//postproc_merge_out.csv", df_merge);
=#

#Reference: https://julia-data-query.readthedocs.io/en/latest/dplyr.html
DF_Model_Results_Byname = groupby(DF_Model_Results, [:UNIT_NAME, :TYPE_MAIN_FUEL]);
DF_Model_Results_Byfuel = groupby(DF_Model_Results, [:TYPE_MAIN_FUEL]);

#=DF_Model_Results_Byname = @combine(DF_Model_Results_Byname,
    Sum_GenCost = sum(:GenCost),
    Sum_Output = sum(:Output));
=#
DF_Model_Results_Byname = @combine(DF_Model_Results_Byname,
    Sum_GenCost = sum(:GenCost),
    Sum_MW = sum(:Output),
    Sum_EmissCO2_ton = sum(:EmissCO2_ton),
    Sum_EmissSO2_kg = sum(:EmissSO2_kg),
    Sum_EmissNOx_kg = sum(:EmissNOx_kg));

CSV.write(".//outputs//postprocess//postproc_model_cost_byUnit_$(Start_date)_$(Final_date).csv", DF_Model_Results_Byname)

DF_Model_Results_Byfuel = @combine(DF_Model_Results_Byfuel,
    Sum_GenCost = sum(:GenCost),
    Sum_MW = sum(:Output),
    Sum_EmissCO2_ton = sum(:EmissCO2_ton),
    Sum_EmissSO2_kg = sum(:EmissSO2_kg),
    Sum_EmissNOx_kg = sum(:EmissNOx_kg));

CSV.write(".//outputs//postprocess//postproc_model_cost_emiss_byFuel_$(Start_date)_$(Final_date).csv", DF_Model_Results_Byfuel)

#TODO:
# Check why this is happening:
# ASHV_CT03_0 and ASHV_CT04_0 are in data_fuel_price.csv and data_fuel_price_peakers.csv input files
# ASHV_CC01, ASHV_CC02 are not in data_fuel_price.csv or data_fuel_price_peakers.csv
# input files. In the fuel price files provided by Duke there is only info of them from August 2019.

# Getting time-series statistics
# Reference: https://www.tutorialspoint.com/time_series/time_series_error_metrics.htm

# Root Mean Square Error:
# RMSE = ⎷ (1/n ∑(yₜ' - yₜ)²)
# Mean Absolute Error

#include(".//postprocessing//calc_model_costs.jl")
