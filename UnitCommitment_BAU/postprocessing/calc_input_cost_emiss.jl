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

"""
CO₂ emissions [metric ton] = avg. heat rate[mmbtu/MWh] * CO₂ factor[kg/mmbu] * Power Out[MWh] * 10⁻³
 The CO₂ factor was obtained from the EIA site:
 [https://www.eia.gov/electricity/annual/html/epa_a_03.html]
"""
function calc_CO₂_emissions(df_co2::DataFrame, df_gen::DataFrame)
    # Calculating CO2 emissions for Peakers and CC units
    tonCO2_mmbtu = (@where(df_co2, occursin("NG").(:Fuel_code)).KgCO2_MMBTU ) / 1000.0;

    ng_tonCO2_mmbtu = (@where(df_co2, occursin("NG").(:Fuel_code)).KgCO2_MMBTU) / 1000.0;
    coal_tonCO2_mmbtu = (@where(df_co2, occursin("BIT").(:Fuel_code)).KgCO2_MMBTU)/ 1000.0;
    oil_tonCO2_mmbtu = (@where(df_co2, occursin("DFO").(:Fuel_code)).KgCO2_MMBTU)/ 1000.0;

    insertcols!(df_gen, size(df_gen,2), :EmissCO2_ton => zeros(Float64));

    #Options: COAL, CoGen, NGAS, Nuclear, and LOIL
    for unit in eachrow(df_gen)
        if (unit.TYPE_MAIN_FUEL == "COAL")
            unit.EmissCO2_ton = unit.Avg_HR * coal_tonCO2_mmbtu[1] * unit.MW;
        elseif (unit.TYPE_MAIN_FUEL == "NGAS")
            unit.EmissCO2_ton = unit.Avg_HR  * ng_tonCO2_mmbtu[1] * unit.MW;
        elseif (unit.TYPE_MAIN_FUEL == "LOIL")
            unit.EmissCO2_ton = unit.Avg_HR  * oil_tonCO2_mmbtu[1] * unit.MW;
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
function calc_NOx_emissions(df_nox::DataFrame, df_gen::DataFrame)
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
    insertcols!(df_gen, size(df_gen,2), :EmissNOx_kg => df_gen[!,:Avg_HR] .* df_gen[!,:Avg_NOX] .* df_gen[!,:MW]);

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
function calc_SO₂_emissions(df_so2::DataFrame, df_gen::DataFrame)
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

    insertcols!(df_gen, size(df_gen,2), :EmissSO2_kg => df_gen[!,:Avg_HR] .* df_gen[!,:Avg_SO2] .* df_gen[!,:MW]);

    return df_gen;
end



"""
Generators' cost of unit i (variable cost)
Cost Unitᵢ [USD] = Avg. heat rate[mmbtu/MWh] * Avg. Fuel Price [USD/mmbtu] * Power Out[MWh]

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
function calc_gens_costs(df_gens::DataFrame, df_peakers::DataFrame, df_fuel_gens::DataFrame,
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
    insertcols!(df_fp_all, 2, :UNIT_NAME => "UNIT_", makeunique=true);

    for j in eachrow(df_fp_all)
        Idk = findall(x -> x == j.Column2, vec(df_gens_all.UNIT_ID));
        if isempty(Idk) == false
            j.UNIT_NAME = df_gens_all.UNIT_NAME[Idk[1]];
        end
    end

    # Filtering the Actual generation outcomes from UNIT_Schedules.csv
    # Reformats the date-time data given in column BEGIN_DATE
    df_gen_sch.BEGIN_DATE = DateTime.(df_gen_sch.BEGIN_DATE, "mm/dd/yyyy HH:MM:SS p");

    # Call function
    #Selects a subset of schedules that fall into the months that users specify.
    # @where could be extended to include other month using the OR operation (||)
    ini_date = DateTime(ini_date, "mm/dd/yyyy HH:MM:SS");
    end_date = DateTime(end_date, "mm/dd/yyyy HH:MM:SS");

    df_gens_sch_drange = @from i in df_gen_sch begin
                @where DateTime(i.BEGIN_DATE) >= ini_date && DateTime(i.BEGIN_DATE) <= end_date && i.EDITION_NAME=="Actual"
                @select {i.PORTFOLIO_NAME, i.EDITION_NAME, i.UNIT_NAME, i.CC_KEY, i.UNIT_TYPE, i.BEGIN_DATE, i.MW}
                @collect DataFrame
           end

    df_convgen_sch = @from i in df_gens_sch_drange begin
                @where  i.UNIT_TYPE=="Steam" || i.UNIT_TYPE=="Steam Dual Boiler" || i.UNIT_TYPE=="Peaker" || i.UNIT_TYPE=="Nuclear" || i.UNIT_TYPE=="Combined-Cycle"
                @select {i.PORTFOLIO_NAME, i.EDITION_NAME, i.UNIT_NAME, i.CC_KEY, i.UNIT_TYPE, i.BEGIN_DATE, i.MW}
                @collect DataFrame
           end

    insertcols!(df_convgen_sch, size(df_convgen_sch,2), :Avg_HR => zeros(Float64));
    insertcols!(df_convgen_sch, size(df_convgen_sch,2), :Avg_FP => zeros(Float64));
    insertcols!(df_convgen_sch, size(df_convgen_sch,2), :TYPE_MAIN_FUEL => "");
    insertcols!(df_convgen_sch, 4, :UNIT_ID => "");

    for row in eachrow(df_convgen_sch)
        Idx = findall(x -> x == row.UNIT_NAME, vec(df_gens_all.UNIT_NAME));
        row.UNIT_ID = string(row.UNIT_NAME, "_", row.CC_KEY);
        if isempty(Idx) == false
            row.Avg_HR = df_gens_all.Avg_HR[Idx[1]];
        end
    end

    for row in eachrow(df_convgen_sch)
        Idx = findall(x -> x == row.UNIT_NAME, vec(df_fp_all.UNIT_NAME));
        if isempty(Idx) == false
            row.Avg_FP = df_fp_all.Avg_FP[Idx[1]];
            row.TYPE_MAIN_FUEL = df_fp_all.Column3[Idx[1]]; # Column3 = type of main fuel
        end
    end

    insertcols!(df_convgen_sch, size(df_convgen_sch,2), :GenCost => df_convgen_sch[!,:MW] .*df_convgen_sch[!,:Avg_HR] .* df_convgen_sch[!,:Avg_FP]);
    insertcols!(df_convgen_sch, size(df_convgen_sch,2), :Steam => Int64.(df_convgen_sch.UNIT_TYPE .=="Steam"));
    insertcols!(df_convgen_sch, size(df_convgen_sch,2), :SteamDualBoiler => Int64.(df_convgen_sch.UNIT_TYPE .== "Steam Dual Boiler"));
    insertcols!(df_convgen_sch, size(df_convgen_sch,2), :CombinedCycle => Int64.(df_convgen_sch.UNIT_TYPE .== "Combined-Cycle"));
    insertcols!(df_convgen_sch, size(df_convgen_sch,2), :Nuclear => Int64.(df_convgen_sch.UNIT_TYPE .== "Nuclear"));
    insertcols!(df_convgen_sch, size(df_convgen_sch,2), :Peaker => Int64.(df_convgen_sch.UNIT_TYPE .== "Peaker"));

    insertcols!(df_convgen_sch, size(df_convgen_sch,2), :SteamMW => df_convgen_sch[!,:MW] .*df_convgen_sch[!,:Steam]);
    insertcols!(df_convgen_sch, size(df_convgen_sch,2), :SteamDualBoilerMW => df_convgen_sch[!,:MW] .*df_convgen_sch[!,:SteamDualBoiler]);
    insertcols!(df_convgen_sch, size(df_convgen_sch,2), :CombinedCycleMW => df_convgen_sch[!,:MW] .*df_convgen_sch[!,:CombinedCycle]);
    insertcols!(df_convgen_sch, size(df_convgen_sch,2), :NuclearMW => df_convgen_sch[!,:MW] .*df_convgen_sch[!,:Nuclear]);
    insertcols!(df_convgen_sch, size(df_convgen_sch,2), :PeakerMW => df_convgen_sch[!,:MW] .*df_convgen_sch[!,:Peaker]);

    insertcols!(df_convgen_sch, size(df_convgen_sch,2), :SteamCost => df_convgen_sch[!,:GenCost] .*df_convgen_sch[!,:Steam]);
    insertcols!(df_convgen_sch, size(df_convgen_sch,2), :SteamDualBoilerCost => df_convgen_sch[!,:GenCost] .*df_convgen_sch[!,:SteamDualBoiler]);
    insertcols!(df_convgen_sch, size(df_convgen_sch,2), :CombinedCycleCost => df_convgen_sch[!,:GenCost] .*df_convgen_sch[!,:CombinedCycle]);
    insertcols!(df_convgen_sch, size(df_convgen_sch,2), :NuclearCost => df_convgen_sch[!,:GenCost] .*df_convgen_sch[!,:Nuclear]);
    insertcols!(df_convgen_sch, size(df_convgen_sch,2), :PeakerCost => df_convgen_sch[!,:GenCost] .*df_convgen_sch[!,:Peaker]);

    return df_convgen_sch;
end; # end function

# Date format MM/DD/YYYY HH:MM:SS
Start_date = "01/01/2019 07:00:00"
#Final_date = "01/31/2019 23:00:00"
Final_date = "12/25/2019 06:00:00"

DF_Results = DataFrame();

DF_Results = calc_gens_costs(df_gens, df_peakers, df_fuel_gens, df_fuel_peakers,
    df_gen_sch, Start_date, Final_date)

DF_Results = calc_CO₂_emissions(df_eia_co2, DF_Results);
#TODO: Add calculation for summer
DF_Results = calc_NOx_emissions(df_nox_winter, DF_Results);
DF_Results = calc_SO₂_emissions(df_so2_winter, DF_Results);

Start_date = replace(Start_date, "/" => "-")
Final_date = replace(Final_date, "/" => "-")

Start_date = Start_date[1:findfirst(isequal(' '), Start_date)-1]
Final_date = Final_date[1:findfirst(isequal(' '), Final_date)-1]

DF_Results = DF_Results[!, [:BEGIN_DATE, :UNIT_NAME, :CC_KEY, :UNIT_ID, :UNIT_TYPE,
            :PORTFOLIO_NAME, :Avg_HR, :Avg_FP, :TYPE_MAIN_FUEL,
            :GenCost, :EmissCO2_ton, :Avg_NOX, :EmissNOx_kg, :Avg_SO2,
            :EmissSO2_kg, :MW]];

CSV.write(".//outputs//postprocess//postproc_gens_cost_emiss_$(Start_date)_$(Final_date).csv", DF_Results)

#Reference: https://julia-data-query.readthedocs.io/en/latest/dplyr.html
DF_Results_Byname = groupby(DF_Results, [:UNIT_NAME, :UNIT_TYPE, :TYPE_MAIN_FUEL]);
DF_Results_Byfuel = groupby(DF_Results, [:TYPE_MAIN_FUEL]);

DF_Results_Byname = @combine(DF_Results_Byname,
    Sum_GenCost = sum(:GenCost),
    Sum_MW = sum(:MW),
    Sum_EmissCO2_ton = sum(:EmissCO2_ton),
    Sum_EmissSO2_kg = sum(:EmissSO2_kg),
    Sum_EmissNOx_kg = sum(:EmissNOx_kg));

CSV.write(".//outputs//postprocess//postproc_gens_cost_emiss_byUnit_$(Start_date)_$(Final_date).csv", DF_Results_Byname)

DF_Results_Byfuel = @combine(DF_Results_Byfuel,
    Sum_GenCost = sum(:GenCost),
    Sum_MW = sum(:MW),
    Sum_EmissCO2_ton = sum(:EmissCO2_ton),
    Sum_EmissSO2_kg = sum(:EmissSO2_kg),
    Sum_EmissNOx_kg = sum(:EmissNOx_kg));

CSV.write(".//outputs//postprocess//postproc_gens_cost_emiss_byFuel_$(Start_date)_$(Final_date).csv", DF_Results_Byfuel)


#include(".//postprocessing//calc_cost_emissions.jl")
dummy = @where(DF_Results, (:UNIT_NAME .== "SUTT_CT02"))
dummy = @where(DF_Results_Byname, (:UNIT_NAME .== "BELE_UN01"))
dummy_model = @where(DF_Model_Results_Byname, (:UNIT_NAME .== "BELE_UN01"))

dummy = @where(DF_Results, (:UNIT_NAME .== "BELE_UN01"))
CSV.write(".//outputs//postprocess//TEMP_dummy.csv", dummy)

@where(DF_Results_Byname, (:UNIT_NAME .== "BELE_UN01"))
