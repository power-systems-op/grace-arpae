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

DF_Gen_Sch = CSV.read(".//inputs//UnitSchedule_(DEC-DEP 2019).csv",
                  dateformat="mm-dd-yyyy THH:MM:SS.000Z", header=true, copycols=true, DataFrame);

DF_Gens = CSV.read(".//inputs//data_generators.csv", header=true, DataFrame);
DF_Peakers = CSV.read(".//inputs//data_peakers.csv", header=true, DataFrame);

select!(DF_Gens, Not(:Cogen));

#=
cycles_units_header    = ["Section", "Time", "Note1", "Note2", "Note3", "Note4"]
open(".//outputs//postproc_gens_cycle_units.csv", FILE_ACCESS_OVER) do io
    writedlm(io, permutedims(cycles_units_header), ',')
end; # closes file
=#


function calc_gens_cyclesbyID(df_results::DataFrame, df_gen_sch::DataFrame,
    df_gens_all::DataFrame, ini_date::String, end_date::String)
    #Selects a subset of schedules that fall into the months that users specify.
    # @where could be extended to include other month using the OR operation (||)
    ini_date = DateTime(ini_date, "mm/dd/yyyy HH:MM:SS");
    end_date = DateTime(end_date, "mm/dd/yyyy HH:MM:SS");

    # add UNIT_ID
    insertcols!(df_gen_sch, 4, :UNIT_ID => df_gen_sch.UNIT_NAME .* "_" .* string.(df_gen_sch.CC_KEY));
    #df_gen_sch = df_gen_sch

    df_gens_sch_drange = @from i in df_gen_sch begin
                @where DateTime(i.BEGIN_DATE) >= ini_date && DateTime(i.BEGIN_DATE) <= end_date && i.EDITION_NAME=="Actual"
                @select {i.PORTFOLIO_NAME, i.EDITION_NAME, i.UNIT_NAME, i.CC_KEY, i.UNIT_ID, i.UNIT_TYPE, i.BEGIN_DATE, i.MW}
                @collect DataFrame
           end

    df_convgen_sch = @from i in df_gens_sch_drange begin
                @where  i.UNIT_TYPE=="Steam" || i.UNIT_TYPE=="Steam Dual Boiler" || i.UNIT_TYPE=="Peaker" || i.UNIT_TYPE=="Nuclear" || i.UNIT_TYPE=="Combined-Cycle"
                @select {i.PORTFOLIO_NAME, i.EDITION_NAME, i.UNIT_NAME, i.CC_KEY, i.UNIT_ID, i.UNIT_TYPE, i.BEGIN_DATE, i.MW}
                @collect DataFrame
           end
    insertcols!(df_convgen_sch, size(df_convgen_sch,2), :On_Off => Int64.(df_convgen_sch.MW .> 0));
    insertcols!(df_convgen_sch, size(df_convgen_sch,2), :ShutDown => zeros(Int64));
    insertcols!(df_convgen_sch, size(df_convgen_sch,2), :StartUp => zeros(Int64));

    for unit in eachrow(df_gens_all)
        #unit_name = unit.UNIT_NAME;
        unit_id = unit.UNIT_ID;
        df_unit_sch = @where(df_convgen_sch, (:UNIT_ID .== unit_id))
        insertcols!(df_unit_sch, 1, :UNIT => unit.UNIT);
        #df_unit_sch = @where(df_convgen_sch, (:UNIT_NAME .== "ALLE_UN01"))

        sort!(df_unit_sch, :BEGIN_DATE)

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
    end; # for loop all units in dataframe df_gens_all

    return df_results;
end; # function


#Combines the slow generators and peakers specs into one dataframe
DF_Gens_All = vcat(DF_Gens, DF_Peakers);

# Filtering the Actual generation outcomes from UNIT_Schedules.csv
# Reformats the date-time data given in column BEGIN_DATE
DF_Gen_Sch.BEGIN_DATE = DateTime.(DF_Gen_Sch.BEGIN_DATE, "mm/dd/yyyy HH:MM:SS p");

Start_date = "01/01/2019 00:00:00"
Final_date = "01/02/2019 02:00:00"
DF_Results = DataFrame();

DF_Results = calc_gens_cycles(DF_Results, DF_Gen_Sch, DF_Gens_All, Start_date, Final_date);

Start_date = replace(Start_date, "/" => "-")
Final_date = replace(Final_date, "/" => "-")
Start_date = Start_date[1:findfirst(isequal(' '), Start_date)-1]
Final_date = Final_date[1:findfirst(isequal(' '), Final_date)-1]

CSV.write(".//outputs//postprocess//postproc_gens_cycles_ByID_$(Start_date)_$(Final_date).csv", DF_Results)

# Get Summary of results by unit and save them
#Reference: https://julia-data-query.readthedocs.io/en/latest/dplyr.html
DF_Results_ByID = groupby(DF_Results, [:UNIT_ID, :UNIT_TYPE]);

DF_ResultsID_Summary = @combine(DF_Results_ByID,
  Sum_On_Off = sum(:On_Off),
  Avg_On_Off = mean(:On_Off),
  Sum_StartUp = sum(:StartUp),
  Sum_ShutDown = sum(:ShutDown))

CSV.write(".//outputs//postprocess//postproc_gens_cycles_SUMMARYbyID_$(Start_date)_$(Final_date).csv", DF_ResultsID_Summary)

#=TODO:
Emissions calculations for 358 days
Shutdown is 1, one hour after the unit has been shutoff.
Compare the number of shutdowns and startup.
startup if at time 0 the units are on.
=#

#include(".//postprocessing//calc_input_gens_cyclesbyID.jl")
