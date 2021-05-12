
function sucr_model(day::Int64, df_gens::DataFrame,
    df_peakers::DataFrame, df_storage::DataFrame, fuelprice::Matrix{Float64},
    fuelprice_peakers::Matrix{Float64},
	map_gens::Matrix{Int64}, map_storage::Matrix{Int64},
	sucr_results::UC_Results, sucr_prepoc::DemandWAPreprocGens,
	lb_MDT::Matrix{Int64}, lb_MUT::Matrix{Int64},
	lb_MDT_peaker::Matrix{Int64}, lb_MUT_peaker::Matrix{Int64})

	t1_SUCRmodel = time_ns()

	uc_gens = GensResults();
	uc_peakers = PeakersResults(
		genout_block = zeros(Float64, PEAKERS,BLOCKS,24-INIT_HR_SUCR+INIT_HR_FUCR));
	uc_storg = StorageResults();
	uc_results = UC_Results(uc_gens, uc_peakers, uc_storg);

	SUCRmodel = direct_model(CPLEX.Optimizer())
	set_optimizer_attribute(SUCRmodel, "CPX_PARAM_EPGAP", SOLVER_EPGAP)

	# Declaring the decision variables for conventional generators
	@variable(SUCRmodel, sucrm_genOnOff[1:GENS, 0:HRS_SUCR], Bin) #Bin
	@variable(SUCRmodel, sucrm_genStartUp[1:GENS, 1:HRS_SUCR], Bin) # startup variable
	@variable(SUCRmodel, sucrm_genShutDown[1:GENS, 1:HRS_SUCR], Bin) # shutdown variable
	@variable(SUCRmodel, sucrm_genOut[1:GENS, 0:HRS_SUCR]>=0) # Generator's output schedule
	@variable(SUCRmodel, sucrm_genOut_Block[1:GENS, 1:BLOCKS, 1:HRS_SUCR]>=0) # Generator's output schedule from each block (block rfers to IHR curve blocks/segments)
	@variable(SUCRmodel, sucrm_genResUp[1:GENS, 1:HRS_SUCR]>=0) # Generators' up reserve schedule
	@variable(SUCRmodel, sucrm_genResNonSpin[1:GENS, 1:HRS_SUCR]>=0) # Generators' up reserve schedule
	@variable(SUCRmodel, sucrm_genResDn[1:GENS, 1:HRS_SUCR]>=0) # Generator's down rserve schedule
	@variable(SUCRmodel, sucrm_TotGenVioP[g=1:GENS, 1:HRS_SUCR]>=0)
	@variable(SUCRmodel, sucrm_TotGenVioN[g=1:GENS, 1:HRS_SUCR]>=0)
	@variable(SUCRmodel, sucrm_MaxGenVioP[g=1:GENS, 1:HRS_SUCR]>=0)
	@variable(SUCRmodel, sucrm_MinGenVioP[g=1:GENS, 1:HRS_SUCR]>=0)

	# Declaring the decision variables for peakers
	@variable(SUCRmodel, 0<=sucrm_peakerOnOff[1:PEAKERS, 0:HRS_SUCR]<=1) #Bin, relaxed
	@variable(SUCRmodel, 0<=sucrm_peakerStartUp[1:PEAKERS, 1:HRS_SUCR]<=1) # startup variable
	@variable(SUCRmodel, 0<=sucrm_peakerShutDown[1:PEAKERS, 1:HRS_SUCR]<=1) # shutdown variable
	@variable(SUCRmodel, sucrm_peakerOut[1:PEAKERS, 0:HRS_SUCR]>=0) # Generator's output schedule
	@variable(SUCRmodel, sucrm_peakerOut_Block[1:PEAKERS, 1:BLOCKS, 1:HRS_SUCR]>=0) # Generator's output schedule from each block (block rfers to IHR curve blocks/segments)
	@variable(SUCRmodel, sucrm_peakerResUp[1:PEAKERS, 1:HRS_SUCR]>=0) # Generators' up reserve schedule
	@variable(SUCRmodel, sucrm_peakerResNonSpin[1:PEAKERS, 1:HRS_SUCR]>=0) # Generators' up reserve schedule
	@variable(SUCRmodel, sucrm_peakerResDn[1:PEAKERS, 1:HRS_SUCR]>=0) # Generator's down rserve schedule

	# Declaring decision variables for storage Units
	@variable(SUCRmodel, sucrm_storgChrg[1:STORG_UNITS, 1:HRS_SUCR], Bin) #Bin variable equal to 1 if unit runs in the charging mode
	@variable(SUCRmodel, sucrm_storgDisc[1:STORG_UNITS, 1:HRS_SUCR], Bin) #Bin variable equal to 1 if unit runs in the discharging mode
	@variable(SUCRmodel, sucrm_storgIdle[1:STORG_UNITS, 1:HRS_SUCR], Bin) ##Bin variable equal to 1 if unit runs in the idle mode
	@variable(SUCRmodel, sucrm_storgChrgPwr[1:STORG_UNITS, 0:HRS_SUCR] >= 0) #Chargung power
	@variable(SUCRmodel, sucrm_storgDiscPwr[1:STORG_UNITS, 0:HRS_SUCR] >= 0) # Discharging Power
	@variable(SUCRmodel, sucrm_storgSOC[1:STORG_UNITS, 0:HRS_SUCR] >= 0) # state of charge (stored energy level for storage unit at time t)
	@variable(SUCRmodel, sucrm_storgResUp[1:STORG_UNITS, 0:HRS_SUCR] >= 0) # Scheduled up reserve
	@variable(SUCRmodel, sucrm_storgResDn[1:STORG_UNITS, 0:HRS_SUCR] >= 0) # Scheduled down reserve

	# declaring decision variables for renewable generation
	@variable(SUCRmodel, sucrm_solarG[1:N_ZONES, 1:HRS_SUCR] >= 0) # solar energy schedules
	@variable(SUCRmodel, sucrm_windG[1:N_ZONES, 1:HRS_SUCR] >= 0) # wind energy schedules
	@variable(SUCRmodel, sucrm_hydroG[1:N_ZONES, 1:HRS_SUCR] >= 0) # hydro energy schedules
	@variable(SUCRmodel, sucrm_solarGSpil[1:N_ZONES, 1:HRS_SUCR] >= 0) # solar energy schedules
	@variable(SUCRmodel, sucrm_windGSpil[1:N_ZONES, 1:HRS_SUCR] >= 0) # wind energy schedules
	@variable(SUCRmodel, sucrm_hydroGSpil[1:N_ZONES, 1:HRS_SUCR] >= 0) # hydro energy schedules

	# Declaring decision variables for hourly dispatched and curtailed demand
	@variable(SUCRmodel, sucrm_Demand[1:N_ZONES, 1:HRS_SUCR]>=0) # Hourly scheduled demand
	@variable(SUCRmodel, sucrm_Demand_Curt[1:N_ZONES, 1:HRS_SUCR]>=0) # Hourly schedule demand

	@variable(SUCRmodel, sucrm_OverGen[1:N_ZONES, 1:HRS_SUCR]>=0) # Hourly schedule demand

	# Declaring variables for transmission system
	@variable(SUCRmodel, sucrm_voltAngle[1:N_ZONES, 1:HRS_SUCR]) #voltage angle at zone/bus n in t//
	@variable(SUCRmodel, sucrm_powerFlow[1:N_ZONES, 1:M_ZONES, 1:HRS_SUCR]) #transmission Flow from zone n to zone m//

	# Defining the objective function that minimizes the overal cost of supplying electricity (=total variable, no-load, startup, and shutdown costs)
	@objective(SUCRmodel, Min, sum(sum(df_gens.IHRC_B1_HR[g]*fuelprice[g,day]*sucrm_genOut_Block[g,1,t]
			+df_gens.IHRC_B2_HR[g]*fuelprice[g,day]*sucrm_genOut_Block[g,2,t]
			+df_gens.IHRC_B3_HR[g]*fuelprice[g,day]*sucrm_genOut_Block[g,3,t]
			+df_gens.IHRC_B4_HR[g]*fuelprice[g,day]*sucrm_genOut_Block[g,4,t]
			+df_gens.IHRC_B5_HR[g]*fuelprice[g,day]*sucrm_genOut_Block[g,5,t]
			+df_gens.IHRC_B6_HR[g]*fuelprice[g,day]*sucrm_genOut_Block[g,6,t]
			+df_gens.IHRC_B7_HR[g]*fuelprice[g,day]*sucrm_genOut_Block[g,7,t]
			+df_gens.NoLoadHR[g]*fuelprice[g,day]*sucrm_genOnOff[g,t] +
			((df_gens.HotStartU_FixedCost[g]+(df_gens.HotStartU_HeatRate[g]*fuelprice[g,day]))*sucrm_genStartUp[g,t])
			+df_gens.ShutdownCost[g]*sucrm_genShutDown[g, t]
			+(sucrm_TotGenVioP[g,t]*VIOLATION_PENALTY)+(sucrm_TotGenVioN[g,t]*VIOLATION_PENALTY)+
			(sucrm_MaxGenVioP[g,t]*VIOLATION_PENALTY)+(sucrm_MinGenVioP[g,t]*VIOLATION_PENALTY) for g in 1:GENS)
			+sum(df_peakers.IHRC_B1_HR[k]*fuelprice_peakers[k,day]*sucrm_peakerOut_Block[k,1,t]
			+df_peakers.IHRC_B2_HR[k]*fuelprice_peakers[k,day]*sucrm_peakerOut_Block[k,2,t]
			+df_peakers.IHRC_B3_HR[k]*fuelprice_peakers[k,day]*sucrm_peakerOut_Block[k,3,t]
			+df_peakers.IHRC_B4_HR[k]*fuelprice_peakers[k,day]*sucrm_peakerOut_Block[k,4,t]
			+df_peakers.IHRC_B5_HR[k]*fuelprice_peakers[k,day]*sucrm_peakerOut_Block[k,5,t]
			+df_peakers.IHRC_B6_HR[k]*fuelprice_peakers[k,day]*sucrm_peakerOut_Block[k,6,t]
			+df_peakers.IHRC_B7_HR[k]*fuelprice_peakers[k,day]*sucrm_peakerOut_Block[k,7,t]
			+df_peakers.NoLoadHR[k]*fuelprice_peakers[k,day]*sucrm_peakerOnOff[k,t] +
			((df_peakers.HotStartU_FixedCost[k]+(df_peakers.HotStartU_HeatRate[k]*fuelprice_peakers[k,day]))*sucrm_peakerStartUp[k,t])
			+df_peakers.ShutdownCost[k]*sucrm_peakerShutDown[k, t] for k in 1:PEAKERS) for t in 1:HRS_SUCR)
		   +sum(sum((sucrm_Demand_Curt[n,t]*LOAD_SHED_PENALTY)+(sucrm_OverGen[n,t]*OVERGEN_PENALTY) for n=1:N_ZONES) for t=1:HRS_SUCR))

	#Initialization of commitment and dispatch variables for slow-start generators at t=0 (representing the last hour of previous scheduling horizon day=day-1 and t=24)
	@constraint(SUCRmodel, conInitGenOnOff[g=1:GENS], sucrm_genOnOff[g,0]==sucr_results.gens.onoff_init[g]) # initial generation level for generator g at t=0
	@constraint(SUCRmodel, conInitGenOut[g=1:GENS], sucrm_genOut[g,0]==sucr_results.gens.power_out_init[g]) # initial on/off status for generators g at t=0

	#Initialization of commitment and dispatch variables for peakers at t=0 (representing the last hour of previous scheduling horizon day=day-1 and t=24)
	@constraint(SUCRmodel, conInitGenOnOff_Peaker[k=1:PEAKERS], sucrm_peakerOnOff[k,0]==sucr_results.peakers.onoff_init[k]) # initial generation level for peaker k at t=0
	@constraint(SUCRmodel, conInitGenOut_Peaker[k=1:PEAKERS], sucrm_peakerOut[k,0]==sucr_results.peakers.power_out_init[k]) # initial on/off status for peaker k at t=0
	#Initialization of commitment and dispatch variables for storage units at t=0 (representing the last hour of previous scheduling horizon day=day-1 and t=24)
	@constraint(SUCRmodel, conInitSOC[p=1:STORG_UNITS], sucrm_storgSOC[p,0]==sucr_results.storg.soc_init[p]) # SOC for storage unit p at t=0

	# Baseload Operation of nuclear units
	@constraint(SUCRmodel, conNuckBaseLoad[t=1:HRS_SUCR, g=1:GENS], sucrm_genOnOff[g,t]>=df_gens.Nuclear[g]) #
	@constraint(SUCRmodel, conNuclearTotGenZone[t=1:HRS_SUCR, n=1:N_ZONES], sum((sucrm_genOut[g,t]*map_gens[g,n]*df_gens.Nuclear[g]) for g=1:GENS) -sucr_prepoc.nuclear_wa[t,n] ==0)

	#Limits on generation of cogen units
	@constraint(SUCRmodel, conCoGenBaseLoad[t=1:HRS_SUCR, g=1:GENS], sucrm_genOnOff[g,t]>=df_gens.Cogen[g]) #
	@constraint(SUCRmodel, conCoGenTotGenZone[t=1:HRS_SUCR, n=1:N_ZONES], sum((sucrm_genOut[g,t]*map_gens[g,n]*df_gens.Cogen[g]) for g=1:GENS) -sucr_prepoc.cogen_wa[t,n] ==0)

	# Constraints representing technical limits of conventional generators
	#Status transition trajectory of
	@constraint(SUCRmodel, conStartUpAndDn[t=1:HRS_SUCR, g=1:GENS], (sucrm_genOnOff[g,t] - sucrm_genOnOff[g,t-1] - sucrm_genStartUp[g,t] + sucrm_genShutDown[g,t])==0)
	# Max Power generation limit in Block 1
	@constraint(SUCRmodel, conMaxPowBlock1[t=1:HRS_SUCR, g=1:GENS],  sucrm_genOut_Block[g,1,t] <= df_gens.IHRC_B1_Q[g]*sucrm_genOnOff[g,t] )
	# Max Power generation limit in Block 2
	@constraint(SUCRmodel, conMaxPowBlock2[t=1:HRS_SUCR, g=1:GENS],  sucrm_genOut_Block[g,2,t] <= df_gens.IHRC_B2_Q[g]*sucrm_genOnOff[g,t] )
	# Max Power generation limit in Block 3
	@constraint(SUCRmodel, conMaxPowBlock3[t=1:HRS_SUCR, g=1:GENS],  sucrm_genOut_Block[g,3,t] <= df_gens.IHRC_B3_Q[g]*sucrm_genOnOff[g,t] )
	# Max Power generation limit in Block 4
	@constraint(SUCRmodel, conMaxPowBlock4[t=1:HRS_SUCR, g=1:GENS],  sucrm_genOut_Block[g,4,t] <= df_gens.IHRC_B4_Q[g]*sucrm_genOnOff[g,t] )
	# Max Power generation limit in Block 5
	@constraint(SUCRmodel, conMaxPowBlock5[t=1:HRS_SUCR, g=1:GENS],  sucrm_genOut_Block[g,5,t] <= df_gens.IHRC_B5_Q[g]*sucrm_genOnOff[g,t] )
	# Max Power generation limit in Block 6
	@constraint(SUCRmodel, conMaxPowBlock6[t=1:HRS_SUCR, g=1:GENS],  sucrm_genOut_Block[g,6,t] <= df_gens.IHRC_B6_Q[g]*sucrm_genOnOff[g,t] )
	# Max Power generation limit in Block 7
	@constraint(SUCRmodel, conMaxPowBlock7[t=1:HRS_SUCR, g=1:GENS],  sucrm_genOut_Block[g,7,t] <= df_gens.IHRC_B7_Q[g]*sucrm_genOnOff[g,t] )
	# Total Production of each generation equals the sum of generation from its all blocks
	@constraint(SUCRmodel, conTotalGen[t=1:HRS_SUCR, g=1:GENS],  sum(sucrm_genOut_Block[g,b,t] for b=1:BLOCKS) + sucrm_TotGenVioP[g,t] - sucrm_TotGenVioN[g,t] >=sucrm_genOut[g,t])

	#Max power generation limit
	@constraint(SUCRmodel, conMaxPow[t=1:HRS_SUCR, g=1:GENS],  sucrm_genOut[g,t]+sucrm_genResUp[g,t] - sucrm_MaxGenVioP[g,t]  <= df_gens.MaxPowerOut[g]*sucrm_genOnOff[g,t] )
	# Min power generation limit
	@constraint(SUCRmodel, conMinPow[t=1:HRS_SUCR, g=1:GENS],  sucrm_genOut[g,t]-sucrm_genResDn[g,t] + sucrm_MinGenVioP[g,t] >= df_gens.MinPowerOut[g]*sucrm_genOnOff[g,t] )
	# Up reserve provision limit
	@constraint(SUCRmodel, conMaxResUp[t=1:HRS_SUCR, g=1:GENS], sucrm_genResUp[g,t] <= df_gens.SpinningRes_Limit[g]*sucrm_genOnOff[g,t] )
	# Non-Spinning Reserve Limit
	#@constraint(SUCRmodel, conMaxNonSpinResUp[t=1:HRS_SUCR, g=1:GENS], sucrm_genResNonSpin[g,t] <= (df_gens.NonSpinningRes_Limit[g]*(1-sucrm_genOnOff[g,t])) )
	@constraint(SUCRmodel, conMaxNonSpinResUp[t=1:HRS_SUCR, g=1:GENS], sucrm_genResNonSpin[g,t] <= 0 )
	#Down reserve provision limit
	@constraint(SUCRmodel, conMaxResDown[t=1:HRS_SUCR, g=1:GENS],  sucrm_genResDn[g,t] <= df_gens.SpinningRes_Limit[g]*sucrm_genOnOff[g,t] )
	#Up ramp rate limit
	@constraint(SUCRmodel, conRampRateUp[t=1:HRS_SUCR, g=1:GENS], (sucrm_genOut[g,t] - sucrm_genOut[g,t-1] <=(df_gens.RampUpLimit[g]*sucrm_genOnOff[g, t-1]) + (df_gens.RampStartUpLimit[g]*sucrm_genStartUp[g,t])))
	# Down ramp rate limit
	@constraint(SUCRmodel, conRampRateDown[t=1:HRS_SUCR, g=1:GENS], (sucrm_genOut[g,t-1] - sucrm_genOut[g,t] <=(df_gens.RampDownLimit[g]*sucrm_genOnOff[g,t]) + (df_gens.RampShutDownLimit[g]*sucrm_genShutDown[g,t])))
	# Min Up Time limit with alternative formulation
	@constraint(SUCRmodel, conUpTime[t=1:HRS_SUCR, g=1:GENS], (sum(sucrm_genStartUp[g,k] for k=lb_MUT[g,t]:t)<=sucrm_genOnOff[g,t]))
	# Min down Time limit with alternative formulation
	@constraint(SUCRmodel, conDownTime[t=1:HRS_SUCR, g=1:GENS], (1-sum(sucrm_genShutDown[g,i] for i=lb_MDT[g,t]:t)>=sucrm_genOnOff[g,t]))

	# Constraints representing technical limits of Peakers
	#Status transition trajectory of peakers
	@constraint(SUCRmodel, conStartUpAndDn_Peaker[t=1:HRS_SUCR, k=1:PEAKERS], (sucrm_peakerOnOff[k,t] - sucrm_peakerOnOff[k,t-1] - sucrm_peakerStartUp[k,t] + sucrm_peakerShutDown[k,t])==0)
	# Max Power generation limit in Block 1
	@constraint(SUCRmodel, conMaxPowBlock1_Peaker[t=1:HRS_SUCR, k=1:PEAKERS],  sucrm_peakerOut_Block[k,1,t] <= df_peakers.IHRC_B1_Q[k]*sucrm_peakerOnOff[k,t] )
	# Max Power generation limit in Block 2
	@constraint(SUCRmodel, conMaxPowBlock2_Peaker[t=1:HRS_SUCR, k=1:PEAKERS],  sucrm_peakerOut_Block[k,2,t] <= df_peakers.IHRC_B2_Q[k]*sucrm_peakerOnOff[k,t] )
	# Max Power generation limit in Block 3
	@constraint(SUCRmodel, conMaxPowBlock3_Peaker[t=1:HRS_SUCR, k=1:PEAKERS],  sucrm_peakerOut_Block[k,3,t] <= df_peakers.IHRC_B3_Q[k]*sucrm_peakerOnOff[k,t] )
	# Max Power generation limit in Block 4
	@constraint(SUCRmodel, conMaxPowBlock4_Peaker[t=1:HRS_SUCR, k=1:PEAKERS],  sucrm_peakerOut_Block[k,4,t] <= df_peakers.IHRC_B4_Q[k]*sucrm_peakerOnOff[k,t] )
	# Max Power generation limit in Block 5
	@constraint(SUCRmodel, conMaxPowBlock5_Peaker[t=1:HRS_SUCR, k=1:PEAKERS],  sucrm_peakerOut_Block[k,5,t] <= df_peakers.IHRC_B5_Q[k]*sucrm_peakerOnOff[k,t] )
	# Max Power generation limit in Block 6
	@constraint(SUCRmodel, conMaxPowBlock6_Peaker[t=1:HRS_SUCR, k=1:PEAKERS],  sucrm_peakerOut_Block[k,6,t] <= df_peakers.IHRC_B6_Q[k]*sucrm_peakerOnOff[k,t] )
	# Max Power generation limit in Block 7
	@constraint(SUCRmodel, conMaxPowBlock7_Peaker[t=1:HRS_SUCR, k=1:PEAKERS],  sucrm_peakerOut_Block[k,7,t] <= df_peakers.IHRC_B7_Q[k]*sucrm_peakerOnOff[k,t] )
	# Total Production of each generation equals the sum of generation from its all blocks
	@constraint(SUCRmodel, conTotalGen_Peaker[t=1:HRS_SUCR, k=1:PEAKERS],  sum(sucrm_peakerOut_Block[k,b,t] for b=1:BLOCKS)>=sucrm_peakerOut[k,t])
	#Max power generation limit
	@constraint(SUCRmodel, conMaxPow_Peaker[t=1:HRS_SUCR, k=1:PEAKERS],  sucrm_peakerOut[k,t]+sucrm_peakerResUp[k,t] <= df_peakers.MaxPowerOut[k]*sucrm_peakerOnOff[k,t] )
	# Min power generation limit
	@constraint(SUCRmodel, conMinPow_Peaker[t=1:HRS_SUCR, k=1:PEAKERS],  sucrm_peakerOut[k,t]-sucrm_peakerResDn[k,t] >= df_peakers.MinPowerOut[k]*sucrm_peakerOnOff[k,t] )
	# Up reserve provision limit
	@constraint(SUCRmodel, conMaxResUp_Peaker[t=1:HRS_SUCR, k=1:PEAKERS], sucrm_peakerResUp[k,t] <= df_peakers.SpinningRes_Limit[k]*sucrm_peakerOnOff[k,t] )
	# Non-Spinning Reserve Limit
	@constraint(SUCRmodel, conMaxNonSpinResUp_Peaker[t=1:HRS_SUCR, k=1:PEAKERS], sucrm_peakerResNonSpin[k,t] <= (df_peakers.NonSpinningRes_Limit[k]*(1-sucrm_peakerOnOff[k,t])))
	#Down reserve provision limit
	@constraint(SUCRmodel, conMaxResDown_Peaker[t=1:HRS_SUCR, k=1:PEAKERS],  sucrm_peakerResDn[k,t] <= df_peakers.SpinningRes_Limit[k]*sucrm_peakerOnOff[k,t] )
	#Up ramp rate limit
	@constraint(SUCRmodel, conRampRateUp_Peaker[t=1:HRS_SUCR, k=1:PEAKERS], (sucrm_peakerOut[k,t] - sucrm_peakerOut[k,t-1] <=(df_peakers.RampUpLimit[k]*sucrm_peakerOnOff[k, t-1]) + (df_peakers.RampStartUpLimit[k]*sucrm_peakerStartUp[k,t])))
	# Down ramp rate limit
	@constraint(SUCRmodel, conRampRateDown_Peaker[t=1:HRS_SUCR, k=1:PEAKERS], (sucrm_peakerOut[k,t-1] - sucrm_peakerOut[k,t] <=(df_peakers.RampDownLimit[k]*sucrm_peakerOnOff[k,t]) + (df_peakers.RampShutDownLimit[k]*sucrm_peakerShutDown[k,t])))
	# Min Up Time limit with alternative formulation
	@constraint(SUCRmodel, conUpTime_Peaker[t=1:HRS_SUCR, k=1:PEAKERS], (sum(sucrm_peakerStartUp[k,r] for r=lb_MUT_peaker[k,t]:t)<=sucrm_peakerOnOff[k,t]))
	# Min down Time limit with alternative formulation
	@constraint(SUCRmodel, conDownTime_Peaker[t=1:HRS_SUCR, k=1:PEAKERS], (1-sum(sucrm_peakerShutDown[k,s] for s=lb_MDT_peaker[k,t]:t)>=sucrm_peakerOnOff[k,t]))

	# Renewable generation constraints
	@constraint(SUCRmodel, conSolarLimit[t=1:HRS_SUCR, n=1:N_ZONES], sucrm_solarG[n, t] + sucrm_solarGSpil[n,t]<=sucr_prepoc.solar_wa[t,n])
	@constraint(SUCRmodel, conWindLimit[t=1:HRS_SUCR, n=1:N_ZONES], sucrm_windG[n, t] + sucrm_windGSpil[n,t]<=sucr_prepoc.wind_wa[t,n])
	@constraint(SUCRmodel, conHydroLimit[t=1:HRS_SUCR, n=1:N_ZONES], sucrm_hydroG[n, t] + sucrm_hydroGSpil[n,t]<=sucr_prepoc.hydro_wa[t,n])

	# Constraints representing technical characteristics of storage units
	# status transition of storage units between charging, discharging, and idle modes
	@constraint(SUCRmodel, conStorgStatusTransition[t=1:HRS_SUCR, p=1:STORG_UNITS], (sucrm_storgChrg[p,t]+sucrm_storgDisc[p,t]+sucrm_storgIdle[p,t])==1)
	# charging power limit
	@constraint(SUCRmodel, conStrgChargPowerLimit[t=1:HRS_SUCR, p=1:STORG_UNITS], (sucrm_storgChrgPwr[p,t] - sucrm_storgResDn[p,t])<=df_storage.Power[p]*sucrm_storgChrg[p,t])
	# Discharging power limit
	@constraint(SUCRmodel, conStrgDisChgPowerLimit[t=1:HRS_SUCR, p=1:STORG_UNITS], (sucrm_storgDiscPwr[p,t] + sucrm_storgResUp[p,t])<=df_storage.Power[p]*sucrm_storgDisc[p,t])
	# Down reserve provision limit
	@constraint(SUCRmodel, conStrgDownResrvMax[t=1:HRS_SUCR, p=1:STORG_UNITS], sucrm_storgResDn[p,t]<=df_storage.Power[p]*sucrm_storgChrg[p,t])
	# Up reserve provision limit`
	@constraint(SUCRmodel, conStrgUpResrvMax[t=1:HRS_SUCR, p=1:STORG_UNITS], sucrm_storgResUp[p,t]<=df_storage.Power[p]*sucrm_storgDisc[p,t])
	# State of charge at t
	@constraint(SUCRmodel, conStorgSOC[t=1:HRS_SUCR, p=1:STORG_UNITS], sucrm_storgSOC[p,t]==sucrm_storgSOC[p,t-1]-(sucrm_storgDiscPwr[p,t]/df_storage.TripEfficDown[p])+(sucrm_storgChrgPwr[p,t]*df_storage.TripEfficUp[p])-(sucrm_storgSOC[p,t]*df_storage.SelfDischarge[p]))
	# minimum energy limit
	@constraint(SUCRmodel, conMinEnrgStorgLimi[t=1:HRS_SUCR, p=1:STORG_UNITS], sucrm_storgSOC[p,t]-(sucrm_storgResUp[p,t]/df_storage.TripEfficDown[p])+(sucrm_storgResDn[p,t]/df_storage.TripEfficUp[p])>=0)
	# Maximum energy limit
	@constraint(SUCRmodel, conMaxEnrgStorgLimi[t=1:HRS_SUCR, p=1:STORG_UNITS], sucrm_storgSOC[p,t]-(sucrm_storgResUp[p,t]/df_storage.TripEfficDown[p])+(sucrm_storgResDn[p,t]/df_storage.TripEfficUp[p])<=(df_storage.Power[p]/df_storage.PowerToEnergRatio[p]))
	# Constraints representing transmission grid capacity constraints
	# DC Power Flow Calculation
	#@constraint(SUCRmodel, conDCPowerFlowPos[t=1:HRS_SUCR, n=1:N_ZONES, m=1:N_ZONES], sucrm_powerFlow[n,m,t]-(TranS[n,m]*(sucrm_voltAngle[n,t]-sucrm_voltAngle[m,t])) ==0)
	@constraint(SUCRmodel, conDCPowerFlowNeg[t=1:HRS_SUCR, n=1:N_ZONES, m=1:N_ZONES], sucrm_powerFlow[n,m,t]+sucrm_powerFlow[m,n,t]==0)
	# Tranmission flow bounds (from n to m and from m to n)
	@constraint(SUCRmodel, conPosFlowLimit[t=1:HRS_SUCR, n=1:N_ZONES, m=1:N_ZONES], sucrm_powerFlow[n,m,t]<=TranC[n,m])
	@constraint(SUCRmodel, conNegFlowLimit[t=1:HRS_SUCR, n=1:N_ZONES, m=1:N_ZONES], sucrm_powerFlow[n,m,t]>=-TranC[n,m])
	# Voltage Angle bounds and reference point
	#@constraint(SUCRmodel, conVoltAnglUB[t=1:HRS_SUCR, n=1:N_ZONES], sucrm_voltAngle[n,t]<=π)
	#@constraint(SUCRmodel, conVoltAnglLB[t=1:HRS_SUCR, n=1:N_ZONES], sucrm_voltAngle[n,t]>=-π)
	#@constraint(SUCRmodel, conVoltAngRef[t=1:HRS_SUCR], sucrm_voltAngle[1,t]==0)

	# Demand-side Constraints
	@constraint(SUCRmodel, conDemandLimit[t=1:HRS_SUCR, n=1:N_ZONES], sucrm_Demand[n,t]+ sucrm_Demand_Curt[n,t] == sucr_prepoc.wk_ahead[t,n])

	# Demand Curtailment and wind generation limits
	@constraint(SUCRmodel, conDemandCurtLimit[t=1:HRS_SUCR, n=1:N_ZONES], sucrm_Demand_Curt[n,t] <= LOAD_SHED_MAX);
	@constraint(SUCRmodel, conOverGenLimit[t=1:HRS_SUCR, n=1:N_ZONES], sucrm_OverGen[n,t] <= OVERGEN_MAX);

	# System-wide Constraints
	#nodal balance constraint
	@constraint(SUCRmodel, conNodBalanc[t=1:HRS_SUCR, n=1:N_ZONES], sum((sucrm_genOut[g,t]*map_gens[g,n]) for g=1:GENS) + sum((sucrm_storgDiscPwr[p,t]*map_storage[p,n]) for p=1:STORG_UNITS) - sum((sucrm_storgChrgPwr[p,t]*map_storage[p,n]) for p=1:STORG_UNITS) +sucrm_solarG[n, t] +sucrm_windG[n, t] +sucrm_hydroG[n, t] - sucrm_OverGen[n,t] - sucrm_Demand[n,t] == sum(sucrm_powerFlow[n,m,t] for m=1:M_ZONES))

	# Minimum zonal up reserve requirement, if there are more than two zones, we should  define reserve regions for DEC and DEP
	#@constraint(SUCRmodel, conMinUpReserveReq[t=1:HRS_SUCR, n=1:N_ZONES], sum((sucrm_genResUp[g,t]*map_gens[g,n]) for g=1:GENS) + sum((sucrm_storgResUp[p,t]*map_storage[p,n]) for p=1:STORG_UNITS) >= Reserve_Req_Up[n] )
	@constraint(SUCRmodel, conMinUpReserveReq[t=1:HRS_SUCR], sum((sucrm_genResUp[g,t]+sucrm_genResNonSpin[g,t]) for g=1:GENS) + sum((sucrm_storgResUp[p,t]) for p=1:STORG_UNITS) >= sum(Reserve_Req_Up[n] for n=1:N_ZONES))

	# Minimum down reserve requirement
	#    @constraint(SUCRmodel, conMinDnReserveReq[t=1:HRS_SUCR], sum(genResDn[g,t] for g=1:GENS) + sum(storgResDn[p,t] for p=1:STORG_UNITS) >= Reserve_Req_Dn[t] )

	t2_SUCRmodel = time_ns()
	time_SUCRmodel = (t2_SUCRmodel -t1_SUCRmodel)/1.0e9;
	@info "SUCRmodel for day: $day setup executed in (s): $time_SUCRmodel";

	open(".//outputs//csv//time_performance.csv", FILE_ACCESS_APPEND) do io
			writedlm(io, hcat("SUCRmodel", time_SUCRmodel, "day: $day",
					"", "", "Model Setup"), ',')
	end; # close file

	# solve the Second WA-UC model (SUCR)
	JuMP.optimize!(SUCRmodel)

	open(".//outputs//csv//objective_values_v76.csv", FILE_ACCESS_APPEND) do io
			writedlm(io, hcat("SUCRmodel", "day: $day",
					"", "", JuMP.objective_value(SUCRmodel)), ',')
	end;

	# Pricing general results in the terminal window
	println("Objective value: ", JuMP.objective_value(SUCRmodel))
	println("------------------------------------")
	println("------- SURC OBJECTIVE VALUE -------")
	println("Objective value for day ", day, " is ", JuMP.objective_value(SUCRmodel))
	println("------------------------------------")
	println("------- SURC PRIMAL STATUS -------")
	println(primal_status(SUCRmodel))
	println("------------------------------------")
	println("------- SURC DUAL STATUS -------")
	println(JuMP.dual_status(SUCRmodel))
	println("Day: ", day, " solved")
	println("---------------------------")
	println("SUCRmodel Number of variables: ", JuMP.num_variables(SUCRmodel))
	@info "SUCRmodel Number of variables: " JuMP.num_variables(SUCRmodel)

	open(".//outputs//csv//time_performance.csv", FILE_ACCESS_APPEND) do io
			writedlm(io, hcat("SUCRmodel", JuMP.num_variables(SUCRmodel), "day: $day",
					"", "", "Variables"), ',')
	end;

	@debug "SUCRmodel for day: $day optimized executed in (s):  $(solve_time(SUCRmodel))";

	open(".//outputs//csv//time_performance.csv", FILE_ACCESS_APPEND) do io
			writedlm(io, hcat("SUCRmodel", solve_time(SUCRmodel), "day: $day",
					"", "", "Model Optimization"), ',')
	end; # close file

	## Write the optimal outcomes into spreadsheets
	#TODO: Later we need to include a variable for day so the cell
	# number in which the results are printed is updated accordingly

	# Write the conventional generators' schedules
	t1_write_SUCRmodel_results = time_ns()
	open(".//outputs//csv//SUCR_GenOutputs.csv", FILE_ACCESS_APPEND) do io
		for t in 1:HRS_SUCR, g=1:GENS
			writedlm(io, hcat(day, t+INIT_HR_SUCR, g, df_gens.UNIT_ID[g],
				df_gens.MinPowerOut[g], df_gens.MaxPowerOut[g],
				JuMP.value.(sucrm_genOut[g,t]), JuMP.value.(sucrm_genOnOff[g,t]),
				JuMP.value.(sucrm_genShutDown[g,t]), JuMP.value.(sucrm_genStartUp[g,t]),
				JuMP.value.(sucrm_genResUp[g,t]), JuMP.value.(sucrm_genResNonSpin[g,t]),
				JuMP.value.(sucrm_genResDn[g,t]), JuMP.value.(sucrm_TotGenVioP[g,t]),
				JuMP.value.(sucrm_TotGenVioN[g,t]), JuMP.value.(sucrm_MaxGenVioP[g,t]),
				JuMP.value.(sucrm_MinGenVioP[g,t])), ',')
		end # ends the loop
	end; # close file

	open(".//outputs//csv//SUCR_PeakerOutputs.csv", FILE_ACCESS_APPEND) do io
		for t in 1:HRS_SUCR, k=1:PEAKERS
			writedlm(io, hcat(day, t+INIT_HR_SUCR, k, df_peakers.UNIT_ID[k],
				df_peakers.MinPowerOut[k], df_peakers.MaxPowerOut[k],
				JuMP.value.(sucrm_peakerOut[k,t]), JuMP.value.(sucrm_peakerOnOff[k,t]),
				JuMP.value.(sucrm_peakerShutDown[k,t]), JuMP.value.(sucrm_peakerStartUp[k,t]),
				JuMP.value.(sucrm_peakerResUp[k,t]), JuMP.value.(sucrm_peakerResNonSpin[k,t]),
				JuMP.value.(sucrm_peakerResDn[k,t])), ',')
		end # ends the loop
	end; # close file

	# Writing storage units' optimal schedules in CSV file
	open(".//outputs//csv//SUCR_StorageOutputs.csv", FILE_ACCESS_APPEND) do io
		for t in 1:HRS_SUCR, p=1:STORG_UNITS
			writedlm(io, hcat(day, t+INIT_HR_SUCR, p, df_storage.Power[p],
				df_storage.Power[p]/df_storage.PowerToEnergRatio[p],
				JuMP.value.(sucrm_storgChrg[p,t]), JuMP.value.(sucrm_storgDisc[p,t]),
				JuMP.value.(sucrm_storgIdle[p,t]), JuMP.value.(sucrm_storgChrgPwr[p,t]),
				JuMP.value.(sucrm_storgDiscPwr[p,t]), JuMP.value.(sucrm_storgSOC[p,t]),
				JuMP.value.(sucrm_storgResUp[p,t]), JuMP.value.(sucrm_storgResDn[p,t]) ), ',')
		end # ends the loop
	end; # close file

	# Writing the transmission flow schedules into spreadsheets
	open(".//outputs//csv//SUCR_TranFlowOutputs.csv", FILE_ACCESS_APPEND) do io
		for t in 1:HRS_SUCR, n=1:N_ZONES, m=1:M_ZONES
			writedlm(io, hcat(day, t+INIT_HR_SUCR, n, m,
				JuMP.value.(sucrm_powerFlow[n,m,t]), TranC[n,m] ), ',')
		end # ends the loop
	end; # close file

	# Writing the curtilment, overgeneration, and spillage outcomes in CSV file
	open(".//outputs//csv//SUCR_Curtail.csv", FILE_ACCESS_APPEND) do io
		for t in 1:HRS_SUCR, n=1:N_ZONES
		   writedlm(io, hcat(day, t+INIT_HR_SUCR, n,
			   JuMP.value.(sucrm_OverGen[n,t]), JuMP.value.(sucrm_Demand_Curt[n,t]),
			   JuMP.value.(sucrm_windGSpil[n,t]), JuMP.value.(sucrm_solarGSpil[n,t]),
			   JuMP.value.(sucrm_hydroGSpil[n,t])), ',')
		end # ends the loop
	end; # close file

	t2_write_SUCRmodel_results = time_ns()
	time_write_SUCRmodel_results = (t2_write_SUCRmodel_results -t1_write_SUCRmodel_results)/1.0e9;
	@info "Write SUCRmodel results for day $day: $time_write_SUCRmodel_results executed in (s)";

	open(".//outputs//csv//time_performance.csv", FILE_ACCESS_APPEND) do io
			writedlm(io, hcat("SUCRmodel", time_write_SUCRmodel_results, "day: $day",
					"", "", "Write CSV files"), ',')
	end; #close file

	# Create and save the following parameters, which are transefered to BAUC2
	for h=1:24-INIT_HR_SUCR+INIT_HR_FUCR
		for g=1:GENS
			uc_results.gens.onoff[g,h]= round(JuMP.value.(sucrm_genOnOff[g,h]));
			uc_results.gens.power_out[g,h]= JuMP.value.(sucrm_genOut[g,h]);
			uc_results.gens.startup[g,h]= round(JuMP.value.(sucrm_genStartUp[g,h]));
			uc_results.gens.shutdown[g,h]=round(JuMP.value.(sucrm_genShutDown[g,h]));
			for b=1:BLOCKS
				uc_results.gens.genout_block[g,b,h]=JuMP.value.(sucrm_genOut_Block[g,b,h]);
			end
		end
		for k=1:PEAKERS
			uc_results.peakers.onoff[k,h]= round(JuMP.value.(sucrm_peakerOnOff[k,h]));
			uc_results.peakers.power_out[k,h]=JuMP.value.(sucrm_peakerOut[k,h]);
			uc_results.peakers.startup[k,h]= round(JuMP.value.(sucrm_peakerStartUp[k,h]));
			uc_results.peakers.shutdown[k,h]= round(JuMP.value.(sucrm_peakerShutDown[k,h]));
			for b=1:BLOCKS
				uc_results.peakers.genout_block[k,b,h]=JuMP.value.(sucrm_peakerOut_Block[k,b,h]);
			end
		end
		for p=1:STORG_UNITS
			uc_results.storg.chrg[p,h]=round(JuMP.value.(sucrm_storgChrg[p,h]));
			uc_results.storg.disc[p,h]=round(JuMP.value.(sucrm_storgDisc[p,h]));
			uc_results.storg.idle[p,h]=round(JuMP.value.(sucrm_storgIdle[p,h]));
			uc_results.storg.chrgpwr[p,h]=JuMP.value.(sucrm_storgChrgPwr[p,h]);
			uc_results.storg.discpwr[p,h]=JuMP.value.(sucrm_storgDiscPwr[p,h]);
			uc_results.storg.soc[p,h]=JuMP.value.(sucrm_storgSOC[p,h]);
		end
	end

	return uc_results;

end; #end function
