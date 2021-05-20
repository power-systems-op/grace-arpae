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

const FILE_ACCESS_OVER = "w+";
const FILE_ACCESS_APPEND = "a+";
#include("import_post_data.jl")

DF_Gen_Sch = CSV.read(".//inputs//csv//UnitSchedule_(DEC-DEP 2019).csv",
                  dateformat="mm-dd-yyyy THH:MM:SS.000Z", header=true, copycols=true, DataFrame);

DF_Gens = CSV.read(".//inputs//csv//data_generators.csv", header=true, DataFrame);
DF_Peakers = CSV.read(".//inputs//csv//data_peakers.csv", header=true, DataFrame);

select!(DF_Gens, Not(:Cogen));

#=
cycles_units_header    = ["Section", "Time", "Note1", "Note2", "Note3", "Note4"]
open(".//outputs//csv//postproc_gens_cycle_units.csv", FILE_ACCESS_OVER) do io
    writedlm(io, permutedims(cycles_units_header), ',')
end; # closes file
=#


function calc_gens_cycles(df_results::DataFrame, df_gen_sch::DataFrame,
    df_gens_all::DataFrame, n_month::Int64)
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
    insertcols!(df_convgen_sch, size(df_convgen_sch,2), :On_Off => Int64.(df_convgen_sch.MW .> 0));
    insertcols!(df_convgen_sch, size(df_convgen_sch,2), :ShutDown => zeros(Int64));
    insertcols!(df_convgen_sch, size(df_convgen_sch,2), :StartUp => zeros(Int64));
    #CSV.write(".//outputs//csv//postproc_gens_cycle_month$n_month.csv", df_convgen_sch)

    for unit in eachrow(df_gens_all)
        unit_name = unit.UNIT_NAME;
        df_unit_sch = @where(df_convgen_sch, (:UNIT_NAME .== unit_name))
        insertcols!(df_unit_sch, 1, :UNIT => unit.UNIT);
        #df_unit_sch = @where(df_convgen_sch, (:UNIT_NAME .== "ALLE_UN01"))

        sort!(df_unit_sch, :BEGIN_DATE)

    #=    if unit.UNIT == 120
            break
        end;
    =#
        was_on = zero(Int64);
        for row in eachrow(df_unit_sch)
            if rownumber(row) == 1  #First row, save initial ON/OFF value
                was_on = row.On_Off;
                row.StartUp = row.On_Off;
            elseif ((row.On_Off == 1)  & (was_on == 0))
                was_on = 1;
                row.StartUp = 1;
            elseif ((row.On_Off == 0)  & (was_on == 1))
                was_on = 0;
                row.ShutDown = 1;
            end;
        end;

        if isempty(df_results)
            df_results = copy(df_unit_sch);
        else
            df_results = vcat(df_results, df_unit_sch);
        end;

        #println("Number of cycles for unit:", df_unit_sch.UNIT_NAME, "is: ", n_cycles)
        #CSV.write(".//outputs//csv//postproc_gens_cycle_unit$unit_name.csv", df_unit_sch)
    end; # for loop all units in dataframe df_gens_all

    return df_results;
end; # function


#Combines the slow generators and peakers specs into one dataframe
DF_Gens_All = vcat(DF_Gens, DF_Peakers);

# Filtering the Actual generation outcomes from UNIT_Schedules.csv
# Reformats the date-time data given in column BEGIN_DATE
DF_Gen_Sch.BEGIN_DATE = DateTime.(DF_Gen_Sch.BEGIN_DATE, "mm/dd/yyyy HH:MM:SS p");

#TODO: Change date range to be dates (MM/DD/YY) instead of inital month end months

#=
n_month = 1;
DF_Results = DataFrame();
DF_Results = calc_gens_cycles(DF_Results, DF_Gen_Sch, DF_Gens_All, n_month);
CSV.write(".//outputs//csv//postproc_gens_cycle_ALLUNITS.csv", DF_Results)
=#
let
    ini_month = 1;
    end_month = 12;
    DF_Results = DataFrame();
    for month in ini_month:end_month
        DF_Results = calc_gens_cycles(DF_Results, DF_Gen_Sch, DF_Gens_All, month);
    end;
    CSV.write(".//outputs//csv//postproc_gens_cycle_ALLUNITS.csv", DF_Results);
end

#=TODO:
Emissions calculations for 358 days
Shutdown is 1, one hour after the unit has been shutoff.
Compare the number of shutdowns and startup.
startup if at time 0 the units are on.
=#
