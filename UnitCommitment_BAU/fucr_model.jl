function fucr_model(day::Int64, df_gens::DataFrame, df_peakers::DataFrame,
	df_storage::DataFrame, fuelprice::Matrix{Float64},
	fuelprice_peakers::Matrix{Float64},  map_gens::Matrix{Int64},
	map_peakers::Matrix{Int64}, map_storage::Matrix{Int64},
	fucr_results::UC_Results, fucr_prepoc::DemandWAPreprocGens,
	lb_MDT::Matrix{Int64}, lb_MUT::Matrix{Int64},
	lb_MDT_peaker::Matrix{Int64}, lb_MUT_peaker::Matrix{Int64})

	t1_FUCRmodel = time_ns()

	uc_gens = GensResults();
	uc_peakers = PeakersResults();
	uc_storg = StorageResults();
	uc_results = UC_Results(uc_gens, uc_peakers, uc_storg);

	FUCRmodel = direct_model(CPLEX.Optimizer())
	# Enable Benders strategy
	#MOI.set(FUCRmodel, MOI.RawParameter("CPXPARAM_Benders_Strategy"), 3)
	set_optimizer_attribute(FUCRmodel, "CPX_PARAM_EPGAP", SOLVER_EPGAP)

  	# Declaring the decision variables for conventional generators
	@variable(FUCRmodel, fucrm_genOnOff[1:GENS, 0:HRS_FUCR], Bin) #Bin
	@variable(FUCRmodel, fucrm_genStartUp[1:GENS, 1:HRS_FUCR], Bin) # startup variable
	@variable(FUCRmodel, fucrm_genShutDown[1:GENS, 1:HRS_FUCR], Bin) # shutdown variable
	@variable(FUCRmodel, fucrm_genOut[1:GENS, 0:HRS_FUCR]>=0) # Generator's output schedule
	@variable(FUCRmodel, fucrm_genOut_Block[1:GENS, 1:BLOCKS, 1:HRS_FUCR]>=0) # Generator's output schedule from each block (block rfers to IHR curve blocks/segments)
	@variable(FUCRmodel, fucrm_genResUp[1:GENS, 1:HRS_FUCR]>=0) # Generators' up reserve schedule
	@variable(FUCRmodel, fucrm_genResNonSpin[1:GENS, 1:HRS_FUCR]>=0) # Scheduled up reserve on offline fast-start peakers
	@variable(FUCRmodel, fucrm_genResDn[1:GENS, 1:HRS_FUCR]>=0) # Generator's down rserve schedule
	@variable(FUCRmodel, fucrm_TotGenVioP[g=1:GENS, 1:HRS_FUCR]>=0)
	@variable(FUCRmodel, fucrm_TotGenVioN[g=1:GENS, 1:HRS_FUCR]>=0)
	@variable(FUCRmodel, fucrm_MaxGenVioP[g=1:GENS, 1:HRS_FUCR]>=0)
	@variable(FUCRmodel, fucrm_MinGenVioP[g=1:GENS, 1:HRS_FUCR]>=0)

  	# Declaring the decision variables for peaker units
	@variable(FUCRmodel, 0<=fucrm_peakerOnOff[1:PEAKERS, 0:HRS_FUCR]<=1)
	@variable(FUCRmodel, 0<=fucrm_peakerStartUp[1:PEAKERS, 1:HRS_FUCR]<=1)
	@variable(FUCRmodel, 0<=fucrm_peakerShutDown[1:PEAKERS, 1:HRS_FUCR]<=1)
	@variable(FUCRmodel, fucrm_peakerOut[1:PEAKERS, 0:HRS_FUCR]>=0) # Generator's output schedule
	@variable(FUCRmodel, fucrm_peakerOut_Block[1:PEAKERS, 1:BLOCKS, 1:HRS_FUCR]>=0) # Generator's output schedule from each block (block rfers to IHR curve blocks/segments)
	@variable(FUCRmodel, fucrm_peakerResUp[1:PEAKERS, 1:HRS_FUCR]>=0) # Generators' up reserve schedule
	@variable(FUCRmodel, fucrm_peakerResNonSpin[1:PEAKERS, 1:HRS_FUCR]>=0) # Scheduled up reserve on offline fast-start peakers
	@variable(FUCRmodel, fucrm_peakerResDn[1:PEAKERS, 1:HRS_FUCR]>=0) # Generator's down rserve schedule

    # declaring decision variables for storage Units
	@variable(FUCRmodel, fucrm_storgChrg[1:STORG_UNITS, 1:HRS_FUCR], Bin) #Bin variable equal to 1 if unit runs in the charging mode
	@variable(FUCRmodel, fucrm_storgDisc[1:STORG_UNITS, 1:HRS_FUCR], Bin) #Bin variable equal to 1 if unit runs in the discharging mode
	@variable(FUCRmodel, fucrm_storgIdle[1:STORG_UNITS, 1:HRS_FUCR], Bin) ##Bin variable equal to 1 if unit runs in the idle mode
	@variable(FUCRmodel, fucrm_storgChrgPwr[1:STORG_UNITS, 0:HRS_FUCR]>=0) #Chargung power
	@variable(FUCRmodel, fucrm_storgDiscPwr[1:STORG_UNITS, 0:HRS_FUCR]>=0) # Discharging Power
	@variable(FUCRmodel, fucrm_storgSOC[1:STORG_UNITS, 0:HRS_FUCR]>=0) # state of charge (stored energy level for storage unit at time t)
	@variable(FUCRmodel, fucrm_storgResUp[1:STORG_UNITS, 0:HRS_FUCR]>=0) # Scheduled up reserve
	@variable(FUCRmodel, fucrm_storgResDn[1:STORG_UNITS, 0:HRS_FUCR]>=0) # Scheduled down reserve

	# declaring decision variables for renewable generation
	@variable(FUCRmodel, fucrm_solarG[1:N_ZONES, 1:HRS_FUCR]>=0) # solar energy schedules
	@variable(FUCRmodel, fucrm_windG[1:N_ZONES, 1:HRS_FUCR]>=0) # wind energy schedules
	@variable(FUCRmodel, fucrm_hydroG[1:N_ZONES, 1:HRS_FUCR]>=0) # hydro energy schedules
	@variable(FUCRmodel, fucrm_solarGSpil[1:N_ZONES, 1:HRS_FUCR]>=0) # solar energy schedules
	@variable(FUCRmodel, fucrm_windGSpil[1:N_ZONES, 1:HRS_FUCR]>=0) # wind energy schedules
	@variable(FUCRmodel, fucrm_hydroGSpil[1:N_ZONES, 1:HRS_FUCR]>=0) # hydro energy schedules

	# Declaring decision variables for hourly dispatched and curtailed demand
	@variable(FUCRmodel, fucrm_Demand[1:N_ZONES, 1:HRS_FUCR]>=0) # Hourly scheduled demand
	@variable(FUCRmodel, fucrm_Demand_Curt[1:N_ZONES, 1:HRS_FUCR]>=0) # Hourly schedule demand

	# Declaring variables for transmission system
	@variable(FUCRmodel, fucrm_voltAngle[1:N_ZONES, 1:HRS_FUCR]) #voltage angle at zone/bus n in t//
	@variable(FUCRmodel, fucrm_powerFlow[1:N_ZONES, 1:M_ZONES, 1:HRS_FUCR]) #transmission Flow from zone n to zone m//

	# Declaring over and undergeneration decision variable
	@variable(FUCRmodel, fucrm_OverGen[1:N_ZONES, 1:HRS_FUCR]>=0) #overgeneration at zone n and time t//

    # Defining the objective function that minimizes the overal cost of supplying electricity (=total variable, no-load, startup, and shutdown costs)
	@objective(FUCRmodel, Min, sum(sum(df_gens.IHRC_B1_HR[g]*fuelprice[g,day]*fucrm_genOut_Block[g,1,t]
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
         +(fucrm_TotGenVioP[g,t]*VIOLATION_PENALTY)
         +(fucrm_TotGenVioN[g,t]*VIOLATION_PENALTY)
         +(fucrm_MaxGenVioP[g,t]*VIOLATION_PENALTY)
         +(fucrm_MinGenVioP[g,t]*VIOLATION_PENALTY) for g in 1:GENS)
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
         +sum(sum((fucrm_Demand_Curt[n,t]*LOAD_SHED_PENALTY)
         +(fucrm_OverGen[n,t]*OVERGEN_PENALTY) for n=1:N_ZONES) for t=1:HRS_FUCR))

	#Initialization of commitment and dispatch variables for convnentioal generatoes at t=0 (representing the last hour of previous scheduling horizon day=day-1 and t=24)
	@constraint(FUCRmodel, conInitGenOnOff[g=1:GENS], fucrm_genOnOff[g,0]==fucr_results.gens.onoff_init[g]) # initial generation level for generator g at t=0
	@constraint(FUCRmodel, conInitGenOut[g=1:GENS], fucrm_genOut[g,0]==fucr_results.gens.power_out_init[g]) # initial on/off status for generators g at t=0
	#Initialization of commitment and dispatch variables for peakers  at t=0 (representing the last hour of previous scheduling horizon day=day-1 and t=24)
	@constraint(FUCRmodel, conInitGenOnOff_Peakers[k=1:PEAKERS], fucrm_peakerOnOff[k,0]==fucr_results.peakers.onoff_init[k]) # initial generation level for peaker k at t=0
	@constraint(FUCRmodel, conInitGenOut_Peakers[k=1:PEAKERS], fucrm_peakerOut[k,0]==fucr_results.peakers.power_out_init[k]) # initial on/off status for peaker k at t=0
	#Initialization of SOC variables for storage units at t=0 (representing the last hour of previous scheduling horizon day=day-1 and t=24)
	@constraint(FUCRmodel, conInitSOC[p=1:STORG_UNITS], fucrm_storgSOC[p,0]==fucr_results.storg.soc_init[p]) # SOC for storage unit p at t=0

	#Base-Load Operation of nuclear Generators
	@constraint(FUCRmodel, conNuckBaseLoad[t=1:HRS_FUCR, g=1:GENS], fucrm_genOnOff[g,t]>=df_gens.Nuclear[g]) #
	@constraint(FUCRmodel, conNuclearTotGenZone[t=1:HRS_FUCR, n=1:N_ZONES], sum((fucrm_genOut[g,t]*map_gens[g,n]*df_gens.Nuclear[g]) for g=1:GENS) -fucr_prepoc.nuclear_wa[t,n] ==0)

	#Limits on generation of cogen units
	@constraint(FUCRmodel, conCoGenBaseLoad[t=1:HRS_FUCR, g=1:GENS], fucrm_genOnOff[g,t]>=df_gens.Cogen[g]) #
	@constraint(FUCRmodel, conCoGenTotGenZone[t=1:HRS_FUCR, n=1:N_ZONES], sum((fucrm_genOut[g,t]*map_gens[g,n]*df_gens.Cogen[g]) for g=1:GENS) -fucr_prepoc.cogen_wa[t,n] ==0)

	# Constraints representing technical limits of conventional generators
	#Status transition trajectory of
	@constraint(FUCRmodel, conStartUpAndDn[t=1:HRS_FUCR, g=1:GENS], (fucrm_genOnOff[g,t] - fucrm_genOnOff[g,t-1] - fucrm_genStartUp[g,t] + fucrm_genShutDown[g,t])==0)
	# Max Power generation limit in Block 1
	@constraint(FUCRmodel, conMaxPowBlock1[t=1:HRS_FUCR, g=1:GENS],  fucrm_genOut_Block[g,1,t] <= df_gens.IHRC_B1_Q[g]*fucrm_genOnOff[g,t] )
	# Max Power generation limit in Block 2
	@constraint(FUCRmodel, conMaxPowBlock2[t=1:HRS_FUCR, g=1:GENS],  fucrm_genOut_Block[g,2,t] <= df_gens.IHRC_B2_Q[g]*fucrm_genOnOff[g,t] )
	# Max Power generation limit in Block 3
	@constraint(FUCRmodel, conMaxPowBlock3[t=1:HRS_FUCR, g=1:GENS],  fucrm_genOut_Block[g,3,t] <= df_gens.IHRC_B3_Q[g]*fucrm_genOnOff[g,t] )
	# Max Power generation limit in Block 4
	@constraint(FUCRmodel, conMaxPowBlock4[t=1:HRS_FUCR, g=1:GENS],  fucrm_genOut_Block[g,4,t] <= df_gens.IHRC_B4_Q[g]*fucrm_genOnOff[g,t] )
	# Max Power generation limit in Block 5
	@constraint(FUCRmodel, conMaxPowBlock5[t=1:HRS_FUCR, g=1:GENS],  fucrm_genOut_Block[g,5,t] <= df_gens.IHRC_B5_Q[g]*fucrm_genOnOff[g,t] )
	# Max Power generation limit in Block 6
	@constraint(FUCRmodel, conMaxPowBlock6[t=1:HRS_FUCR, g=1:GENS],  fucrm_genOut_Block[g,6,t] <= df_gens.IHRC_B6_Q[g]*fucrm_genOnOff[g,t] )
	# Max Power generation limit in Block 7
	@constraint(FUCRmodel, conMaxPowBlock7[t=1:HRS_FUCR, g=1:GENS],  fucrm_genOut_Block[g,7,t] <= df_gens.IHRC_B7_Q[g]*fucrm_genOnOff[g,t] )
	# Total Production of each generation equals the sum of generation from its all blocks
	@constraint(FUCRmodel, conTotalGen[t=1:HRS_FUCR, g=1:GENS],  sum(fucrm_genOut_Block[g,b,t] for b=1:BLOCKS) + fucrm_TotGenVioP[g,t] - fucrm_TotGenVioN[g,t] ==fucrm_genOut[g,t])
	#Max power generation limit
	@constraint(FUCRmodel, conMaxPow[t=1:HRS_FUCR, g=1:GENS],  fucrm_genOut[g,t]+fucrm_genResUp[g,t] - fucrm_MaxGenVioP[g,t] <= df_gens.MaxPowerOut[g]*fucrm_genOnOff[g,t] )
	# Min power generation limit
	@constraint(FUCRmodel, conMinPow[t=1:HRS_FUCR, g=1:GENS],  fucrm_genOut[g,t]-fucrm_genResDn[g,t] + fucrm_MinGenVioP[g,t] >= df_gens.MinPowerOut[g]*fucrm_genOnOff[g,t] )
	# Up reserve provision limit
	@constraint(FUCRmodel, conMaxResUp[t=1:HRS_FUCR, g=1:GENS], fucrm_genResUp[g,t] <= df_gens.SpinningRes_Limit[g]*fucrm_genOnOff[g,t] )
	# Non-Spinning Reserve Limit
	#    @constraint(FUCRmodel, conMaxNonSpinResUp[t=1:HRS_SUCR, g=1:GENS], fucrm_genResNonSpin[g,t] <= (df_gens.NonSpinningRes_Limit[g]*(1-fucrm_genOnOff[g,t])*df_gens.FastStart[g]))
	@constraint(FUCRmodel, conMaxNonSpinResUp[t=1:HRS_SUCR, g=1:GENS], fucrm_genResNonSpin[g,t] <= 0)
	#Down reserve provision limit
	@constraint(FUCRmodel, conMaxResDown[t=1:HRS_FUCR, g=1:GENS],  fucrm_genResDn[g,t] <= df_gens.SpinningRes_Limit[g]*fucrm_genOnOff[g,t] )
	#Up ramp rate limit
	@constraint(FUCRmodel, conRampRateUp[t=1:HRS_FUCR, g=1:GENS], (fucrm_genOut[g,t] - fucrm_genOut[g,t-1] <=(df_gens.RampUpLimit[g]*fucrm_genOnOff[g, t-1]) + (df_gens.RampStartUpLimit[g]*fucrm_genStartUp[g,t])))
	# Down ramp rate limit
	@constraint(FUCRmodel, conRampRateDown[t=1:HRS_FUCR, g=1:GENS], (fucrm_genOut[g,t-1] - fucrm_genOut[g,t] <=(df_gens.RampDownLimit[g]*fucrm_genOnOff[g,t]) + (df_gens.RampShutDownLimit[g]*fucrm_genShutDown[g,t])))
	# Min Up Time limit with alternative formulation
	@constraint(FUCRmodel, conUpTime[t=1:HRS_FUCR, g=1:GENS], (sum(fucrm_genStartUp[g,r] for r=lb_MUT[g,t]:t)<=fucrm_genOnOff[g,t]))
	# Min down Time limit with alternative formulation
	@constraint(FUCRmodel, conDownTime[t=1:HRS_FUCR, g=1:GENS], (1-sum(fucrm_genShutDown[g,s] for s=lb_MDT[g,t]:t)>=fucrm_genOnOff[g,t]))

	# Peaker Units' constraints
	#Status transition trajectory of
	@constraint(FUCRmodel, conStartUpAndDn_Peaker[t=1:HRS_FUCR, k=1:PEAKERS], (fucrm_peakerOnOff[k,t] - fucrm_peakerOnOff[k,t-1] - fucrm_peakerStartUp[k,t] + fucrm_peakerShutDown[k,t])==0)
	# Max Power generation limit in Block 1
	@constraint(FUCRmodel, conMaxPowBlock1_Peaker[t=1:HRS_FUCR, k=1:PEAKERS],  fucrm_peakerOut_Block[k,1,t] <= df_peakers.IHRC_B1_Q[k]*fucrm_peakerOnOff[k,t] )
	# Max Power generation limit in Block 2
	@constraint(FUCRmodel, conMaxPowBlock2_Peaker[t=1:HRS_FUCR, k=1:PEAKERS],  fucrm_peakerOut_Block[k,2,t] <= df_peakers.IHRC_B2_Q[k]*fucrm_peakerOnOff[k,t] )
	# Max Power generation limit in Block 3
	@constraint(FUCRmodel, conMaxPowBlock3_Peaker[t=1:HRS_FUCR, k=1:PEAKERS],  fucrm_peakerOut_Block[k,3,t] <= df_peakers.IHRC_B3_Q[k]*fucrm_peakerOnOff[k,t] )
	# Max Power generation limit in Block 4
	@constraint(FUCRmodel, conMaxPowBlock4_Peaker[t=1:HRS_FUCR, k=1:PEAKERS],  fucrm_peakerOut_Block[k,4,t] <= df_peakers.IHRC_B4_Q[k]*fucrm_peakerOnOff[k,t] )
	# Max Power generation limit in Block 5
	@constraint(FUCRmodel, conMaxPowBlock5_Peaker[t=1:HRS_FUCR, k=1:PEAKERS],  fucrm_peakerOut_Block[k,5,t] <= df_peakers.IHRC_B5_Q[k]*fucrm_peakerOnOff[k,t] )
	# Max Power generation limit in Block 6
	@constraint(FUCRmodel, conMaxPowBlock6_Peaker[t=1:HRS_FUCR, k=1:PEAKERS],  fucrm_peakerOut_Block[k,6,t] <= df_peakers.IHRC_B6_Q[k]*fucrm_peakerOnOff[k,t] )
	# Max Power generation limit in Block 7
	@constraint(FUCRmodel, conMaxPowBlock7_Peaker[t=1:HRS_FUCR, k=1:PEAKERS],  fucrm_peakerOut_Block[k,7,t] <= df_peakers.IHRC_B7_Q[k]*fucrm_peakerOnOff[k,t] )
	# Total Production of each generation equals the sum of generation from its all blocks
	@constraint(FUCRmodel, conTotalGen_Peaker[t=1:HRS_FUCR, k=1:PEAKERS],  sum(fucrm_peakerOut_Block[k,b,t] for b=1:BLOCKS)>=fucrm_peakerOut[k,t])
	#Max power generation limit
	@constraint(FUCRmodel, conMaxPow_Peaker[t=1:HRS_FUCR, k=1:PEAKERS],  fucrm_peakerOut[k,t]+fucrm_peakerResUp[k,t] <= df_peakers.MaxPowerOut[k]*fucrm_peakerOnOff[k,t] )
	# Min power generation limit
	@constraint(FUCRmodel, conMinPow_Peaker[t=1:HRS_FUCR, k=1:PEAKERS],  fucrm_peakerOut[k,t]-fucrm_peakerResDn[k,t] >= df_peakers.MinPowerOut[k]*fucrm_peakerOnOff[k,t] )
	# Up reserve provision limit
	@constraint(FUCRmodel, conMaxResUp_Peaker[t=1:HRS_FUCR, k=1:PEAKERS], fucrm_peakerResUp[k,t] <= df_peakers.SpinningRes_Limit[k]*fucrm_peakerOnOff[k,t] )
	# Non-Spinning Reserve Limit
	@constraint(FUCRmodel, conMaxNonSpinResUp_Peaker[t=1:HRS_SUCR, k=1:PEAKERS], fucrm_peakerResNonSpin[k,t] <= (df_peakers.NonSpinningRes_Limit[k]*(1-fucrm_peakerOnOff[k,t])))
	#Down reserve provision limit
	@constraint(FUCRmodel, conMaxResDown_Peaker[t=1:HRS_FUCR, k=1:PEAKERS],  fucrm_peakerResDn[k,t] <= df_peakers.SpinningRes_Limit[k]*fucrm_peakerOnOff[k,t] )
	#Up ramp rate limit
	@constraint(FUCRmodel, conRampRateUp_Peaker[t=1:HRS_FUCR, k=1:PEAKERS], (fucrm_peakerOut[k,t] - fucrm_peakerOut[k,t-1] <=(df_peakers.RampUpLimit[k]*fucrm_peakerOnOff[k, t-1]) + (df_peakers.RampStartUpLimit[k]*fucrm_peakerStartUp[k,t])))
	# Down ramp rate limit
	@constraint(FUCRmodel, conRampRateDown_Peaker[t=1:HRS_FUCR, k=1:PEAKERS], (fucrm_peakerOut[k,t-1] - fucrm_peakerOut[k,t] <=(df_peakers.RampDownLimit[k]*fucrm_peakerOnOff[k,t]) + (df_peakers.RampShutDownLimit[k]*fucrm_peakerShutDown[k,t])))
	# Min Up Time limit with alternative formulation
	@constraint(FUCRmodel, conUpTime_Peaker[t=1:HRS_FUCR, k=1:PEAKERS], (sum(fucrm_peakerStartUp[k,r] for r=lb_MUT_peaker[k,t]:t)<=fucrm_peakerOnOff[k,t]))
	# Min down Time limit with alternative formulation
	@constraint(FUCRmodel, conDownTime_Peaker[t=1:HRS_FUCR, k=1:PEAKERS], (1-sum(fucrm_peakerShutDown[k,s] for s=lb_MDT_peaker[k,t]:t)>=fucrm_peakerOnOff[k,t]))

	# Renewable generation constraints
	@constraint(FUCRmodel, conSolarLimit[t=1:HRS_FUCR, n=1:N_ZONES], fucrm_solarG[n, t] + fucrm_solarGSpil[n,t]<=fucr_prepoc.solar_wa[t,n])
	@constraint(FUCRmodel, conWindLimit[t=1:HRS_FUCR, n=1:N_ZONES], fucrm_windG[n, t] + fucrm_windGSpil[n,t]<=fucr_prepoc.wind_wa[t,n])
	@constraint(FUCRmodel, conHydroLimit[t=1:HRS_FUCR, n=1:N_ZONES], fucrm_hydroG[n, t] + fucrm_hydroGSpil[n,t]<=fucr_prepoc.hydro_wa[t,n])

	#=
	@constraint(FUCRmodel, conSolarLimit[t=1:HRS_FUCR, n=1:N_ZONES], fucrm_solarG[n, t] + fucrm_solarGSpil[n,t]<=0)
	@constraint(FUCRmodel, conWindLimit[t=1:HRS_FUCR, n=1:N_ZONES], fucrm_windG[n, t] + fucrm_windGSpil[n,t]<=0)
	@constraint(FUCRmodel, conHydroLimit[t=1:HRS_FUCR, n=1:N_ZONES], fucrm_hydroG[n, t] + fucrm_hydroGSpil[n,t]<=0)
	=#

	# Constraints representing technical characteristics of storage units
	# status transition of storage units between charging, discharging, and idle modes
	@constraint(FUCRmodel, conStorgStatusTransition[t=1:HRS_FUCR, p=1:STORG_UNITS], (fucrm_storgChrg[p,t]+fucrm_storgDisc[p,t]+fucrm_storgIdle[p,t])==1)
	# charging power limit
	@constraint(FUCRmodel, conStrgChargPowerLimit[t=1:HRS_FUCR, p=1:STORG_UNITS], (fucrm_storgChrgPwr[p,t] - fucrm_storgResDn[p,t])<=df_storage.Power[p]*fucrm_storgChrg[p,t])
	# Discharging power limit
	@constraint(FUCRmodel, conStrgDisChgPowerLimit[t=1:HRS_FUCR, p=1:STORG_UNITS], (fucrm_storgDiscPwr[p,t] + fucrm_storgResUp[p,t])<=df_storage.Power[p]*fucrm_storgDisc[p,t])
	# Down reserve provision limit
	@constraint(FUCRmodel, conStrgDownResrvMax[t=1:HRS_FUCR, p=1:STORG_UNITS], fucrm_storgResDn[p,t]<=df_storage.Power[p]*fucrm_storgChrg[p,t])
	# Up reserve provision limit`
	@constraint(FUCRmodel, conStrgUpResrvMax[t=1:HRS_FUCR, p=1:STORG_UNITS], fucrm_storgResUp[p,t]<=df_storage.Power[p]*fucrm_storgDisc[p,t])
	# State of charge at t
	@constraint(FUCRmodel, conStorgSOC[t=1:HRS_FUCR, p=1:STORG_UNITS], fucrm_storgSOC[p,t]==fucrm_storgSOC[p,t-1]-(fucrm_storgDiscPwr[p,t]/df_storage.TripEfficDown[p])+(fucrm_storgChrgPwr[p,t]*df_storage.TripEfficUp[p])-(fucrm_storgSOC[p,t]*df_storage.SelfDischarge[p]))
	# minimum energy limit
	@constraint(FUCRmodel, conMinEnrgStorgLimi[t=1:HRS_FUCR, p=1:STORG_UNITS], fucrm_storgSOC[p,t]-(fucrm_storgResUp[p,t]/df_storage.TripEfficDown[p])+(fucrm_storgResDn[p,t]/df_storage.TripEfficUp[p])>=0)
	# Maximum energy limit
	@constraint(FUCRmodel, conMaxEnrgStorgLimi[t=1:HRS_FUCR, p=1:STORG_UNITS], fucrm_storgSOC[p,t]-(fucrm_storgResUp[p,t]/df_storage.TripEfficDown[p])+(fucrm_storgResDn[p,t]/df_storage.TripEfficUp[p])<=(df_storage.Power[p]/df_storage.PowerToEnergRatio[p]))
	# Constraints representing transmission grid capacity constraints
	# DC Power Flow Calculation
	#@constraint(FUCRmodel, conDCPowerFlowPos[t=1:HRS_FUCR, n=1:N_ZONES, m=1:N_ZONES], fucrm_powerFlow[n,m,t]-(TranS[n,m]*(fucrm_voltAngle[n,t]-fucrm_voltAngle[m,t])) ==0)
	@constraint(FUCRmodel, conDCPowerFlowNeg[t=1:HRS_FUCR, n=1:N_ZONES, m=1:N_ZONES], fucrm_powerFlow[n,m,t]+fucrm_powerFlow[m,n,t]==0)
	# Tranmission flow bounds (from n to m and from m to n)
	@constraint(FUCRmodel, conPosFlowLimit[t=1:HRS_FUCR, n=1:N_ZONES, m=1:N_ZONES], fucrm_powerFlow[n,m,t]<=TranC[n,m])
	@constraint(FUCRmodel, conNegFlowLimit[t=1:HRS_FUCR, n=1:N_ZONES, m=1:N_ZONES], fucrm_powerFlow[n,m,t]>=-TranC[n,m])
	# Voltage Angle bounds and reference point
	#@constraint(FUCRmodel, conVoltAnglUB[t=1:HRS_FUCR, n=1:N_ZONES], fucrm_voltAngle[n,t]<=π)
	#@constraint(FUCRmodel, conVoltAnglLB[t=1:HRS_FUCR, n=1:N_ZONES], fucrm_voltAngle[n,t]>=-π)
	#@constraint(FUCRmodel, conVoltAngRef[t=1:HRS_FUCR], fucrm_voltAngle[1,t]==0)

	# Demand-side Constraints
	@constraint(FUCRmodel, conDemandLimit[t=1:HRS_FUCR, n=1:N_ZONES], fucrm_Demand[n,t]+ fucrm_Demand_Curt[n,t] == fucr_prepoc.wk_ahead[t,n])

	# Demand Curtailment and wind generation limits
	@constraint(FUCRmodel, conDemandCurtLimit[t=1:HRS_FUCR, n=1:N_ZONES], fucrm_Demand_Curt[n,t] <= LOAD_SHED_MAX);
	@constraint(FUCRmodel, conOverGenLimit[t=1:HRS_FUCR, n=1:N_ZONES], fucrm_OverGen[n,t] <= OVERGEN_MAX);

	# System-wide Constraints
	#nodal balance constraint
	@constraint(FUCRmodel, conNodBalanc[t=1:HRS_FUCR, n=1:N_ZONES], sum((fucrm_genOut[g,t]*map_gens[g,n]) for g=1:GENS) +sum((fucrm_peakerOut[k,t]*map_peakers[k,n]) for k=1:PEAKERS)  + sum((fucrm_storgDiscPwr[p,t]*map_storage[p,n]) for p=1:STORG_UNITS) - sum((fucrm_storgChrgPwr[p,t]*map_storage[p,n]) for p=1:STORG_UNITS) +fucrm_solarG[n, t] +fucrm_windG[n, t] +fucrm_hydroG[n, t] - fucrm_Demand[n,t] - fucrm_OverGen[n,t]== sum(fucrm_powerFlow[n,m,t] for m=1:M_ZONES))

	#@constraint(FUCRmodel, conNodBalanc[t=1:HRS_FUCR], sum(fucrm_genOut[g,t] for g=1:GENS) + sum((fucrm_storgDiscPwr[p,t]) for p=1:STORG_UNITS) - sum((fucrm_storgChrgPwr[p,t]) for p=1:STORG_UNITS) +sum(fucrm_solarG[n, t] for n=1:N_ZONES) + sum(fucrm_windG[n, t] for n=1:N_ZONES)+ sum(fucrm_hydroG[n, t] for n=1:N_ZONES) - sum(fucr_prepoc.wk_ahead[t,n] for n=1:N_ZONES) == 0)

	# @constraint(FUCRmodel, conNodBalanc[t=1:HRS_FUCR], sum((fucrm_genOut[g,t]) for g=1:GENS) + sum((fucrm_storgDiscPwr[p,t]) for p=1:STORG_UNITS) - sum((fucrm_storgChrgPwr[p,t]) for p=1:STORG_UNITS) +sum((fucrm_solarG[n, t]) for n=1:N_ZONES) +sum((fucrm_windG[n, t]) for n=1:N_ZONES) +sum((fucrm_hydroG[n, t]) for n=1:N_ZONES) - sum((fucr_prepoc.wk_ahead[t,n]) for n=1:N_ZONES) == 0)
	# Minimum zonal up reserve requirement, if there are more than two zones, we should  define reserve regions for DEC and DEP
	#@constraint(FUCRmodel, conMinUpReserveReq[t=1:HRS_FUCR, n=1:N_ZONES], sum((fucrm_genResUp[g,t]*map_gens[g,n]) for g=1:GENS) + sum((fucrm_storgResUp[p,t]*map_storage[p,n]) for p=1:STORG_UNITS) >= Reserve_Req_Up[n] )
	#@constraint(FUCRmodel, conMinUpReserveReq[t=1:HRS_FUCR], sum((fucrm_genResUp[g,t]+fucrm_genResNonSpin[g,t]) for g=1:GENS) + sum((fucrm_storgResUp[p,t]) for p=1:STORG_UNITS) >= sum(Reserve_Req_Up[n] for n=1:N_ZONES))
	@constraint(FUCRmodel, conMinUpReserveReq[t=1:HRS_FUCR], sum((fucrm_genResUp[g,t]) for g=1:GENS) + sum((fucrm_peakerResUp[k,t]+fucrm_peakerResNonSpin[k,t]) for k=1:PEAKERS)+ sum((fucrm_storgResUp[p,t]) for p=1:STORG_UNITS) >= sum(Reserve_Req_Up[n] for n=1:N_ZONES))


	# Minimum down reserve requirement
	# @constraint(FUCRmodel, conMinDnReserveReq[t=1:HRS_FUCR], sum(genResDn[g,t] for g=1:GENS) + sum(storgResDn[p,t] for p=1:STORG_UNITS) >= Reserve_Req_Dn[t] )

	t2_FUCRmodel = time_ns()
	time_FUCRmodel = (t2_FUCRmodel -t1_FUCRmodel)/1.0e9;
	@info "FUCRmodel for day: $day setup executed in (s): $time_FUCRmodel";

	open(".//outputs//time_performance.csv", FILE_ACCESS_APPEND) do io
	      writedlm(io, hcat("FUCRmodel", time_FUCRmodel, "day: $day",
	              "", "", "Model Setup"), ',')
	end; # closes file

	# solve the First WAUC model (FUCR)
	JuMP.optimize!(FUCRmodel)

	# Pricing general results in the terminal window
	println("Objective value: ", JuMP.objective_value(FUCRmodel))

	open(".//outputs//objective_values_v76.csv", FILE_ACCESS_APPEND) do io
	      writedlm(io, hcat("FUCRmodel", "day: $day",
	              "", "", JuMP.objective_value(FUCRmodel)), ',')
	end;

	println("------------------------------------")
	println("------- FUCR OBJECTIVE VALUE -------")
	println("Objective value for day ", day, " is ", JuMP.objective_value(FUCRmodel))
	println("------------------------------------")
	println("-------FUCR PRIMAL STATUS -------")
	println(primal_status(FUCRmodel))
	println("------------------------------------")
	println("------- FUCR DUAL STATUS -------")
	println(JuMP.dual_status(FUCRmodel))
	println("Day: ", day, " solved")
	println("---------------------------")
	println("FUCRmodel Number of variables: ", JuMP.num_variables(FUCRmodel))
	@info "FUCRmodel Number of variables: " JuMP.num_variables(FUCRmodel)

	open(".//outputs//time_performance.csv", FILE_ACCESS_APPEND) do io
	      writedlm(io, hcat("FUCRmodel", JuMP.num_variables(FUCRmodel), "day: $day",
	              "", "", "Variables"), ',')
	end;

	@debug "FUCRmodel for day: $day optimized executed in (s):  $(solve_time(FUCRmodel))";

	open(".//outputs//time_performance.csv", FILE_ACCESS_APPEND) do io
	      writedlm(io, hcat("FUCRmodel", solve_time(FUCRmodel), "day: $day",
	              "", "", "Model Optimization"), ',')
	end; # closes file

	# Write the conventional generators' schedules in CSV file
	t1_write_FUCRmodel_results = time_ns()
	open(".//outputs//FUCR_GenOutputs.csv", FILE_ACCESS_APPEND) do io
	  for t in 1:HRS_FUCR, g=1:GENS
	      writedlm(io, hcat(day, t+INIT_HR_FUCR, g, df_gens.UNIT_NAME[g],
	          df_gens.MinPowerOut[g], df_gens.MaxPowerOut[g],
	          JuMP.value.(fucrm_genOut[g,t]), JuMP.value.(fucrm_genOnOff[g,t]),
	          JuMP.value.(fucrm_genShutDown[g,t]), JuMP.value.(fucrm_genStartUp[g,t]),
	          JuMP.value.(fucrm_genResUp[g,t]), JuMP.value.(fucrm_genResNonSpin[g,t]),
	          JuMP.value.(fucrm_genResDn[g,t]), JuMP.value.(fucrm_TotGenVioP[g,t]),
	          JuMP.value.(fucrm_TotGenVioN[g,t]), JuMP.value.(fucrm_MaxGenVioP[g,t]),
	          JuMP.value.(fucrm_MinGenVioP[g,t]) ), ',')
	  end # ends the loop
	end; # closes file
	# Write the peakers' schedules in CSV file
	open(".//outputs//FUCR_PeakerOutputs.csv", FILE_ACCESS_APPEND) do io
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
	open(".//outputs//FUCR_StorageOutputs.csv", FILE_ACCESS_APPEND) do io
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
	open(".//outputs//FUCR_TranFlowOutputs.csv", FILE_ACCESS_APPEND) do io
	  for t in 1:HRS_FUCR, n=1:N_ZONES, m=1:M_ZONES
	     writedlm(io, hcat(day, t+INIT_HR_FUCR, n,
	         JuMP.value.(fucrm_powerFlow[n,m,t]), TranC[n,m] ), ',')
	  end # ends the loop
	end; # closes file

	# Writing the curtilment, overgeneration, and spillage outcomes in CSV file
	open(".//outputs//FUCR_Curtail.csv", FILE_ACCESS_APPEND) do io
	  for t in 1:HRS_FUCR, n=1:N_ZONES
	     writedlm(io, hcat(day, t+INIT_HR_FUCR, n,
	         JuMP.value.(fucrm_OverGen[n,t]), JuMP.value.(fucrm_Demand_Curt[n,t]),
	         JuMP.value.(fucrm_windGSpil[n,t]), JuMP.value.(fucrm_solarGSpil[n,t]),
	         JuMP.value.(fucrm_hydroGSpil[n,t])), ',')
	  end # ends the loop
	end; # closes file

	t2_write_FUCRmodel_results = time_ns()

	time_write_FUCRmodel_results = (t2_write_FUCRmodel_results -t1_write_FUCRmodel_results)/1.0e9;
	@info "Write FUCRmodel results for day $day: $time_write_FUCRmodel_results executed in (s)";

	open(".//outputs//time_performance.csv", FILE_ACCESS_APPEND) do io
	      writedlm(io, hcat("FUCRmodel", time_write_FUCRmodel_results, "day: $day",
	              "", "", "Write CSV files"), ',')
	end; #closes file

	t1_FUCRtoBUCR1_data_hand = time_ns()

	for h=1:INIT_HR_SUCR-INIT_HR_FUCR
	  for g=1:GENS
		  uc_results.gens.onoff[g,h]= round(JuMP.value.(fucrm_genOnOff[g,h]));
		  uc_results.gens.power_out[g,h]= JuMP.value.(fucrm_genOut[g,h]);
		  uc_results.gens.startup[g,h]= round(JuMP.value.(fucrm_genStartUp[g,h]));
		  uc_results.gens.shutdown[g,h]= round(JuMP.value.(fucrm_genShutDown[g,h]));
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
		  uc_results.storg.chrg[p,h]=round(JuMP.value.(fucrm_storgChrg[p,h]));
		  uc_results.storg.disc[p,h]=round(JuMP.value.(fucrm_storgDisc[p,h]));
		  uc_results.storg.idle[p,h]=round(JuMP.value.(fucrm_storgIdle[p,h]));
		  uc_results.storg.chrgpwr[p,h]=JuMP.value.(fucrm_storgChrgPwr[p,h]);
		  uc_results.storg.discpwr[p,h]=JuMP.value.(fucrm_storgDiscPwr[p,h]);
		  uc_results.storg.soc[p,h]=JuMP.value.(fucrm_storgSOC[p,h]);
	  end
	end

	t2_FUCRtoBUCR1_data_hand = time_ns();

	time_FUCRtoBUCR1_data_hand = (t2_FUCRtoBUCR1_data_hand -t1_FUCRtoBUCR1_data_hand)/1.0e9;
	@info "FUCRtoBUCR1 data handling for day $day executed in (s): $time_FUCRtoBUCR1_data_hand";

	open(".//outputs//time_performance.csv", FILE_ACCESS_APPEND) do io
		  writedlm(io, hcat("FUCRmodel", time_FUCRtoBUCR1_data_hand, "day: $day",
				  " ", "Pre-processing variables", "Data Manipulation"), ',')
	end; #closes file

	return uc_results;

end # end function
