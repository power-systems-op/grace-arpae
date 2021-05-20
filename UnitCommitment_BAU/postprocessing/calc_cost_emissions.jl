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

    #Options: COAL, CoGen, NGAS, Nuclear, LOIL, LOIL
    for unit in eachrow(df_gen)
        if (unit.TYPE_MAIN_FUEL == "COAL")
            unit.EmissCO2_ton = unit.Avg_HR * coal_tonCO2_mmbtu[1] * unit.MW;
        elseif (unit.TYPE_MAIN_FUEL == "NGAS")
            unit.EmissCO2_ton = unit.Avg_HR  * ng_tonCO2_mmbtu[1] * unit.MW;
        elseif (unit.TYPE_MAIN_FUEL == "LOIL")
            unit.EmissCO2_ton = unit.Avg_HR  * oil_tonCO2_mmbtu[1] * unit.MW;
      end;
    end
#=
    insertcols!(df_gen, size(df_gen,2),
        :PeakerCO2 => df_gen[!,:Avg_HR] .* tonCO2_mmbtu .* df_gen[!,:PeakerMW]);

    insertcols!(df_gen, size(df_gen,2),
        :CombinedCycleCO2 => df_gen[!,:Avg_HR] .* tonCO2_mmbtu .* df_gen[!,:CombinedCycleMW]);
    # Calculating CO2 emissions for Steam and Steam Dual Boiler units
    tonCO2_mmbtu = (@where(df_co2, occursin("BIT").(:Fuel_code)).KgCO2_MMBTU) / 1000;

    insertcols!(df_gen, size(df_gen,2),
        :SteamCO2 => df_gen[!,:Avg_HR] .* tonCO2_mmbtu .* df_gen[!,:SteamMW]);

    insertcols!(df_gen, size(df_gen,2),
        :SteamDualBoilerCO2 => df_gen[!,:Avg_HR] .* tonCO2_mmbtu .* df_gen[!,:SteamDualBoilerMW]);

    insertcols!(df_gen, size(df_gen,2), :EmissionsCO2_ton => df_gen[!,:PeakerCO2] +
        df_gen[!,:CombinedCycleCO2] + df_gen[!,:SteamCO2] + df_gen[!,:SteamDualBoilerCO2]);
=#
    return df_gen;
end


"""
NOₓ emissions [kg] = avg. heat rate [mmbtu/MWh] * avg NOₓ [lb/mmbu] * power out [MWh] * conv factor[Kg/lb]

The NOₓ factor was estimated from the data prvided by Duke Energy in the files:
   - HR_Breakpoints_Summer_DEC-DEP_(2019) V2.csv and
   - HR_Breakpoints_Winter_DEC-DEP_(2019) V2.csv
"""
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

    # Calculating NOx emissions for Peakers and CC units
#=    insertcols!(df_gen, size(df_gen,2),
          :PeakerNOx => df_gen[!,:Avg_HR] .* df_gen[!,:Avg_NOX] .* df_gen[!,:PeakerMW]);

    insertcols!(df_gen, size(df_gen,2),
          :CombinedCycleNOx => df_gen[!,:Avg_HR] .* df_gen[!,:Avg_NOX] .* df_gen[!,:CombinedCycleMW]);

    # Calculating NOx emissions for Steam and Steam Dual Boiler units
    insertcols!(df_gen, size(df_gen,2),
     :SteamNOx => df_gen[!,:Avg_HR] .* df_gen[!,:Avg_NOX] .* df_gen[!,:SteamMW]);

    insertcols!(df_gen, size(df_gen,2),
       :SteamDualBoilerNOx => df_gen[!,:Avg_HR] .* df_gen[!,:Avg_NOX] .* df_gen[!,:SteamDualBoilerMW]);

    #  NOx Emissions
    insertcols!(df_gen, size(df_gen,2), :EmissNOx_kg => df_gen[!,:PeakerNOx] +
       df_gen[!,:CombinedCycleNOx] + df_gen[!,:SteamNOx] + df_gen[!,:SteamDualBoilerNOx]);
=#
#  NOx Emissions
    insertcols!(df_gen, size(df_gen,2), :EmissNOx_kg => df_gen[!,:Avg_HR] .* df_gen[!,:Avg_NOX] .* df_gen[!,:MW]);

     return df_gen;
end

"""
SO₂ emissions [kg] = avg. heat rate[mmbtu/MWh] * SO₂ factor[kg/mmbu] * Power Out[MW]
The SO₂ factor was obtained from the data provided by Duke Energy in the files:
   - HR_Breakpoints_Summer_DEC-DEP_(2019) V2.csv and
   - HR_Breakpoints_Winter_DEC-DEP_(2019) V2.csv
"""
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
#=
    # Calculating SO2 emissions for Peakers and CC units
    insertcols!(df_gen, size(df_gen,2),
          :PeakerSO2 => df_gen[!,:Avg_HR] .* df_gen[!,:Avg_SO2] .* df_gen[!,:PeakerMW]);

    insertcols!(df_gen, size(df_gen,2),
          :CombinedCycleSO2 => df_gen[!,:Avg_HR] .* df_gen[!,:Avg_SO2] .* df_gen[!,:CombinedCycleMW]);

    # Calculating SO2 emissions for Steam and Steam Dual Boiler units
    insertcols!(df_gen, size(df_gen,2),
     :SteamSO2 => df_gen[!,:Avg_HR] .* df_gen[!,:Avg_SO2] .* df_gen[!,:SteamMW]);

    insertcols!(df_gen, size(df_gen,2),
       :SteamDualBoilerSO2 => df_gen[!,:Avg_HR] .* df_gen[!,:Avg_SO2] .* df_gen[!,:SteamDualBoilerMW]);

    # Adding total SO2 Emissions
    insertcols!(df_gen, size(df_gen,2), :EmissionsSO2_kg => df_gen[!,:PeakerSO2] +
       df_gen[!,:CombinedCycleSO2] + df_gen[!,:SteamSO2] + df_gen[!,:SteamDualBoilerSO2]);
=#
    return df_gen;
end


function main(df_gens::DataFrame, df_peakers::DataFrame, df_fuel_gens::DataFrame,
    df_fuel_peakers::DataFrame, df_gen_sch::DataFrame, df_nox_winter::DataFrame,
    df_so2_winter::DataFrame, df_eia_co2::DataFrame)

    #Combines the slow generators and peakers specs into one dataframe
    df_gens_all = vcat(df_gens, df_peakers);
    # Add the average heat rate data to the all gens' specs dataframe
    df_gens_all.Avg_HR =(df_gens_all.IHRC_B1_HR+df_gens_all.IHRC_B2_HR +
        df_gens_all.IHRC_B3_HR+df_gens_all.IHRC_B4_HR+df_gens_all.IHRC_B5_HR +
        df_gens_all.IHRC_B6_HR+df_gens_all.IHRC_B7_HR) / 7.0;
    # reads the fuel price data for slow gens and peakers

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
    for n_month in 1:1
        #Selects a subset of schedules that fall into the months that users specify.
        # @where could be extended to include other month using the OR operation (||)
        df_gens_sch_drange = @from i in df_gen_sch begin
                    @where Dates.month(i.BEGIN_DATE) == n_month && i.EDITION_NAME=="Actual"
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
        #insertcols!(df_gens, size(df_gens,2), :TYPE_MAIN_FUEL => Vector{String});


        for i in eachrow(df_convgen_sch)
              Idx = findall(x -> x == i.UNIT_NAME, vec(df_gens_all.UNIT_NAME));
              if isempty(Idx) == false
                    i.Avg_HR = df_gens_all.Avg_HR[Idx[1]];
              end
        end

        for k in eachrow(df_convgen_sch)
              Ids = findall(x -> x == k.UNIT_NAME, vec(df_fp_all.UNIT_NAME));

              if isempty(Ids) == false
                    k.Avg_FP = df_fp_all.Avg_FP[Ids[1]];
                    k.TYPE_MAIN_FUEL = df_fp_all.Column3[Ids[1]]; # Column3 = type of main fuel
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

        df_convgen_sch = calc_CO₂_emissions(df_eia_co2, df_convgen_sch);
        #TODO: Add calculation for summer
        df_convgen_sch = calc_NOx_emissions(df_nox_winter, df_convgen_sch);
        df_convgen_sch = calc_SO₂_emissions(df_so2_winter, df_convgen_sch);

        CSV.write(".//outputs//csv//postproc_gens_cost_emiss_month$n_month.csv", df_convgen_sch)

        combine(groupby(df_convgen_sch, [:UNIT_TYPE]),
          df -> DataFrame(mw_mean = mean(df_convgen_sch.MW))
        )

    end #end for cycle
end; # end function


main(df_gens, df_peakers, df_fuel_gens, df_fuel_peakers,
    df_gen_sch, df_nox_winter, df_so2_winter, df_eia_co2)
