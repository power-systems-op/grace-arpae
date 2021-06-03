using DataFrames
using DataFramesMeta
using Dates
using DelimitedFiles
using CSV
using Query
using Statistics
using StatsBase

const FILE_ACCESS_OVER = "w+";
const FILE_ACCESS_APPEND = "a+";

DF_Model = CSV.read(".//outputs//postprocess//postproc_model_costs_01-01-2019_12-25-2019.csv", header=true, DataFrame);
DF_Inputs = CSV.read(".//outputs//postprocess//postproc_gens_cost_emiss_01-01-2019_12-25-2019.csv", header=true, DataFrame);

Start_date = "01/01/2019 07:00:00"
Final_date = "12/25/2019 06:00:00"

#Select a subset of values that fall into the months that the users specifies.
ini_date = DateTime(Start_date, "mm/dd/yyyy HH:MM:SS");
end_date = DateTime(Final_date, "mm/dd/yyyy HH:MM:SS");

rename!(DF_Model,:DATE => :BEGIN_DATE);

df_inputs_drange = @from i in DF_Inputs begin
        @where DateTime(i.BEGIN_DATE) >= ini_date && DateTime(i.BEGIN_DATE) <= end_date
        @select {i.BEGIN_DATE, i.PORTFOLIO_NAME, i.UNIT_NAME, i.UNIT_ID, i.UNIT_TYPE, i.TYPE_MAIN_FUEL,
                i.MW, i.GenCost, i.EmissCO2_ton, i.EmissNOx_kg, i.EmissSO2_kg}
        @collect DataFrame
   end;


df_model_drange = @from i in DF_Model begin
   @where DateTime(i.BEGIN_DATE) >= ini_date && DateTime(i.BEGIN_DATE) <= end_date
   @select {i.BEGIN_DATE, i.UNIT_ID, i.Output, i.GenCost, i.EmissCO2_ton,
            i.EmissNOx_kg, i.EmissSO2_kg}
   @collect DataFrame
end;

rename!(df_model_drange,:Output => :MW_Model, :GenCost => :GenCost_Model,
         :EmissCO2_ton => :EmissCO2_ton_Model, :EmissNOx_kg => :EmissNOx_kg_Model,
         :EmissSO2_kg => :EmissSO2_kg_Model);


DF_Merge = outerjoin(df_inputs_drange, df_model_drange,
            on = [:BEGIN_DATE => :BEGIN_DATE, :UNIT_ID => :UNIT_ID],
            validate=(true, true), makeunique=true);


##Estimate Error Metrics

# Mean Absolute Error (MAE) of power generation (MW)
insertcols!(DF_Merge, size(DF_Merge,2)+1, :Abs_Diff_MW => abs.(DF_Merge.MW_Model .- DF_Merge.MW));

insertcols!(DF_Merge, size(DF_Merge,2)+1, :MW_NoMiss => DF_Merge.MW);
insertcols!(DF_Merge, size(DF_Merge,2)+1, :MW_Model_NoMiss => DF_Merge.MW_Model);

DF_Merge.MW_NoMiss = collect(Missings.replace(DF_Merge.MW_NoMiss, 0))
DF_Merge.MW_Model_NoMiss = collect(Missings.replace(DF_Merge.MW_Model_NoMiss, 0))

DF_Merge.MW_NoMiss = convert.(Float64, DF_Merge.MW_NoMiss);
DF_Merge.MW_Model_NoMiss = convert.(Float64, DF_Merge.MW_Model_NoMiss);
insertcols!(DF_Merge, size(DF_Merge,2)+1, :Abs_Diff_MW_NoMiss => abs.(DF_Merge.MW_NoMiss .- DF_Merge.MW_Model_NoMiss));

MAE_MW = mean(skipmissing(DF_Merge.Abs_Diff_MW));

#MAE_MW_NoMiss = mean(DF_Merge.Abs_Diff_MW_NoMiss);
MAE_MW_NoMiss = meanad(DF_Merge.MW_NoMiss, DF_Merge.MW_Model_NoMiss);

# Mean Percentage Error (MAPE) of power generation (MW)
insertcols!(DF_Merge, size(DF_Merge,2)+1, :Percent_Diff_MW => DF_Merge.Abs_Diff_MW ./ DF_Merge.MW);
insertcols!(DF_Merge, size(DF_Merge,2)+1, :Percent_Diff_MW_NoMiss => DF_Merge.Abs_Diff_MW_NoMiss ./ DF_Merge.MW_NoMiss);

#TODO: Check an alterantive to MAPE
MAPE_MW = (sum(skipmissing(DF_Merge.Percent_Diff_MW)) / size(DF_Merge,1)) * 100;
MAPE_MW_NoMiss = (sum(skipmissing(DF_Merge.Percent_Diff_MW_NoMiss)) / size(DF_Merge,1)) * 100;

#Root Mean Square Error (RMSE) of power generation
insertcols!(DF_Merge, size(DF_Merge,2)+1, :Sqr_Diff_MW => DF_Merge.Abs_Diff_MW.^2);
insertcols!(DF_Merge, size(DF_Merge,2)+1, :Sqr_Diff_MW_NoMiss => DF_Merge.Abs_Diff_MW_NoMiss.^2);

MSE_MW = mean(skipmissing(DF_Merge.Sqr_Diff_MW));
MSE_MW_NoMiss = msd(DF_Merge.MW_NoMiss, DF_Merge.MW_Model_NoMiss);

RMSE_MW = sqrt(mean(skipmissing(DF_Merge.Sqr_Diff_MW)));
RMSE_MW_NoMiss = rmsd(DF_Merge.MW_NoMiss, DF_Merge.MW_Model_NoMiss);
#RMSE_MW_NoMiss = sqrt(mean(DF_Merge.Sqr_Diff_MW_NoMiss));

# Mean Absolute Error (MAE) of generation cost ($)
insertcols!(DF_Merge, size(DF_Merge,2)+1, :Abs_Diff_GenCost => abs.(DF_Merge.GenCost_Model .- DF_Merge.GenCost));

insertcols!(DF_Merge, size(DF_Merge,2)+1, :GenCost_NoMiss => DF_Merge.GenCost);
insertcols!(DF_Merge, size(DF_Merge,2)+1, :GenCost_Model_NoMiss => DF_Merge.GenCost_Model);

DF_Merge.GenCost_NoMiss = collect(Missings.replace(DF_Merge.GenCost_NoMiss, 0))
DF_Merge.GenCost_Model_NoMiss = collect(Missings.replace(DF_Merge.GenCost_Model_NoMiss, 0))

DF_Merge.GenCost_NoMiss = convert.(Float64, DF_Merge.GenCost_NoMiss);
DF_Merge.GenCost_Model_NoMiss = convert.(Float64, DF_Merge.GenCost_Model_NoMiss);

insertcols!(DF_Merge, size(DF_Merge,2)+1, :Abs_Diff_GenCost_NoMiss => abs.(DF_Merge.GenCost_NoMiss .- DF_Merge.GenCost_Model_NoMiss));

MAE_GenCost = mean(skipmissing(DF_Merge.Abs_Diff_GenCost));
MAE_GenCost_NoMiss = mean(DF_Merge.Abs_Diff_GenCost_NoMiss);

# Mean Percentage Error (MAPE) of power generation (GenCost)
insertcols!(DF_Merge, size(DF_Merge,2)+1, :Percent_Diff_GenCost => DF_Merge.Abs_Diff_GenCost ./  DF_Merge.GenCost);
insertcols!(DF_Merge, size(DF_Merge,2)+1, :Percent_Diff_GenCost_NoMiss => (DF_Merge.Abs_Diff_GenCost_NoMiss ./  DF_Merge.GenCost_NoMiss));

MAPE_GenCost = (sum(skipmissing(DF_Merge.Percent_Diff_GenCost)) / size(DF_Merge,1)) * 100;
MAPE_GenCost_NoMiss = (sum(skipmissing(DF_Merge.Percent_Diff_GenCost_NoMiss)) / size(DF_Merge,1)) * 100;

#Root Mean Square Error (RMSE) of generation cost
insertcols!(DF_Merge, size(DF_Merge,2)+1, :Sqr_Diff_GenCost => DF_Merge.Abs_Diff_GenCost.^2);
insertcols!(DF_Merge, size(DF_Merge,2)+1, :Sqr_Diff_GenCost_NoMiss => DF_Merge.Abs_Diff_GenCost_NoMiss.^2);

MSE_GenCost = mean(skipmissing(DF_Merge.Sqr_Diff_GenCost));
MSE_GenCost_NoMiss = msd(DF_Merge.GenCost_NoMiss, DF_Merge.GenCost_Model_NoMiss);

RMSE_GenCost = sqrt(mean(skipmissing(DF_Merge.Sqr_Diff_GenCost)));
RMSE_GenCost_NoMiss = rmsd(DF_Merge.GenCost_NoMiss, DF_Merge.GenCost_Model_NoMiss);

DF_Merge_Byname = groupby(DF_Merge, [:UNIT_NAME, :UNIT_TYPE, :TYPE_MAIN_FUEL]);
DF_Merge_ByID = groupby(DF_Merge, [:UNIT_ID, :UNIT_NAME, :UNIT_TYPE, :TYPE_MAIN_FUEL]);
DF_Merge_Byfuel = groupby(DF_Merge, :TYPE_MAIN_FUEL);

DF_Summary_Byname = @combine(DF_Merge_Byname,
    MW = sum(:MW),
    GenCost = sum(:GenCost),
    EmissCO2_ton = sum(:EmissCO2_ton),
    EmissSO2_kg = sum(:EmissSO2_kg),
    EmissNOx_kg = sum(:EmissNOx_kg),
    MW_Model = sum(:MW_Model),
    GenCost_Model = sum(:GenCost_Model),
    EmissCO2_ton_Model = sum(:EmissCO2_ton_Model),
    EmissSO2_kg_Model = sum(:EmissSO2_kg_Model),
    EmissNOx_kg_Model = sum(:EmissNOx_kg_Model),
    #Sum_Abs_Diff_MW = sum(:Abs_Diff_MW),
    #Percent_Diff_over_MW = mean(:Abs_Diff_MW),
    #Sum_Abs_Diff_GenCost = sum(:Abs_Diff_GenCost),
    #Percent_Diff_over_GenCost = sum(:Abs_Diff_GenCost) / sum(:GenCost),
    #MAE_MW = mean(:Abs_Diff_MW_NoMiss),
    MAE_MW = meanad(:MW_NoMiss, :MW_Model_NoMiss),
    MSE_MW = msd(:MW_NoMiss, :MW_Model_NoMiss),
    #RMSE_MW = sqrt(mean(:Sqr_Diff_MW_NoMiss)),
    RMSE_MW = rmsd(:MW_NoMiss, :MW_Model_NoMiss),
    RMSE_MW_Normal = rmsd(:MW_NoMiss, :MW_Model_NoMiss; normalize=true),
    MAE_GenCost = meanad(:GenCost_NoMiss, :GenCost_Model_NoMiss),
    MSE_GenCost = msd(:GenCost_NoMiss, :GenCost_Model_NoMiss),
    RMSE_GenCost = rmsd(:GenCost_NoMiss, :GenCost_Model_NoMiss),
    RMSE_GenCost_Normal = rmsd(:GenCost_NoMiss, :GenCost_Model_NoMiss; normalize=true),
    N = size(:MW_NoMiss, 1));

DF_Summary_ByID = @combine(DF_Merge_ByID,
    MW = sum(:MW),
    GenCost = sum(:GenCost),
    EmissCO2_ton = sum(:EmissCO2_ton),
    EmissSO2_kg = sum(:EmissSO2_kg),
    EmissNOx_kg = sum(:EmissNOx_kg),
    MW_Model = sum(:MW_Model),
    GenCost_Model = sum(:GenCost_Model),
    EmissCO2_ton_Model = sum(:EmissCO2_ton_Model),
    EmissSO2_kg_Model = sum(:EmissSO2_kg_Model),
    EmissNOx_kg_Model = sum(:EmissNOx_kg_Model),
    MAE_MW = meanad(:MW_NoMiss, :MW_Model_NoMiss),
    MSE_MW = msd(:MW_NoMiss, :MW_Model_NoMiss),
    RMSE_MW = rmsd(:MW_NoMiss, :MW_Model_NoMiss),
    RMSE_MW_Normal = rmsd(:MW_NoMiss, :MW_Model_NoMiss; normalize=true),
    MAE_GenCost = meanad(:GenCost_NoMiss, :GenCost_Model_NoMiss),
    MSE_GenCost = msd(:GenCost_NoMiss, :GenCost_Model_NoMiss),
    RMSE_GenCost = rmsd(:GenCost_NoMiss, :GenCost_Model_NoMiss),
    RMSE_GenCost_Normal = rmsd(:GenCost_NoMiss, :GenCost_Model_NoMiss; normalize=true),
    N = size(:MW_NoMiss, 1));

DF_Summary_Byfuel = @combine(DF_Merge_Byfuel,
    MW = sum(:MW),
    GenCost = sum(:GenCost),
    EmissCO2_ton = sum(:EmissCO2_ton),
    EmissSO2_kg = sum(:EmissSO2_kg),
    EmissNOx_kg = sum(:EmissNOx_kg),
    MW_Model = sum(:MW_Model),
    GenCost_Model = sum(:GenCost_Model),
    EmissCO2_ton_Model = sum(:EmissCO2_ton_Model),
    EmissSO2_kg_Model = sum(:EmissSO2_kg_Model),
    EmissNOx_kg_Model = sum(:EmissNOx_kg_Model),
    MAE_MW = meanad(:MW_NoMiss, :MW_Model_NoMiss),
    MSE_MW = msd(:MW_NoMiss, :MW_Model_NoMiss),
    RMSE_MW = rmsd(:MW_NoMiss, :MW_Model_NoMiss),
    RMSE_MW_Normal = rmsd(:MW_NoMiss, :MW_Model_NoMiss; normalize=true),
    MAE_GenCost = meanad(:GenCost_NoMiss, :GenCost_Model_NoMiss),
    MSE_GenCost = msd(:GenCost_NoMiss, :GenCost_Model_NoMiss),
    RMSE_GenCost = rmsd(:GenCost_NoMiss, :GenCost_Model_NoMiss),
    RMSE_GenCost_Normal = rmsd(:GenCost_NoMiss, :GenCost_Model_NoMiss; normalize=true),
    N = size(:MW_NoMiss, 1) );

#Some of the operations in the @combine function add a total row. Delete this.
delete!(DF_Summary_Byname, size(DF_Summary_Byname,1))
delete!(DF_Summary_ByID, size(DF_Summary_ByID,1))
delete!(DF_Summary_Byfuel, size(DF_Summary_Byfuel,1))

#Store results
Start_date = replace(Start_date, "/" => "-");
Final_date = replace(Final_date, "/" => "-");

Start_date = Start_date[1:findfirst(isequal(' '), Start_date)-1]
Final_date = Final_date[1:findfirst(isequal(' '), Final_date)-1]

CSV.write(".//outputs//postprocess//gen_cost_emiss_inputANDmodel_$(Start_date)_$(Final_date).csv", DF_Merge)

CSV.write(".//outputs//postprocess//perform_error_byName_$(Start_date)_$(Final_date).csv", DF_Summary_Byname)
CSV.write(".//outputs//postprocess//perform_error_byID_$(Start_date)_$(Final_date).csv", DF_Summary_ByID)
CSV.write(".//outputs//postprocess//perform_error_byFuel_$(Start_date)_$(Final_date).csv", DF_Summary_Byfuel)

# Save performance error indicators for whole data set
performance_header    = ["Outcome", "Mean Absolute Error (MAE)", "Mean Square Error (MSE)", "Root Mean Square Error (RMSE)"]
open(".//outputs//postprocess//perform_error_TOTAL_$(Start_date)_$(Final_date).csv", FILE_ACCESS_OVER) do io
    writedlm(io, permutedims(performance_header), ',')
    writedlm(io, hcat("Power Output (MW)", MAE_MW, MSE_MW, RMSE_MW), ',')
    writedlm(io, hcat("Power Output (MW) [Missing replaced]", MAE_MW_NoMiss, MSE_MW_NoMiss, RMSE_MW_NoMiss), ',')
    writedlm(io, hcat("Generation Cost", MAE_GenCost, MSE_GenCost, RMSE_GenCost), ',')
    writedlm(io, hcat("Generation Cost [Missing replaced]", MAE_GenCost_NoMiss, MSE_GenCost_NoMiss, RMSE_GenCost_NoMiss), ',')
end; # closes file

#include(".//postprocessing//get_perform_err_metrics.jl")
