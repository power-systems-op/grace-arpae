using DataFrames
using DelimitedFiles
using JuMP

include("constants.jl")
include("data_structure.jl")

#function fucr_model(df_gens, df_peakers, fuelprice, fuelprice_peakers, df_storage, uc_results)
function fucr_model(day::Int64, df_gens::DataFrame, df_peakers::DataFrame,
      fuelprice::Matrix{Float64}, fuelprice_peakers::Matrix{Float64},
      df_storage::DataFrame, fucr_results::UC_Results, fucr_prep_demand)

   t1_FUCRmodel = time_ns()

   uc_gens = GensResults();
   uc_peakers = PeakersResults();
   uc_storg = StorageResults();

   uc_results = UC_Results(uc_gens, uc_peakers, uc_storg);

   model = direct_model(CPLEX.Optimizer())
   #set_optimizer_attribute(model, "CPX_PARAM_EPINT", 1e-5)
   # Enable Benders strategy
   #MOI.set(model, MOI.RawParameter("CPXPARAM_Benders_Strategy"), 3)
   set_optimizer_attribute(model, "CPX_PARAM_EPGAP", SOLVER_EPGAP)

   # Declaring the decision variables for conventional generators
   @variable(model, fucrm_genOnOff[1:GENS, 0:HRS_FUCR], Bin) #Bin
   @variable(model, fucrm_genStartUp[1:GENS, 1:HRS_FUCR], Bin) # startup variable
   @variable(model, fucrm_genShutDown[1:GENS, 1:HRS_FUCR], Bin) # shutdown variable
   @variable(model, fucrm_genOut[1:GENS, 0:HRS_FUCR]>=0) # Generator's output schedule
   @variable(model, fucrm_genOut_Block[1:GENS, 1:BLOCKS, 1:HRS_FUCR]>=0) # Generator's output schedule from each block (block rfers to IHR curve blocks/segments)
   @variable(model, fucrm_genResUp[1:GENS, 1:HRS_FUCR]>=0) # Generators' up reserve schedule
   @variable(model, fucrm_genResNonSpin[1:GENS, 1:HRS_FUCR]>=0) # Scheduled up reserve on offline fast-start peakers
   @variable(model, fucrm_genResDn[1:GENS, 1:HRS_FUCR]>=0) # Generator's down rserve schedule
   @variable(model, fucrm_totGenVioP[g=1:GENS, 1:HRS_FUCR]>=0)
   @variable(model, fucrm_totGenVioN[g=1:GENS, 1:HRS_FUCR]>=0)
   @variable(model, fucrm_maxGenVioP[g=1:GENS, 1:HRS_FUCR]>=0)
   @variable(model, fucrm_minGenVioP[g=1:GENS, 1:HRS_FUCR]>=0)

   # Declaring the decision variables for peaker units
   @variable(model, 0<=fucrm_peakerOnOff[1:PEAKERS, 0:HRS_FUCR]<=1)
   @variable(model, 0<=fucrm_peakerStartUp[1:PEAKERS, 1:HRS_FUCR]<=1)
   @variable(model, 0<=fucrm_peakerShutDown[1:PEAKERS, 1:HRS_FUCR]<=1)
   @variable(model, fucrm_peakerOut[1:PEAKERS, 0:HRS_FUCR]>=0) # Generator's output schedule
   @variable(model, fucrm_peakerOut_Block[1:PEAKERS, 1:BLOCKS, 1:HRS_FUCR]>=0) # Generator's output schedule from each block (block rfers to IHR curve blocks/segments)
   @variable(model, fucrm_peakerResUp[1:PEAKERS, 1:HRS_FUCR]>=0) # Generators' up reserve schedule
   @variable(model, fucrm_peakerResNonSpin[1:PEAKERS, 1:HRS_FUCR]>=0) # Scheduled up reserve on offline fast-start peakers
   @variable(model, fucrm_peakerResDn[1:PEAKERS, 1:HRS_FUCR]>=0) # Generator's down rserve schedule

   # declaring decision variables for storage Units
   @variable(model, fucrm_storgChrg[1:STORG_UNITS, 1:HRS_FUCR], Bin) #Bin variable equal to 1 if unit runs in the charging mode
   @variable(model, fucrm_storgDisc[1:STORG_UNITS, 1:HRS_FUCR], Bin) #Bin variable equal to 1 if unit runs in the discharging mode
   @variable(model, fucrm_storgIdle[1:STORG_UNITS, 1:HRS_FUCR], Bin) ##Bin variable equal to 1 if unit runs in the idle mode
   @variable(model, fucrm_storgChrgPwr[1:STORG_UNITS, 0:HRS_FUCR]>=0) #Chargung power
   @variable(model, fucrm_storgDiscPwr[1:STORG_UNITS, 0:HRS_FUCR]>=0) # Discharging Power
   @variable(model, fucrm_storgSOC[1:STORG_UNITS, 0:HRS_FUCR]>=0) # state of charge (stored energy level for storage unit at time t)
   @variable(model, fucrm_storgResUp[1:STORG_UNITS, 0:HRS_FUCR]>=0) # Scheduled up reserve
   @variable(model, fucrm_storgResDn[1:STORG_UNITS, 0:HRS_FUCR]>=0) # Scheduled down reserve

   # declaring decision variables for renewable generation
   @variable(model, fucrm_solarG[1:N_ZONES, 1:HRS_FUCR]>=0) # solar energy schedules
   @variable(model, fucrm_windG[1:N_ZONES, 1:HRS_FUCR]>=0) # wind energy schedules
   @variable(model, fucrm_hydroG[1:N_ZONES, 1:HRS_FUCR]>=0) # hydro energy schedules
   @variable(model, fucrm_solarGSpil[1:N_ZONES, 1:HRS_FUCR]>=0) # solar energy schedules
   @variable(model, fucrm_windGSpil[1:N_ZONES, 1:HRS_FUCR]>=0) # wind energy schedules
   @variable(model, fucrm_hydroGSpil[1:N_ZONES, 1:HRS_FUCR]>=0) # hydro energy schedules

   # Declaring decision variables for hourly dispatched and curtailed demand
   @variable(model, fucrm_demand[1:N_ZONES, 1:HRS_FUCR]>=0) # Hourly scheduled demand
   @variable(model, fucrm_demand_curt[1:N_ZONES, 1:HRS_FUCR]>=0) # Hourly schedule demand

   # Declaring variables for transmission system
   @variable(model, fucrm_voltangle[1:N_ZONES, 1:HRS_FUCR]) #voltage angle at zone/bus n in t//
   @variable(model, fucrm_powerflow[1:N_ZONES, 1:M_ZONES, 1:HRS_FUCR]) #transmission Flow from zone n to zone m//

   # Declaring over and undergeneration decision variable
   @variable(model, fucrm_overgen[1:N_ZONES, 1:HRS_FUCR]>=0) #overgeneration at zone n and time t//


   # Defining the objective function that minimizes the overal cost of supplying electricity (=total variable, no-load, startup, and shutdown costs)
   @objective(model, Min, sum(sum(df_gens.IHRC_B1_HR[g]*fuelprice[g,day]*fucrm_genOut_Block[g,1,t]
                                     +df_gens.IHRC_B2_HR[g]*fuelprice[g,day]*fucrm_genOut_Block[g,2,t]
                                     +df_gens.IHRC_B3_HR[g]*fuelprice[g,day]*fucrm_genOut_Block[g,3,t]
                                     +df_gens.IHRC_B4_HR[g]*fuelprice[g,day]*fucrm_genOut_Block[g,4,t]
                                     +df_gens.IHRC_B5_HR[g]*fuelprice[g,day]*fucrm_genOut_Block[g,5,t]
                                     +df_gens.IHRC_B6_HR[g]*fuelprice[g,day]*fucrm_genOut_Block[g,6,t]
                                     +df_gens.IHRC_B7_HR[g]*fuelprice[g,day]*fucrm_genOut_Block[g,7,t]
                                     +df_gens.NoLoadHR[g]*fuelprice[g,day]*fucrm_genOnOff[g,t]
                                     +((df_gens.HotStartU_FixedCost[g]
                                     +(df_gens.HotStartU_HeatRate[g]*fuelprice[g,day]))*fucrm_genStartUp[g,t])
                                     +df_gens.ShutdownCost[g]*fucrm_genShutDown[g, t]
                                     +(fucrm_totGenVioP[g,t]*VIOLATION_PENALTY)
                                     +(fucrm_totGenVioN[g,t]*VIOLATION_PENALTY)
                                     +(fucrm_maxGenVioP[g,t]*VIOLATION_PENALTY)
                                     +(fucrm_minGenVioP[g,t]*VIOLATION_PENALTY) for g in 1:GENS)
                                     +sum(df_peakers.IHRC_B1_HR[k]*fuelprice_peakers[k,day]*fucrm_peakerOut_Block[k,1,t]
                                     +df_peakers.IHRC_B2_HR[k]*fuelprice_peakers[k,day]*fucrm_peakerOut_Block[k,2,t]
                                     +df_peakers.IHRC_B3_HR[k]*fuelprice_peakers[k,day]*fucrm_peakerOut_Block[k,3,t]
                                     +df_peakers.IHRC_B4_HR[k]*fuelprice_peakers[k,day]*fucrm_peakerOut_Block[k,4,t]
                                     +df_peakers.IHRC_B5_HR[k]*fuelprice_peakers[k,day]*fucrm_peakerOut_Block[k,5,t]
                                     +df_peakers.IHRC_B6_HR[k]*fuelprice_peakers[k,day]*fucrm_peakerOut_Block[k,6,t]
                                     +df_peakers.IHRC_B7_HR[k]*fuelprice_peakers[k,day]*fucrm_peakerOut_Block[k,7,t]
                                     +df_peakers.NoLoadHR[k]*fuelprice_peakers[k,day]*fucrm_peakerOnOff[k,t]
                                     +((df_peakers.HotStartU_FixedCost[k]
                                     +(df_peakers.HotStartU_HeatRate[k]*fuelprice_peakers[k,day]))*fucrm_peakerStartUp[k,t])
                                     +df_peakers.ShutdownCost[k]*fucrm_peakerShutDown[k, t] for k in 1:PEAKERS) for t in 1:HRS_FUCR)
                                     +sum(sum((fucrm_demand_curt[n,t]*LOAD_SHED_PENALTY)
                                     +(fucrm_overgen[n,t]*OVERGEN_PENALTY) for n=1:N_ZONES) for t=1:HRS_FUCR))

   #Initialization of commitment and dispatch variables for convnentioal generatoes at t=0 (representing the last hour of previous scheduling horizon day=day-1 and t=24)
   @constraint(model, conInitGenOnOff[g=1:GENS], fucrm_genOnOff[g,0]==fucr_results.gens.onoff_init[g]) # initial generation level for generator g at t=0
   @constraint(model, conInitGenOut[g=1:GENS], fucrm_genOut[g,0]==fucr_results.gens.power_out[g]) # initial on/off status for generators g at t=0
   #Initialization of commitment and dispatch variables for peakers  at t=0 (representing the last hour of previous scheduling horizon day=day-1 and t=24)
   @constraint(model, conInitGenOnOff_Peakers[k=1:PEAKERS], fucrm_peakerOnOff[k,0]==fucr_results.peakers.onoff_init[k]) # initial generation level for peaker k at t=0
   @constraint(model, conInitGenOut_Peakers[k=1:PEAKERS], fucrm_peakerOut[k,0]==fucr_results.peakers.power_out[k]) # initial on/off status for peaker k at t=0
   #Initialization of SOC variables for storage units at t=0 (representing the last hour of previous scheduling horizon day=day-1 and t=24)
   @constraint(model, conInitSOC[p=1:STORG_UNITS], fucrm_storgSOC[p,0]==fucr_results.storg.soc_init[p]) # SOC for storage unit p at t=0

   #Base-Load Operation of nuclear Generators
   @constraint(model, conNuckBaseLoad[t=1:HRS_FUCR, g=1:GENS], fucrm_genOnOff[g,t]>=df_gens.Nuclear[g]) #
   @constraint(model, conNuclearTotGenZone[t=1:HRS_FUCR, n=1:N_ZONES], sum((fucrm_genOut[g,t]*Map_Gens[g,n]*df_gens.Nuclear[g]) for g=1:GENS) -fucr_prep_demand.nuclear_wa[t,n] ==0)

   #Limits on generation of cogen units
   @constraint(model, conCoGenBaseLoad[t=1:HRS_FUCR, g=1:GENS], fucrm_genOnOff[g,t]>=df_gens.Cogen[g]) #
   @constraint(model, conCoGenTotGenZone[t=1:HRS_FUCR, n=1:N_ZONES], sum((fucrm_genOut[g,t]*Map_Gens[g,n]*df_gens.Cogen[g]) for g=1:GENS) -fucr_prep_demand.cogen_wa[t,n] ==0)

   # Constraints representing technical limits of conventional generators
   #Status transition trajectory of
   @constraint(model, conStartUpAndDn[t=1:HRS_FUCR, g=1:GENS], (fucrm_genOnOff[g,t] - fucrm_genOnOff[g,t-1] - fucrm_genStartUp[g,t] + fucrm_genShutDown[g,t])==0)
   # Max Power generation limit in Block 1
   @constraint(model, conMaxPowBlock1[t=1:HRS_FUCR, g=1:GENS],  fucrm_genOut_Block[g,1,t] <= df_gens.IHRC_B1_Q[g]*fucrm_genOnOff[g,t] )
   # Max Power generation limit in Block 2
   @constraint(model, conMaxPowBlock2[t=1:HRS_FUCR, g=1:GENS],  fucrm_genOut_Block[g,2,t] <= df_gens.IHRC_B2_Q[g]*fucrm_genOnOff[g,t] )
   # Max Power generation limit in Block 3
   @constraint(model, conMaxPowBlock3[t=1:HRS_FUCR, g=1:GENS],  fucrm_genOut_Block[g,3,t] <= df_gens.IHRC_B3_Q[g]*fucrm_genOnOff[g,t] )
   # Max Power generation limit in Block 4
   @constraint(model, conMaxPowBlock4[t=1:HRS_FUCR, g=1:GENS],  fucrm_genOut_Block[g,4,t] <= df_gens.IHRC_B4_Q[g]*fucrm_genOnOff[g,t] )
   # Max Power generation limit in Block 5
   @constraint(model, conMaxPowBlock5[t=1:HRS_FUCR, g=1:GENS],  fucrm_genOut_Block[g,5,t] <= df_gens.IHRC_B5_Q[g]*fucrm_genOnOff[g,t] )
   # Max Power generation limit in Block 6
   @constraint(model, conMaxPowBlock6[t=1:HRS_FUCR, g=1:GENS],  fucrm_genOut_Block[g,6,t] <= df_gens.IHRC_B6_Q[g]*fucrm_genOnOff[g,t] )
   # Max Power generation limit in Block 7
   @constraint(model, conMaxPowBlock7[t=1:HRS_FUCR, g=1:GENS],  fucrm_genOut_Block[g,7,t] <= df_gens.IHRC_B7_Q[g]*fucrm_genOnOff[g,t] )
   # Total Production of each generation equals the sum of generation from its all blocks
   @constraint(model, conTotalGen[t=1:HRS_FUCR, g=1:GENS],  sum(fucrm_genOut_Block[g,b,t] for b=1:BLOCKS) + fucrm_totGenVioP[g,t] - fucrm_totGenVioN[g,t] ==fucrm_genOut[g,t])
   #Max power generation limit
   @constraint(model, conMaxPow[t=1:HRS_FUCR, g=1:GENS],  fucrm_genOut[g,t]+fucrm_genResUp[g,t] - fucrm_maxGenVioP[g,t] <= df_gens.MaxPowerOut[g]*fucrm_genOnOff[g,t] )
   # Min power generation limit
   @constraint(model, conMinPow[t=1:HRS_FUCR, g=1:GENS],  fucrm_genOut[g,t]-fucrm_genResDn[g,t] + fucrm_minGenVioP[g,t] >= df_gens.MinPowerOut[g]*fucrm_genOnOff[g,t] )
   # Up reserve provision limit
   @constraint(model, conMaxResUp[t=1:HRS_FUCR, g=1:GENS], fucrm_genResUp[g,t] <= df_gens.SpinningRes_Limit[g]*fucrm_genOnOff[g,t] )
   # Non-Spinning Reserve Limit
   #    @constraint(model, conMaxNonSpinResUp[t=1:HRS_SUCR, g=1:GENS], fucrm_genResNonSpin[g,t] <= (df_gens.NonSpinningRes_Limit[g]*(1-fucrm_genOnOff[g,t])*df_gens.FastStart[g]))
   @constraint(model, conMaxNonSpinResUp[t=1:HRS_SUCR, g=1:GENS], fucrm_genResNonSpin[g,t] <= 0)
   #Down reserve provision limit
   @constraint(model, conMaxResDown[t=1:HRS_FUCR, g=1:GENS],  fucrm_genResDn[g,t] <= df_gens.SpinningRes_Limit[g]*fucrm_genOnOff[g,t] )
   #Up ramp rate limit
   @constraint(model, conRampRateUp[t=1:HRS_FUCR, g=1:GENS], (fucrm_genOut[g,t] - fucrm_genOut[g,t-1] <=(df_gens.RampUpLimit[g]*fucrm_genOnOff[g, t-1]) + (df_gens.RampStartUpLimit[g]*fucrm_genStartUp[g,t])))
   # Down ramp rate limit
   @constraint(model, conRampRateDown[t=1:HRS_FUCR, g=1:GENS], (fucrm_genOut[g,t-1] - fucrm_genOut[g,t] <=(df_gens.RampDownLimit[g]*fucrm_genOnOff[g,t]) + (df_gens.RampShutDownLimit[g]*fucrm_genShutDown[g,t])))
   # Min Up Time limit with alternative formulation
   @constraint(model, conUpTime[t=1:HRS_FUCR, g=1:GENS], (sum(fucrm_genStartUp[g,r] for r=lb_MUT[g,t]:t)<=fucrm_genOnOff[g,t]))
   # Min down Time limit with alternative formulation
   @constraint(model, conDownTime[t=1:HRS_FUCR, g=1:GENS], (1-sum(fucrm_genShutDown[g,s] for s=lb_MDT[g,t]:t)>=fucrm_genOnOff[g,t]))

   # Peaker Units' constraints
   #Status transition trajectory of
   @constraint(model, conStartUpAndDn_Peaker[t=1:HRS_FUCR, k=1:PEAKERS], (fucrm_peakerOnOff[k,t] - fucrm_peakerOnOff[k,t-1] - fucrm_peakerStartUp[k,t] + fucrm_peakerShutDown[k,t])==0)
   # Max Power generation limit in Block 1
   @constraint(model, conMaxPowBlock1_Peaker[t=1:HRS_FUCR, k=1:PEAKERS],  fucrm_peakerOut_Block[k,1,t] <= df_peakers.IHRC_B1_Q[k]*fucrm_peakerOnOff[k,t] )
   # Max Power generation limit in Block 2
   @constraint(model, conMaxPowBlock2_Peaker[t=1:HRS_FUCR, k=1:PEAKERS],  fucrm_peakerOut_Block[k,2,t] <= df_peakers.IHRC_B2_Q[k]*fucrm_peakerOnOff[k,t] )
   # Max Power generation limit in Block 3
   @constraint(model, conMaxPowBlock3_Peaker[t=1:HRS_FUCR, k=1:PEAKERS],  fucrm_peakerOut_Block[k,3,t] <= df_peakers.IHRC_B3_Q[k]*fucrm_peakerOnOff[k,t] )
   # Max Power generation limit in Block 4
   @constraint(model, conMaxPowBlock4_Peaker[t=1:HRS_FUCR, k=1:PEAKERS],  fucrm_peakerOut_Block[k,4,t] <= df_peakers.IHRC_B4_Q[k]*fucrm_peakerOnOff[k,t] )
   # Max Power generation limit in Block 5
   @constraint(model, conMaxPowBlock5_Peaker[t=1:HRS_FUCR, k=1:PEAKERS],  fucrm_peakerOut_Block[k,5,t] <= df_peakers.IHRC_B5_Q[k]*fucrm_peakerOnOff[k,t] )
   # Max Power generation limit in Block 6
   @constraint(model, conMaxPowBlock6_Peaker[t=1:HRS_FUCR, k=1:PEAKERS],  fucrm_peakerOut_Block[k,6,t] <= df_peakers.IHRC_B6_Q[k]*fucrm_peakerOnOff[k,t] )
   # Max Power generation limit in Block 7
   @constraint(model, conMaxPowBlock7_Peaker[t=1:HRS_FUCR, k=1:PEAKERS],  fucrm_peakerOut_Block[k,7,t] <= df_peakers.IHRC_B7_Q[k]*fucrm_peakerOnOff[k,t] )
   # Total Production of each generation equals the sum of generation from its all blocks
   @constraint(model, conTotalGen_Peaker[t=1:HRS_FUCR, k=1:PEAKERS],  sum(fucrm_peakerOut_Block[k,b,t] for b=1:BLOCKS)>=fucrm_peakerOut[k,t])
   #Max power generation limit
   @constraint(model, conMaxPow_Peaker[t=1:HRS_FUCR, k=1:PEAKERS],  fucrm_peakerOut[k,t]+fucrm_peakerResUp[k,t] <= df_peakers.MaxPowerOut[k]*fucrm_peakerOnOff[k,t] )
   # Min power generation limit
   @constraint(model, conMinPow_Peaker[t=1:HRS_FUCR, k=1:PEAKERS],  fucrm_peakerOut[k,t]-fucrm_peakerResDn[k,t] >= df_peakers.MinPowerOut[k]*fucrm_peakerOnOff[k,t] )
   # Up reserve provision limit
   @constraint(model, conMaxResUp_Peaker[t=1:HRS_FUCR, k=1:PEAKERS], fucrm_peakerResUp[k,t] <= df_peakers.SpinningRes_Limit[k]*fucrm_peakerOnOff[k,t] )
   # Non-Spinning Reserve Limit
   @constraint(model, conMaxNonSpinResUp_Peaker[t=1:HRS_SUCR, k=1:PEAKERS], fucrm_peakerResNonSpin[k,t] <= (df_peakers.NonSpinningRes_Limit[k]*(1-fucrm_peakerOnOff[k,t])))
   #Down reserve provision limit
   @constraint(model, conMaxResDown_Peaker[t=1:HRS_FUCR, k=1:PEAKERS],  fucrm_peakerResDn[k,t] <= df_peakers.SpinningRes_Limit[k]*fucrm_peakerOnOff[k,t] )
   #Up ramp rate limit
   @constraint(model, conRampRateUp_Peaker[t=1:HRS_FUCR, k=1:PEAKERS], (fucrm_peakerOut[k,t] - fucrm_peakerOut[k,t-1] <=(df_peakers.RampUpLimit[k]*fucrm_peakerOnOff[k, t-1]) + (df_peakers.RampStartUpLimit[k]*fucrm_peakerStartUp[k,t])))
   # Down ramp rate limit
   @constraint(model, conRampRateDown_Peaker[t=1:HRS_FUCR, k=1:PEAKERS], (fucrm_peakerOut[k,t-1] - fucrm_peakerOut[k,t] <=(df_peakers.RampDownLimit[k]*fucrm_peakerOnOff[k,t]) + (df_peakers.RampShutDownLimit[k]*fucrm_peakerShutDown[k,t])))
   # Min Up Time limit with alternative formulation
   @constraint(model, conUpTime_Peaker[t=1:HRS_FUCR, k=1:PEAKERS], (sum(fucrm_peakerStartUp[k,r] for r=lb_MUT_Peaker[k,t]:t)<=fucrm_peakerOnOff[k,t]))
   # Min down Time limit with alternative formulation
   @constraint(model, conDownTime_Peaker[t=1:HRS_FUCR, k=1:PEAKERS], (1-sum(fucrm_peakerShutDown[k,s] for s=lb_MDT_Peaker[k,t]:t)>=fucrm_peakerOnOff[k,t]))

   # Renewable generation constraints
   @constraint(model, conSolarLimit[t=1:HRS_FUCR, n=1:N_ZONES], fucrm_solarG[n, t] + fucrm_solarGSpil[n,t]<=fucr_prep_demand.solar_wa[t,n])
   @constraint(model, conWindLimit[t=1:HRS_FUCR, n=1:N_ZONES], fucrm_windG[n, t] + fucrm_windGSpil[n,t]<=fucr_prep_demand.wind_wa[t,n])
   @constraint(model, conHydroLimit[t=1:HRS_FUCR, n=1:N_ZONES], fucrm_hydroG[n, t] + fucrm_hydroGSpil[n,t]<=fucr_prep_demand.hydro_wa[t,n])

   #=
   @constraint(model, conSolarLimit[t=1:HRS_FUCR, n=1:N_ZONES], fucrm_solarG[n, t] + fucrm_solarGSpil[n,t]<=0)
   @constraint(model, conWindLimit[t=1:HRS_FUCR, n=1:N_ZONES], fucrm_windG[n, t] + fucrm_windGSpil[n,t]<=0)
   @constraint(model, conHydroLimit[t=1:HRS_FUCR, n=1:N_ZONES], fucrm_hydroG[n, t] + fucrm_hydroGSpil[n,t]<=0)
   =#

   # Constraints representing technical characteristics of storage units
   # status transition of storage units between charging, discharging, and idle modes
   @constraint(model, conStorgStatusTransition[t=1:HRS_FUCR, p=1:STORG_UNITS], (fucrm_storgChrg[p,t]+fucrm_storgDisc[p,t]+fucrm_storgIdle[p,t])==1)
   # charging power limit
   @constraint(model, conStrgChargPowerLimit[t=1:HRS_FUCR, p=1:STORG_UNITS], (fucrm_storgChrgPwr[p,t] - fucrm_storgResDn[p,t])<=df_storage.Power[p]*fucrm_storgChrg[p,t])
   # Discharging power limit
   @constraint(model, conStrgDisChgPowerLimit[t=1:HRS_FUCR, p=1:STORG_UNITS], (fucrm_storgDiscPwr[p,t] + fucrm_storgResUp[p,t])<=df_storage.Power[p]*fucrm_storgDisc[p,t])
   # Down reserve provision limit
   @constraint(model, conStrgDownResrvMax[t=1:HRS_FUCR, p=1:STORG_UNITS], fucrm_storgResDn[p,t]<=df_storage.Power[p]*fucrm_storgChrg[p,t])
   # Up reserve provision limit`
   @constraint(model, conStrgUpResrvMax[t=1:HRS_FUCR, p=1:STORG_UNITS], fucrm_storgResUp[p,t]<=df_storage.Power[p]*fucrm_storgDisc[p,t])
   # State of charge at t
   @constraint(model, conStorgSOC[t=1:HRS_FUCR, p=1:STORG_UNITS], fucrm_storgSOC[p,t]==fucrm_storgSOC[p,t-1]-(fucrm_storgDiscPwr[p,t]/df_storage.TripEfficDown[p])+(fucrm_storgChrgPwr[p,t]*df_storage.TripEfficUp[p])-(fucrm_storgSOC[p,t]*df_storage.SelfDischarge[p]))
   # minimum energy limit
   @constraint(model, conMinEnrgStorgLimi[t=1:HRS_FUCR, p=1:STORG_UNITS], fucrm_storgSOC[p,t]-(fucrm_storgResUp[p,t]/df_storage.TripEfficDown[p])+(fucrm_storgResDn[p,t]/df_storage.TripEfficUp[p])>=0)
   # Maximum energy limit
   @constraint(model, conMaxEnrgStorgLimi[t=1:HRS_FUCR, p=1:STORG_UNITS], fucrm_storgSOC[p,t]-(fucrm_storgResUp[p,t]/df_storage.TripEfficDown[p])+(fucrm_storgResDn[p,t]/df_storage.TripEfficUp[p])<=(df_storage.Power[p]/df_storage.PowerToEnergRatio[p]))
   # Constraints representing transmission grid capacity constraints
   # DC Power Flow Calculation
   #@constraint(model, conDCPowerFlowPos[t=1:HRS_FUCR, n=1:N_ZONES, m=1:N_ZONES], fucrm_powerflow[n,m,t]-(TranS[n,m]*(fucrm_voltangle[n,t]-fucrm_voltangle[m,t])) ==0)
   @constraint(model, conDCPowerFlowNeg[t=1:HRS_FUCR, n=1:N_ZONES, m=1:N_ZONES], fucrm_powerflow[n,m,t]+fucrm_powerflow[m,n,t]==0)
   # Tranmission flow bounds (from n to m and from m to n)
   @constraint(model, conPosFlowLimit[t=1:HRS_FUCR, n=1:N_ZONES, m=1:N_ZONES], fucrm_powerflow[n,m,t]<=TranC[n,m])
   @constraint(model, conNegFlowLimit[t=1:HRS_FUCR, n=1:N_ZONES, m=1:N_ZONES], fucrm_powerflow[n,m,t]>=-TranC[n,m])
   # Voltage Angle bounds and reference point
   #@constraint(model, conVoltAnglUB[t=1:HRS_FUCR, n=1:N_ZONES], fucrm_voltangle[n,t]<=π)
   #@constraint(model, conVoltAnglLB[t=1:HRS_FUCR, n=1:N_ZONES], fucrm_voltangle[n,t]>=-π)
   #@constraint(model, conVoltAngRef[t=1:HRS_FUCR], fucrm_voltangle[1,t]==0)

   # Demand-side Constraints
   @constraint(model, conDemandLimit[t=1:HRS_FUCR, n=1:N_ZONES], fucrm_demand[n,t]+ fucrm_demand_curt[n,t] == fucr_prep_demand.wk_ahead[t,n])

   # Demand Curtailment and wind generation limits
   @constraint(model, conDemandCurtLimit[t=1:HRS_FUCR, n=1:N_ZONES], fucrm_demand_curt[n,t] <= LOAD_SHED_MAX);
   @constraint(model, conOverGenLimit[t=1:HRS_FUCR, n=1:N_ZONES], fucrm_overgen[n,t] <= OVERGEN_MAX);

   # System-wide Constraints
   #nodal balance constraint
   @constraint(model, conNodBalanc[t=1:HRS_FUCR, n=1:N_ZONES], sum((fucrm_genOut[g,t]*Map_Gens[g,n]) for g=1:GENS) +sum((fucrm_peakerOut[k,t]*Map_Peakers[k,n]) for k=1:PEAKERS)  + sum((fucrm_storgDiscPwr[p,t]*Map_Storage[p,n]) for p=1:STORG_UNITS) - sum((fucrm_storgChrgPwr[p,t]*Map_Storage[p,n]) for p=1:STORG_UNITS) +fucrm_solarG[n, t] +fucrm_windG[n, t] +fucrm_hydroG[n, t] - fucrm_demand[n,t] - fucrm_overgen[n,t]== sum(fucrm_powerflow[n,m,t] for m=1:M_ZONES))

   #@constraint(model, conNodBalanc[t=1:HRS_FUCR], sum(fucrm_genOut[g,t] for g=1:GENS) + sum((fucrm_storgDiscPwr[p,t]) for p=1:STORG_UNITS) - sum((fucrm_storgChrgPwr[p,t]) for p=1:STORG_UNITS) +sum(fucrm_solarG[n, t] for n=1:N_ZONES) + sum(fucrm_windG[n, t] for n=1:N_ZONES)+ sum(fucrm_hydroG[n, t] for n=1:N_ZONES) - sum(fucr_prep_demand.wk_ahead[t,n] for n=1:N_ZONES) == 0)

   # @constraint(model, conNodBalanc[t=1:HRS_FUCR], sum((fucrm_genOut[g,t]) for g=1:GENS) + sum((fucrm_storgDiscPwr[p,t]) for p=1:STORG_UNITS) - sum((fucrm_storgChrgPwr[p,t]) for p=1:STORG_UNITS) +sum((fucrm_solarG[n, t]) for n=1:N_ZONES) +sum((fucrm_windG[n, t]) for n=1:N_ZONES) +sum((fucrm_hydroG[n, t]) for n=1:N_ZONES) - sum((fucr_prep_demand.wk_ahead[t,n]) for n=1:N_ZONES) == 0)
   # Minimum zonal up reserve requirement, if there are more than two zones, we should  define reserve regions for DEC and DEP
   #@constraint(model, conMinUpReserveReq[t=1:HRS_FUCR, n=1:N_ZONES], sum((fucrm_genResUp[g,t]*Map_Gens[g,n]) for g=1:GENS) + sum((fucrm_storgResUp[p,t]*Map_Storage[p,n]) for p=1:STORG_UNITS) >= Reserve_Req_Up[n] )
   #@constraint(model, conMinUpReserveReq[t=1:HRS_FUCR], sum((fucrm_genResUp[g,t]+fucrm_genResNonSpin[g,t]) for g=1:GENS) + sum((fucrm_storgResUp[p,t]) for p=1:STORG_UNITS) >= sum(Reserve_Req_Up[n] for n=1:N_ZONES))
   @constraint(model, conMinUpReserveReq[t=1:HRS_FUCR], sum((fucrm_genResUp[g,t]) for g=1:GENS) + sum((fucrm_peakerResUp[k,t]+fucrm_peakerResNonSpin[k,t]) for k=1:PEAKERS)+ sum((fucrm_storgResUp[p,t]) for p=1:STORG_UNITS) >= sum(Reserve_Req_Up[n] for n=1:N_ZONES))


   # Minimum down reserve requirement
   #    @constraint(model, conMinDnReserveReq[t=1:HRS_FUCR], sum(genResDn[g,t] for g=1:GENS) + sum(storgResDn[p,t] for p=1:STORG_UNITS) >= Reserve_Req_Dn[t] )

   t2_FUCRmodel = time_ns()
   time_FUCRmodel = (t2_FUCRmodel -t1_FUCRmodel)/1.0e9;
   #@info "model for day: $day setup executed in (s): $time_FUCRmodel";

   open(".//outputs//csv//time_performance.csv", FILE_ACCESS_APPEND) do io
          writedlm(io, hcat("model", time_FUCRmodel, "day: $day",
                  "", "", "Model Setup"), ',')
   end; # closes file

   # solve the First WAUC model (fucr_results)
   JuMP.optimize!(model)

   # Pricing general results in the terminal window
   println("Objective value: ", JuMP.objective_value(model))

   println("------------------------------------")
   println("------- fucr_results OBJECTIVE VALUE -------")
   println("Objective value for day ", day, " is ", JuMP.objective_value(model))
   println("------------------------------------")
   println("-------fucr_results PRIMAL STATUS -------")
   println(primal_status(model))
   println("------------------------------------")
   println("------- fucr_results DUAL STATUS -------")
   println(JuMP.dual_status(model))
   println("Day: ", day, " solved")
   println("---------------------------")
   println("model Number of variables: ", JuMP.num_variables(model))

   #@info "model Number of variables: " JuMP.num_variables(model)

   open(".//outputs//csv//time_performance.csv", FILE_ACCESS_APPEND) do io
          writedlm(io, hcat("model", JuMP.num_variables(model), "day: $day",
                  "", "", "Variables"), ',')
   end;

    #@debug "model for day: $day optimized executed in (s):  $(solve_time(model))";

    open(".//outputs//csv//time_performance.csv", FILE_ACCESS_APPEND) do io
            writedlm(io, hcat("model", solve_time(model), "day: $day",
                    "", "", "Model Optimization"), ',')
    end; # closes file

    # Write the conventional generators' schedules in CSV file
    t1_write_FUCRmodel_results = time_ns()
    open(".//outputs//csv//FUCR_GenOutputs.csv", FILE_ACCESS_APPEND) do io
        for t in 1:HRS_FUCR, g=1:GENS
            writedlm(io, hcat(day, t+INIT_HR_FUCR, g, df_gens.UNIT_NAME[g],
                df_gens.MinPowerOut[g], df_gens.MaxPowerOut[g],
                JuMP.value.(fucrm_genOut[g,t]), JuMP.value.(fucrm_genOnOff[g,t]),
                JuMP.value.(fucrm_genShutDown[g,t]), JuMP.value.(fucrm_genStartUp[g,t]),
                JuMP.value.(fucrm_genResUp[g,t]), JuMP.value.(fucrm_genResNonSpin[g,t]),
                JuMP.value.(fucrm_genResDn[g,t]), JuMP.value.(fucrm_totGenVioP[g,t]),
                JuMP.value.(fucrm_totGenVioN[g,t]), JuMP.value.(fucrm_maxGenVioP[g,t]),
                JuMP.value.(fucrm_minGenVioP[g,t]) ), ',')
        end # ends the loop
    end; # closes file
    # Write the peakers' schedules in CSV file
    open(".//outputs//csv//FUCR_PeakerOutputs.csv", FILE_ACCESS_APPEND) do io
        for t in 1:HRS_FUCR, k=1:PEAKERS
            writedlm(io, hcat(day, t+INIT_HR_FUCR, k, df_peakers.UNIT_NAME[k],
               df_peakers.MinPowerOut[k], df_peakers.MaxPowerOut[k],
               JuMP.value.(fucrm_peakerOut[k,t]), JuMP.value.(fucrm_peakerOnOff[k,t]),
               JuMP.value.(fucrm_peakerShutDown[k,t]), JuMP.value.(fucrm_peakerStartUp[k,t]),
               JuMP.value.(fucrm_peakerResUp[k,t]), JuMP.value.(fucrm_peakerResNonSpin[k,t]),
               JuMP.value.(fucrm_peakerResDn[k,t]) ), ',')
        end # ends the loop
    end; # closes file

    # Writing storage units' optimal schedules in CSV file
    open(".//outputs//csv//FUCR_StorageOutputs.csv", FILE_ACCESS_APPEND) do io
         for t in 1:HRS_FUCR, p=1:STORG_UNITS
            writedlm(io, hcat(day, t+INIT_HR_FUCR, p, df_storage.Name[p],
                df_storage.Power[p], df_storage.Power[p]/df_storage.PowerToEnergRatio[p],
                JuMP.value.(fucrm_storgChrg[p,t]), JuMP.value.(fucrm_storgDisc[p,t]),
                JuMP.value.(fucrm_storgIdle[p,t]), JuMP.value.(fucrm_storgChrgPwr[p,t]),
                JuMP.value.(fucrm_storgDiscPwr[p,t]), JuMP.value.(fucrm_storgSOC[p,t]),
                JuMP.value.(fucrm_storgResUp[p,t]), JuMP.value.(fucrm_storgResDn[p,t]) ), ',')
         end # ends the loop
    end; # closes file

    # Writing the transmission line flows in CSV file
    open(".//outputs//csv//FUCR_TranFlowOutputs.csv", FILE_ACCESS_APPEND) do io
        for t in 1:HRS_FUCR, n=1:N_ZONES, m=1:M_ZONES
           writedlm(io, hcat(day, t+INIT_HR_FUCR, n,
               JuMP.value.(fucrm_powerflow[n,m,t]), TranC[n,m] ), ',')
        end # ends the loop
    end; # closes file

    # Writing the curtilment, overgeneration, and spillage outcomes in CSV file
    open(".//outputs//csv//FUCR_Curtail.csv", FILE_ACCESS_APPEND) do io
        for t in 1:HRS_FUCR, n=1:N_ZONES
           writedlm(io, hcat(day, t+INIT_HR_FUCR, n,
               JuMP.value.(fucrm_overgen[n,t]), JuMP.value.(fucrm_demand_curt[n,t]),
               JuMP.value.(fucrm_windGSpil[n,t]), JuMP.value.(fucrm_solarGSpil[n,t]),
               JuMP.value.(fucrm_hydroGSpil[n,t])), ',')
        end # ends the loop
    end; # closes file

    t2_write_FUCRmodel_results = time_ns()

    time_write_FUCRmodel_results = (t2_write_FUCRmodel_results -t1_write_FUCRmodel_results)/1.0e9;
    @info "Write model results for day $day: $time_write_FUCRmodel_results executed in (s)";

    open(".//outputs//csv//time_performance.csv", FILE_ACCESS_APPEND) do io
            writedlm(io, hcat("model", time_write_FUCRmodel_results, "day: $day",
                    "", "", "Write CSV files"), ',')
    end; #closes file

    t1_FUCRtoBUCR1_data_hand = time_ns()
    # Create and save the following parameters to be passed to BUCR1
    for h=1:INIT_HR_SUCR-INIT_HR_FUCR
         for g=1:GENS
             uc_results.gens.onoff[g,h]= JuMP.value.(fucrm_genOnOff[g,h]);
             uc_results.gens.power_out[g,h]= JuMP.value.(fucrm_genOut[g,h]);
             uc_results.gens.startup[g,h]= JuMP.value.(fucrm_genStartUp[g,h]);
             uc_results.gens.shutdown[g,h]=JuMP.value.(fucrm_genShutDown[g,h]);
             for b=1:BLOCKS
                 uc_results.gens.genout_block[g,b,h]=JuMP.value.(fucrm_genOut_Block[g,b,h]);
             end
         end
         for k=1:PEAKERS
             uc_results.peakers.onoff[k,h]= round(JuMP.value.(fucrm_peakerOnOff[k,h]));
             uc_results.peakers.power_out[k,h]=JuMP.value.(fucrm_peakerOut[k,h]);
             uc_results.peakers.startup[k,h]= round(JuMP.value.(fucrm_peakerStartUp[k,h]));
             uc_results.peakers.shutdown[k,h]= round(JuMP.value.(fucrm_peakerShutDown[k,h]));
             for b=1:BLOCKS
                 uc_results.peakers.genout_block[k,b,h]=JuMP.value.(fucrm_peakerOut_Block[k,b,h]);
             end
         end
         for p=1:STORG_UNITS
             uc_results.storg.chrg[p,h]=JuMP.value.(fucrm_storgChrg[p,h]);
             uc_results.storg.disc[p,h]=JuMP.value.(fucrm_storgDisc[p,h]);
             uc_results.storg.idle[p,h]=JuMP.value.(fucrm_storgIdle[p,h]);
             uc_results.storg.chrgpwr[p,h]=JuMP.value.(fucrm_storgChrgPwr[p,h]);
             uc_results.storg.discpwr[p,h]=JuMP.value.(fucrm_storgDiscPwr[p,h]);
             uc_results.storg.soc[p,h]=JuMP.value.(fucrm_storgSOC[p,h]);
         end
     end

     t2_FUCRtoBUCR1_data_hand = time_ns();

     time_FUCRtoBUCR1_data_hand = (t2_FUCRtoBUCR1_data_hand -t1_FUCRtoBUCR1_data_hand)/1.0e9;
     #@info "FUCRtoBUCR1 data handling for day $day executed in (s): $time_FUCRtoBUCR1_data_hand";

     open(".//outputs//csv//time_performance.csv", FILE_ACCESS_APPEND) do io
             writedlm(io, hcat("FUCRmodel", time_FUCRtoBUCR1_data_hand, "day: $day",
                     " ", "Pre-processing variables", "Data Manipulation"), ',')
     end; #closes file

     return uc_results;
end
