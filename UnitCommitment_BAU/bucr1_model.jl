"""
Function that solves the first unit commitment optimization
"""
function bucr1_model(day::Int64, hour::Int64, df_gens::DataFrame,
    df_peakers::DataFrame, df_storage::DataFrame, fuelprice::Matrix{Float64},
    fuelprice_peakers::Matrix{Float64}, map_gens::Matrix{Int64},
	map_peakers::Matrix{Int64}, map_storage::Matrix{Int64},
	bucr1_results::UC_Results, sucr_results::UC_Results,
	bucr2_results::UC_Results, fucr_to_bucr1::UC_Results, bucr1_prepoc::DemandHrPreprocGens,
	bucr_commit_LB::Vector{Int64}, bucr_commit_UB::Vector{Int64},
	bucr_commit_peaker_LB::Vector{Int64}, bucr_commit_peaker_UB::Vector{Int64})

	t1_BUCR1model = time_ns()
    BUCR1model = direct_model(CPLEX.Optimizer())
    set_optimizer_attribute(BUCR1model, "CPX_PARAM_EPGAP", SOLVER_EPGAP)

    # Declaring the decision variables for conventional generators
    @variable(BUCR1model, bucrm_genOnOff[1:GENS], Bin) #Bin
    @variable(BUCR1model, bucrm_genStartUp[1:GENS], Bin) # startup variable
    @variable(BUCR1model, bucrm_genShutDown[1:GENS], Bin) # shutdown variable
    @variable(BUCR1model, bucrm_genOut[1:GENS]>=0) # Generator's output schedule
    @variable(BUCR1model, bucrm_genOut_Block[1:GENS, 1:BLOCKS]>=0) # Generator's output schedule from each block (block rfers to IHR curve blocks/segments)
    @variable(BUCR1model, bucrm_TotGenVioP[g=1:GENS]>=0)
    @variable(BUCR1model, bucrm_TotGenVioN[g=1:GENS]>=0)
    @variable(BUCR1model, bucrm_MaxGenVioP[g=1:GENS]>=0)
    @variable(BUCR1model, bucrm_MinGenVioP[g=1:GENS]>=0)
    #@variable(BUCR1model, bucrm_genResUp[1:GENS]>=0) # Generators' up reserve schedule
    #@variable(BUCR1model, bucrm_genResDn[1:GENS]>=0) # Generator's down rserve schedule

    # Declaring the decision variables for peakers
    @variable(BUCR1model, 0<=bucrm_peakerOnOff[1:PEAKERS]<=1) #Bin, relaxed
    @variable(BUCR1model, 0<=bucrm_peakerStartUp[1:PEAKERS]<=1) # startup variable
    @variable(BUCR1model, 0<=bucrm_peakerShutDown[1:PEAKERS]<=1) # shutdown variable
    @variable(BUCR1model, bucrm_peakerOut[1:PEAKERS]>=0) # Generator's output schedule
    @variable(BUCR1model, bucrm_peakerOut_Block[1:PEAKERS, 1:BLOCKS]>=0) # Generator's output schedule from each block (block rfers to IHR curve blocks/segments)

    # declaring decision variables for storage Units
    @variable(BUCR1model, bucrm_storgChrg[1:STORG_UNITS], Bin) #Bin variable equal to 1 if unit runs in the charging mode
    @variable(BUCR1model, bucrm_storgDisc[1:STORG_UNITS], Bin) #Bin variable equal to 1 if unit runs in the discharging mode
    @variable(BUCR1model, bucrm_storgIdle[1:STORG_UNITS], Bin) ##Bin variable equal to 1 if unit runs in the idle mode
    @variable(BUCR1model, bucrm_storgChrgPwr[1:STORG_UNITS]>=0) #Chargung power
    @variable(BUCR1model, bucrm_storgDiscPwr[1:STORG_UNITS]>=0) # Discharging Power
    @variable(BUCR1model, bucrm_storgSOC[1:STORG_UNITS]>=0) # state of charge (stored energy level for storage unit at time t)
    #@variable(BUCR1model, bucrm_storgResUp[1:STORG_UNITS]>=0) # Scheduled up reserve
    #@variable(BUCR1model, bucrm_storgResDn[1:STORG_UNITS]>=0) # Scheduled down reserve

    # declaring decision variables for renewable generation
    @variable(BUCR1model, bucrm_solarG[1:N_ZONES]>=0) # solar energy schedules
    @variable(BUCR1model, bucrm_windG[1:N_ZONES]>=0) # wind energy schedules
    @variable(BUCR1model, bucrm_hydroG[1:N_ZONES]>=0) # hydro energy schedules
    @variable(BUCR1model, bucrm_solarGSpil[1:N_ZONES]>=0) # solar energy schedules
    @variable(BUCR1model, bucrm_windGSpil[1:N_ZONES]>=0) # wind energy schedules
    @variable(BUCR1model, bucrm_hydroGSpil[1:N_ZONES]>=0) # hydro energy schedules

    # Declaring decision variables for hourly dispatched and curtailed demand
    @variable(BUCR1model, bucrm_Demand[1:N_ZONES]>=0) # Hourly scheduled demand
    @variable(BUCR1model, bucrm_Demand_Curt[1:N_ZONES]>=0) # Hourly schedule demand
    @variable(BUCR1model, bucrm_OverGen[1:N_ZONES]>=0) #

    # declaring variables for transmission system
    @variable(BUCR1model, bucrm_voltAngle[1:N_ZONES]) #voltage angle at zone/bus n in t//
    @variable(BUCR1model, bucrm_powerFlow[1:N_ZONES, 1:M_ZONES]) #transmission Flow from zone n to zone m//

    # Defining the objective function that minimizes the overal cost of supplying electricity (=total variable, no-load, startup, and shutdown costs)

    #@objective(BUCR1model, Min, sum(sum(df_gens.VariableCost[g]*bucrm_genOut[g]+df_gens.NoLoadCost[g]*bucrm_genOnOff[g] +df_gens.StartUpCost[g]*bucrm_genStartUp[g] + df_gens.ShutdownCost[g]*bucrm_genShutDown[g] for g in 1:GENS)))
    @objective(BUCR1model, Min,
		sum(df_gens.IHRC_B1_HR[g]*fuelprice[g,day]*(bucrm_genOut_Block[g,1])
	   +df_gens.IHRC_B2_HR[g]*fuelprice[g,day]*(bucrm_genOut_Block[g,2])
	   +df_gens.IHRC_B3_HR[g]*fuelprice[g,day]*(bucrm_genOut_Block[g,3])
	   +df_gens.IHRC_B4_HR[g]*fuelprice[g,day]*(bucrm_genOut_Block[g,4])
	   +df_gens.IHRC_B5_HR[g]*fuelprice[g,day]*(bucrm_genOut_Block[g,5])
	   +df_gens.IHRC_B6_HR[g]*fuelprice[g,day]*(bucrm_genOut_Block[g,6])
	   +df_gens.IHRC_B7_HR[g]*fuelprice[g,day]*(bucrm_genOut_Block[g,7])
	   +df_gens.NoLoadHR[g]*fuelprice[g,day]*(bucrm_genOnOff[g])
	   +((df_gens.HotStartU_FixedCost[g]+(df_gens.HotStartU_HeatRate[g]*fuelprice[g,day]))*(bucrm_genStartUp[g]))
	   +df_gens.ShutdownCost[g]*(bucrm_genShutDown[g])
	   +(bucrm_TotGenVioP[g]*VIOLATION_PENALTY)+(bucrm_TotGenVioN[g]*VIOLATION_PENALTY)+(bucrm_MaxGenVioP[g]*VIOLATION_PENALTY)+(bucrm_MinGenVioP[g]*VIOLATION_PENALTY) for g in 1:GENS)
	   +sum(df_peakers.IHRC_B1_HR[k]*fuelprice_peakers[k,day]*(bucrm_peakerOut_Block[k,1])
	   +df_peakers.IHRC_B2_HR[k]*fuelprice_peakers[k,day]*(bucrm_peakerOut_Block[k,2])
	   +df_peakers.IHRC_B3_HR[k]*fuelprice_peakers[k,day]*(bucrm_peakerOut_Block[k,3])
	   +df_peakers.IHRC_B4_HR[k]*fuelprice_peakers[k,day]*(bucrm_peakerOut_Block[k,4])
	   +df_peakers.IHRC_B5_HR[k]*fuelprice_peakers[k,day]*(bucrm_peakerOut_Block[k,5])
	   +df_peakers.IHRC_B6_HR[k]*fuelprice_peakers[k,day]*(bucrm_peakerOut_Block[k,6])
	   +df_peakers.IHRC_B7_HR[k]*fuelprice_peakers[k,day]*(bucrm_peakerOut_Block[k,7])
	   +df_peakers.NoLoadHR[k]*fuelprice_peakers[k,day]*(bucrm_peakerOnOff[k])
	   +((df_peakers.HotStartU_FixedCost[k]+(df_peakers.HotStartU_HeatRate[k]*fuelprice_peakers[k,day]))*(bucrm_peakerStartUp[k]))
	   +df_peakers.ShutdownCost[k]*(bucrm_peakerShutDown[k]) for k in 1:PEAKERS)
	   +sum((bucrm_Demand_Curt[n]*LOAD_SHED_PENALTY)+(bucrm_OverGen[n]*OVERGEN_PENALTY) for n=1:N_ZONES) )

    # Baseload Operation of nuclear units
    @constraint(BUCR1model, conNuckBaseLoad[g=1:GENS], bucrm_genOnOff[g]>=df_gens.Nuclear[g]) #
    @constraint(BUCR1model, conNuclearTotGenZone[n=1:N_ZONES],
    	sum((bucrm_genOut[g]*map_gens[g,n]*df_gens.Nuclear[g]) for g=1:GENS) - bucr1_prepoc.nuclear[n] ==0)

    #Limits on generation of cogen units
    @constraint(BUCR1model, conCoGenBaseLoad[g=1:GENS], bucrm_genOnOff[g]>=df_gens.Cogen[g]) #
    @constraint(BUCR1model, conCoGenTotGenZone[n=1:N_ZONES], sum((bucrm_genOut[g]*map_gens[g,n]*df_gens.Cogen[g]) for g=1:GENS) -bucr1_prepoc.cogen[n] ==0)

    # Constraints representing technical limits of conventional generators
    #Status transition trajectory of
    @constraint(BUCR1model, conStartUpAndDn[g=1:GENS], (bucrm_genOnOff[g] - bucr1_results.gens.onoff_init[g] - bucrm_genStartUp[g] + bucrm_genShutDown[g])==0)
    # Max Power generation limit in Block 1
    @constraint(BUCR1model, conMaxPowBlock1[g=1:GENS],  bucrm_genOut_Block[g,1] <= df_gens.IHRC_B1_Q[g]*bucrm_genOnOff[g] )
    # Max Power generation limit in Block 2
    @constraint(BUCR1model, conMaxPowBlock2[g=1:GENS],  bucrm_genOut_Block[g,2] <= df_gens.IHRC_B2_Q[g]*bucrm_genOnOff[g] )
    # Max Power generation limit in Block 3
    @constraint(BUCR1model, conMaxPowBlock3[g=1:GENS],  bucrm_genOut_Block[g,3] <= df_gens.IHRC_B3_Q[g]*bucrm_genOnOff[g] )
    # Max Power generation limit in Block 4
    @constraint(BUCR1model, conMaxPowBlock4[g=1:GENS],  bucrm_genOut_Block[g,4] <= df_gens.IHRC_B4_Q[g]*bucrm_genOnOff[g] )
    # Max Power generation limit in Block 5
    @constraint(BUCR1model, conMaxPowBlock5[g=1:GENS],  bucrm_genOut_Block[g,5] <= df_gens.IHRC_B5_Q[g]*bucrm_genOnOff[g] )
    # Max Power generation limit in Block 6
    @constraint(BUCR1model, conMaxPowBlock6[g=1:GENS],  bucrm_genOut_Block[g,6] <= df_gens.IHRC_B6_Q[g]*bucrm_genOnOff[g] )
    # Max Power generation limit in Block 7
    @constraint(BUCR1model, conMaxPowBlock7[g=1:GENS],  bucrm_genOut_Block[g,7] <= df_gens.IHRC_B7_Q[g]*bucrm_genOnOff[g] )
    # Total Production of each generation equals the sum of generation from its all blocks
    @constraint(BUCR1model, conTotalGen[g=1:GENS],  sum(bucrm_genOut_Block[g,b] for b=1:BLOCKS)+ bucrm_TotGenVioP[g]-bucrm_TotGenVioN[g]==bucrm_genOut[g])
    #Max power generation limit
    @constraint(BUCR1model, conMaxPow[g=1:GENS],  bucrm_genOut[g] - bucrm_MaxGenVioP[g] <= df_gens.MaxPowerOut[g]*bucrm_genOnOff[g])
    # Min power generation limit
    @constraint(BUCR1model, conMinPow[g=1:GENS],  bucrm_genOut[g] + bucrm_MinGenVioP[g] >= df_gens.MinPowerOut[g]*bucrm_genOnOff[g])
    #Up ramp rate limit
    @constraint(BUCR1model, conRampRateUp[g=1:GENS], (bucrm_genOut[g] - bucr1_results.gens.power_out_init[g] <=(df_gens.RampUpLimit[g]*bucr1_results.gens.onoff_init[g]) + (df_gens.RampStartUpLimit[g]*bucrm_genStartUp[g])))
    # Down ramp rate limit
    @constraint(BUCR1model, conRampRateDown[g=1:GENS], (bucr1_results.gens.power_out_init[g] - bucrm_genOut[g] <=(df_gens.RampDownLimit[g]*bucrm_genOnOff[g]) + (df_gens.RampShutDownLimit[g]*bucrm_genShutDown[g])))
    # Min Up Time limit with alternative formulation
    #The next two constraints enforce limits on binary commitment variables of slow and fast generators
    # scheduled slow units are forced to remain on, offline slow units remain off, and fast start units
    # could change their commitment dependent on their MUT and MDT
    @constraint(BUCR1model, conCommitmentUB[g=1:GENS], (bucrm_genOnOff[g] <= bucr_commit_UB[g]))
    # if the generator is slow start and scheduled "on" in the FUCR,  is fixed by the following constraint
    @constraint(BUCR1model, conCommitmentLB[g=1:GENS], (bucrm_genOnOff[g] >= bucr_commit_LB[g]))

    # Constraints representing technical limits of peakers
    #Status transition trajectory of
    @constraint(BUCR1model, conStartUpAndDn_Peaker[k=1:PEAKERS], (bucrm_peakerOnOff[k] - bucr1_results.peakers.onoff_init[k] - bucrm_peakerStartUp[k] + bucrm_peakerShutDown[k])==0)
    # Max Power generation limit in Block 1
    @constraint(BUCR1model, conMaxPowBlock1_Peaker[k=1:PEAKERS],  bucrm_peakerOut_Block[k,1] <= df_peakers.IHRC_B1_Q[k]*bucrm_peakerOnOff[k] )
    # Max Power generation limit in Block 2
    @constraint(BUCR1model, conMaxPowBlock2_Peaker[k=1:PEAKERS],  bucrm_peakerOut_Block[k,2] <= df_peakers.IHRC_B2_Q[k]*bucrm_peakerOnOff[k] )
    # Max Power generation limit in Block 3
    @constraint(BUCR1model, conMaxPowBlock3_Peaker[k=1:PEAKERS],  bucrm_peakerOut_Block[k,3] <= df_peakers.IHRC_B3_Q[k]*bucrm_peakerOnOff[k] )
    # Max Power generation limit in Block 4
    @constraint(BUCR1model, conMaxPowBlock4_Peaker[k=1:PEAKERS],  bucrm_peakerOut_Block[k,4] <= df_peakers.IHRC_B4_Q[k]*bucrm_peakerOnOff[k] )
    # Max Power generation limit in Block 5
    @constraint(BUCR1model, conMaxPowBlock5_Peaker[k=1:PEAKERS],  bucrm_peakerOut_Block[k,5] <= df_peakers.IHRC_B5_Q[k]*bucrm_peakerOnOff[k] )
    # Max Power generation limit in Block 6
    @constraint(BUCR1model, conMaxPowBlock6_Peaker[k=1:PEAKERS],  bucrm_peakerOut_Block[k,6] <= df_peakers.IHRC_B6_Q[k]*bucrm_peakerOnOff[k] )
    # Max Power generation limit in Block 7
    @constraint(BUCR1model, conMaxPowBlock7_Peaker[k=1:PEAKERS],  bucrm_peakerOut_Block[k,7] <= df_peakers.IHRC_B7_Q[k]*bucrm_peakerOnOff[k] )
    # Total Production of each generation equals the sum of generation from its all blocks
    @constraint(BUCR1model, conTotalGen_Peaker[k=1:PEAKERS], sum(bucrm_peakerOut_Block[k,b] for b=1:BLOCKS)>= bucrm_peakerOut[k])
    #Max power generation limit
    @constraint(BUCR1model, conMaxPow_Peaker[k=1:PEAKERS],  bucrm_peakerOut[k] <= df_peakers.MaxPowerOut[k]*bucrm_peakerOnOff[k])
    # Min power generation limit
    @constraint(BUCR1model, conMinPow_Peaker[k=1:PEAKERS],  bucrm_peakerOut[k] >= df_peakers.MinPowerOut[k]*bucrm_peakerOnOff[k])
    #Up ramp rate limit
    @constraint(BUCR1model, conRampRateUp_Peaker[k=1:PEAKERS], (bucrm_peakerOut[k] - bucr1_results.peakers.power_out_init[k] <=(df_peakers.RampUpLimit[k]*bucr1_results.peakers.onoff_init[k]) + (df_peakers.RampStartUpLimit[k]*bucrm_peakerStartUp[k])))
    # Down ramp rate limit
    @constraint(BUCR1model, conRampRateDown_Peaker[k=1:PEAKERS], (bucr1_results.peakers.power_out_init[k] - bucrm_peakerOut[k] <=(df_peakers.RampDownLimit[k]*bucrm_peakerOnOff[k]) + (df_peakers.RampShutDownLimit[k]*bucrm_peakerShutDown[k])))
    # Min Up Time limit with alternative formulation
    #The next two constraints enforce limits on binary commitment variables of slow and fast generators
    # scheduled slow units are forced to remain on, offline slow units remain off, and fast start units
    # could change their commitment dependent on their MUT and MDT
    @constraint(BUCR1model, conCommitmentUB_Peaker[k=1:PEAKERS], (bucrm_peakerOnOff[k] <= bucr_commit_peaker_UB[k]))
    # if the generator is slow start and scheduled "on" in the FUCR,  is fixed by the following constraint
    @constraint(BUCR1model, conCommitmentLB_Peaker[k=1:PEAKERS], (bucrm_peakerOnOff[k] >= bucr_commit_peaker_LB[k]))

    # Renewable generation constraints
    @constraint(BUCR1model, conSolarLimit[n=1:N_ZONES], bucrm_solarG[n] + bucrm_solarGSpil[n] <= bucr1_prepoc.solar[n])
    @constraint(BUCR1model, conWindLimit[n=1:N_ZONES], bucrm_windG[n] + bucrm_windGSpil[n] <= bucr1_prepoc.wind[n])
    @constraint(BUCR1model, conHydroLimit[n=1:N_ZONES], bucrm_hydroG[n] + bucrm_hydroGSpil[n] <= bucr1_prepoc.hydro[n])

    # Constraints representing technical characteristics of storage units
    # the next three constraints fix the balancing charging/discharging/Idle status to their optimal outcomes as determined by FUCR
    @constraint(BUCR1model, conStorgChrgStatusFixed[p=1:STORG_UNITS], (bucrm_storgChrg[p]==fucr_to_bucr1.storg.chrg[p,hour]))
    @constraint(BUCR1model, conStorgDisChrgStatusFixed[p=1:STORG_UNITS], (bucrm_storgDisc[p]==fucr_to_bucr1.storg.disc[p,hour]))
    @constraint(BUCR1model, conStorgIdleStatusFixed[p=1:STORG_UNITS], (bucrm_storgIdle[p]==fucr_to_bucr1.storg.idle[p,hour]))

    # charging power limit
    @constraint(BUCR1model, conStrgChargPowerLimit[p=1:STORG_UNITS], (bucrm_storgChrgPwr[p])<=df_storage.Power[p]*bucrm_storgChrg[p])
    # Discharging power limit
    @constraint(BUCR1model, conStrgDisChgPowerLimit[p=1:STORG_UNITS], (bucrm_storgDiscPwr[p])<=df_storage.Power[p]*bucrm_storgDisc[p])
    # State of charge at t
    @constraint(BUCR1model, conStorgSOC[p=1:STORG_UNITS], bucrm_storgSOC[p]==bucr1_results.storg.soc_init[p]-(bucrm_storgDiscPwr[p]/df_storage.TripEfficDown[p])+(bucrm_storgChrgPwr[p]*df_storage.TripEfficUp[p])-(bucrm_storgSOC[p]*df_storage.SelfDischarge[p]))
    # minimum energy limit
    @constraint(BUCR1model, conMinEnrgStorgLimi[p=1:STORG_UNITS], bucrm_storgSOC[p]>=0)
    # Maximum energy limit
    @constraint(BUCR1model, conMaxEnrgStorgLimi[p=1:STORG_UNITS], bucrm_storgSOC[p]<=(df_storage.Power[p]/df_storage.PowerToEnergRatio[p]))

    # Constraints representing transmission grid capacity constraints
    # DC Power Flow Calculation
    #@constraint(BUCR1model, conDCPowerFlowPos[n=1:N_ZONES, m=1:N_ZONES], bucrm_powerFlow[n,m]-(TranS[n,m]*(bucrm_voltAngle[n]-bucrm_voltAngle[m])) ==0)
    @constraint(BUCR1model, conDCPowerFlowNeg[n=1:N_ZONES, m=1:N_ZONES], bucrm_powerFlow[n,m]+bucrm_powerFlow[m,n]==0)
    # Tranmission flow bounds (from n to m and from m to n)
    @constraint(BUCR1model, conPosFlowLimit[n=1:N_ZONES, m=1:N_ZONES], bucrm_powerFlow[n,m]<=TranC[n,m])
    @constraint(BUCR1model, conNegFlowLimit[n=1:N_ZONES, m=1:N_ZONES], bucrm_powerFlow[n,m]>=-TranC[n,m])
    # Voltage Angle bounds and reference point
    #@constraint(BUCR1model, conVoltAnglUB[n=1:N_ZONES], bucrm_voltAngle[n]<=π)
    #@constraint(BUCR1model, conVoltAnglLB[n=1:N_ZONES], bucrm_voltAngle[n]>=-π)
    #@constraint(BUCR1model, conVoltAngRef, bucrm_voltAngle[1]==0)

    # Demand-side Constraints
    @constraint(BUCR1model, conDemandLimit[n=1:N_ZONES], bucrm_Demand[n]+ bucrm_Demand_Curt[n] == bucr1_prepoc.demand[n])

    # Demand Curtailment and wind generation limits
    @constraint(BUCR1model, conDemandCurtLimit[n=1:N_ZONES], bucrm_Demand_Curt[n] <= LOAD_SHED_MAX);
    @constraint(BUCR1model, conOverGenLimit[n=1:N_ZONES], bucrm_OverGen[n] <= OVERGEN_MAX);

    # System-wide Constraints
    #nodal balance constraint
    @constraint(BUCR1model, conNodBalanc[n=1:N_ZONES],
        sum((bucrm_genOut[g]*map_gens[g,n]) for g=1:GENS) +
        sum((bucrm_peakerOut[k]*map_peakers[k,n]) for k=1:PEAKERS) +
        sum((bucrm_storgDiscPwr[p]*map_storage[p,n]) for p=1:STORG_UNITS) -
        sum((bucrm_storgChrgPwr[p]*map_storage[p,n]) for p=1:STORG_UNITS) + bucrm_solarG[n] + bucrm_windG[n] +bucrm_hydroG[n] - bucrm_OverGen[n]- bucrm_Demand[n] == sum(bucrm_powerFlow[n,m] for m=1:M_ZONES))
    # Minimum up reserve requirement
    #    @constraint(BUCR1model, conMinUpReserveReq[t=1:N_Hrs_BUCR], sum(genResUp[g,t] for g=1:GENS) + sum(storgResUp[p,t] for p=1:STORG_UNITS) >= Reserve_Req_Up[t] )

    # Minimum down reserve requirement
    #    @constraint(BUCR1model, conMinDnReserveReq[t=1:N_Hrs_BUCR], sum(genResDn[g,t] for g=1:GENS) + sum(storgResDn[p,t] for p=1:STORG_UNITS) >= Reserve_Req_Dn[t] )

    t2_BUCR1model = time_ns()
    time_BUCR1model = (t2_BUCR1model -t1_BUCR1model)/1.0e9;
    @info "BUCR1model for day: $day, hour $(hour+INIT_HR_FUCR) setup executed in (s):  $time_BUCR1model";

    open(".//outputs//time_performance.csv", FILE_ACCESS_APPEND) do io
    		writedlm(io, hcat("BUCR1model", time_BUCR1model, "day: $day",
    				"hour $(hour+INIT_HR_FUCR)", "", "Model Setup"), ',')
    end; # closes file

    # solve the First WAUC model (BUCR)
    JuMP.optimize!(BUCR1model)

    # Pricing general results in the terminal window
    println("Objective value: ", JuMP.objective_value(BUCR1model))
    open(".//outputs//objective_values_v76.csv", FILE_ACCESS_APPEND) do io
    		writedlm(io, hcat("BUCR1model", "day: $day",
    				"hour $(hour+INIT_HR_FUCR)", "", JuMP.objective_value(BUCR1model)), ',')
    end;

    println("------------------------------------")
    println("------- BAUC1 OBJECTIVE VALUE -------")
    println("Objective value for day ", day, " and hour ", hour+INIT_HR_FUCR," is: ", JuMP.objective_value(BUCR1model))
    println("------------------------------------")
    println("------- BAUC1 PRIMAL STATUS -------")
    println(primal_status(BUCR1model))
    println("------------------------------------")
    println("------- BAUC1 DUAL STATUS -------")
    println(JuMP.dual_status(BUCR1model))
    println("Day: ", day, " and hour ", hour+INIT_HR_FUCR, ": solved")
    println("---------------------------")
    println("BUCR1model Number of variables: ", JuMP.num_variables(BUCR1model))
    @info "BUCR1model Number of variables: " JuMP.num_variables(BUCR1model)
    open(".//outputs//time_performance.csv", FILE_ACCESS_APPEND) do io
    		writedlm(io, hcat("BUCR1model", JuMP.num_variables(BUCR1model), "day: $day",
    				"hour $(hour+INIT_HR_FUCR)", "", "Variables"), ',')
    end;

    @debug "BUCR1model for day: $day, hour $(hour+INIT_HR_FUCR) optimized executed in (s): $(solve_time(BUCR1model))";

    t1_write_BUCR1model_results = time_ns()
    open(".//outputs//time_performance.csv", FILE_ACCESS_APPEND) do io
    		writedlm(io, hcat("BUCR1model", solve_time(BUCR1model), "day: $day",
    				"hour $(hour+INIT_HR_FUCR)", "", "Model Optimization"), ',')
    end; # closes file

    ## Write the optimal outcomes into spreadsheets
    #TODO: Later we need to include a variable for day so the cell number in
    # which the results are printed is updated accordingly
    # Write the conventional generators' schedules
    open(".//outputs//BUCR_GenOutputs.csv", FILE_ACCESS_APPEND) do io
    	for g=1:GENS
    		writedlm(io, hcat(day, hour+INIT_HR_FUCR, g, df_gens.UNIT_ID[g],
    			df_gens.MinPowerOut[g], df_gens.MaxPowerOut[g],
    			JuMP.value.(bucrm_genOut[g]), JuMP.value.(bucrm_genOnOff[g]),
    			JuMP.value.(bucrm_genShutDown[g]),
    			JuMP.value.(bucrm_genStartUp[g]),
    			JuMP.value.(bucrm_TotGenVioP[g]),
    			JuMP.value.(bucrm_TotGenVioN[g]), JuMP.value.(bucrm_MaxGenVioP[g]),
    			JuMP.value.(bucrm_MinGenVioP[g]) ), ',')
    	end # ends the loop
    end; # closes file

    # Write the conventional peakers' schedules
    open(".//outputs//BUCR_PeakerOutputs.csv", FILE_ACCESS_APPEND) do io
    	for k=1:PEAKERS
    		writedlm(io, hcat(day, hour+INIT_HR_FUCR, k, df_peakers.UNIT_ID[k],
    			df_peakers.MinPowerOut[k], df_peakers.MaxPowerOut[k],
    			JuMP.value.(bucrm_peakerOut[k]),
    			JuMP.value.(bucrm_peakerOnOff[k]),
    			JuMP.value.(bucrm_peakerShutDown[k]),
    			JuMP.value.(bucrm_peakerStartUp[k]) ), ',')
    	end # ends the loop
    end; # closes file

    # Writing storage units' optimal schedules in CSV file
    open(".//outputs//BUCR_StorageOutputs.csv", FILE_ACCESS_APPEND) do io
    	for p=1:STORG_UNITS
    		writedlm(io, hcat(day, hour+INIT_HR_FUCR, p, df_storage.Name[p],
    			df_storage.Power[p],
    			df_storage.Power[p]/df_storage.PowerToEnergRatio[p],
    			JuMP.value.(bucrm_storgChrg[p]),
    			JuMP.value.(bucrm_storgDisc[p]),
    			JuMP.value.(bucrm_storgIdle[p]),
    			JuMP.value.(bucrm_storgChrgPwr[p]),
    			JuMP.value.(bucrm_storgDiscPwr[p]),
    			JuMP.value.(bucrm_storgSOC[p]) ), ',')
    	end # ends the loop
    end; # closes file

    # Writing the transmission flow schedules in CSV file
    open(".//outputs//BUCR_TranFlowOutputs.csv", FILE_ACCESS_APPEND) do io
    	for n=1:N_ZONES, m=1:M_ZONES
    		writedlm(io, hcat(day, hour+INIT_HR_FUCR, n, m,
    			JuMP.value.(bucrm_powerFlow[n,m]), TranC[n,m] ), ',')
    	end # ends the loop
    end; # closes file

    # Writing the curtilment, overgeneration, and spillage outcomes in CSV file
    open(".//outputs//BUCR_Curtail.csv", FILE_ACCESS_APPEND) do io
    	for n=1:N_ZONES
    	   writedlm(io, hcat(day, hour+INIT_HR_FUCR, n,
    		   JuMP.value.(bucrm_OverGen[n]), JuMP.value.(bucrm_Demand_Curt[n]),
    		   JuMP.value.(bucrm_windGSpil[n]), JuMP.value.(bucrm_solarGSpil[n]),
    		   JuMP.value.(bucrm_hydroGSpil[n]) ), ',')
    	end # ends the loop
    end; # closes file

    t2_write_BUCR1model_results = time_ns()
    time_write_BUCR1model_results = (t2_write_BUCR1model_results -t1_write_BUCR1model_results)/1.0e9;
    @info "Write BUCR1model results for day $day and hour $(hour+INIT_HR_FUCR) executed in (s): $time_write_BUCR1model_results";

    open(".//outputs//time_performance.csv", FILE_ACCESS_APPEND) do io
    		writedlm(io, hcat("BUCR1model", time_write_BUCR1model_results, "day: $day",
    				"hour $(hour+INIT_HR_FUCR)", "", "Write CSV files"), ',')
    end; #closes file
    ## Initilization of the next UC Run
    # This must be updated later when we run two WAUCs every day and then RTUCs
    # Setting initial values for bucr1_results (next hour), SUCR1, and bucr2_results
    t1_bucrm_init_next_UC = time_ns();

    for g=1:GENS
    	global bucr1_results.gens.onoff_init[g] = JuMP.value.(bucrm_genOnOff[g]);
    	global bucr1_results.gens.power_out_init[g] = JuMP.value.(bucrm_genOut[g]);
    	if hour==(INIT_HR_SUCR-INIT_HR_FUCR)
    		bucr2_results.gens.onoff_init[g] = JuMP.value.(bucrm_genOnOff[g]);
    		bucr2_results.gens.power_out_init[g] = JuMP.value.(bucrm_genOut[g]);
    		sucr_results.gens.onoff_init[g] = JuMP.value.(bucrm_genOnOff[g]);
    		sucr_results.gens.power_out_init[g] = JuMP.value.(bucrm_genOut[g]);
    	end
    end

    for k=1:PEAKERS
    	bucr1_results.peakers.onoff_init[k] = round(JuMP.value.(bucrm_peakerOnOff[k]));
    	bucr1_results.peakers.power_out_init[k] = JuMP.value.(bucrm_peakerOut[k]);
    	if hour==(INIT_HR_SUCR-INIT_HR_FUCR)
    		bucr2_results.peakers.onoff_init[k] = round(JuMP.value.(bucrm_peakerOnOff[k]));
    		bucr2_results.peakers.power_out_init[k] = JuMP.value.(bucrm_peakerOut[k]);
    		sucr_results.peakers.onoff_init[k] = round(JuMP.value.(bucrm_peakerOnOff[k]));
    		sucr_results.peakers.power_out_init[k] = JuMP.value.(bucrm_peakerOut[k]);
    	end
    end

    for p=1:STORG_UNITS
    	bucr1_results.storg.soc_init[p]=JuMP.value.(bucrm_storgSOC[p]);
    	if hour==(INIT_HR_SUCR-INIT_HR_FUCR)
    		bucr2_results.storg.soc_init[p] = JuMP.value.(bucrm_storgSOC[p]);
    		sucr_results.storg.soc_init[p] = JuMP.value.(bucrm_storgSOC[p]);
    	end
    end

	#NOTE: No need to use round function (round(JuMP.value.(BUCR1_genStartUp[g])))==1
    for g=1:GENS
    	if JuMP.value.(bucrm_genStartUp[g]) > 0.5
    		bucr1_results.gens.uptime_init[g]= 1;
    		bucr1_results.gens.dntime_init[g] = 0;
    	elseif JuMP.value.(bucrm_genShutDown[g]) > 0.5
    		bucr1_results.gens.uptime_init[g]= 0;
    		bucr1_results.gens.dntime_init[g]= 1;
    	else
    		if JuMP.value.(bucrm_genOnOff[g]) > 0.5
    			bucr1_results.gens.uptime_init[g]= bucr1_results.gens.uptime_init[g]+1;
    			bucr1_results.gens.dntime_init[g]= 0;
    		else
    			bucr1_results.gens.uptime_init[g]= 0;
    			bucr1_results.gens.dntime_init[g]= bucr1_results.gens.dntime_init[g]+1;
    		end
    	end
    	if hour == (INIT_HR_SUCR-INIT_HR_FUCR)
    		bucr2_results.gens.uptime_init[g]= bucr1_results.gens.uptime_init[g];
    		bucr2_results.gens.dntime_init[g]= bucr1_results.gens.dntime_init[g];
    		sucr_results.gens.uptime_init[g]= bucr1_results.gens.uptime_init[g];
    		sucr_results.gens.dntime_init[g]= bucr1_results.gens.dntime_init[g];
    	end
    end
    #TODO:No need to use the round function.  Since 0<= bucrm_peakerStartUp<=1,
    # bucrm_genStartUp>0 in the If Statement is enough
    for k=1:PEAKERS
    	if (JuMP.value.(bucrm_peakerStartUp[k]))>0
    		bucr1_results.peakers.uptime_init[k]= 1;
    		bucr1_results.peakers.dntime_init[k] = 0;
    	elseif (JuMP.value.(bucrm_peakerShutDown[k]))>0
    		bucr1_results.peakers.uptime_init[k]= 0;
    		bucr1_results.peakers.dntime_init[k]= 1;
    	else
    		if (JuMP.value.(bucrm_peakerOnOff[k]))>0
    			bucr1_results.peakers.uptime_init[k]= bucr1_results.peakers.uptime_init[k]+1;
    			bucr1_results.peakers.dntime_init[k]= 0;
    		else
    			bucr1_results.peakers.uptime_init[k]= 0;
    			bucr1_results.peakers.dntime_init[k]= bucr1_results.peakers.dntime_init[k]+1;
    		end
    	end
    	if hour==(INIT_HR_SUCR-INIT_HR_FUCR)
    		bucr2_results.peakers.uptime_init[k]= bucr1_results.peakers.uptime_init[k];
    		bucr2_results.peakers.dntime_init[k]= bucr1_results.peakers.dntime_init[k];
    		sucr_results.peakers.uptime_init[k]= bucr1_results.peakers.uptime_init[k];
    		sucr_results.peakers.dntime_init[k]= bucr1_results.peakers.dntime_init[k];
    	end
    end

    t2_bucrm_init_next_UC = time_ns();

    time_bucrm_init_next_UC = (t2_bucrm_init_next_UC -t1_bucrm_init_next_UC)/1.0e9;
    @info "bucrm_init_next_UC data handling for day $day and hour $(hour+INIT_HR_FUCR) executed in (s): $time_bucrm_init_next_UC";

    open(".//outputs//time_performance.csv", FILE_ACCESS_APPEND) do io
    		writedlm(io, hcat("BUCR1model", time_bucrm_init_next_UC, "day: $day",
    				"hour $(hour+INIT_HR_FUCR)", "bucrm_init_next_UC", "Data Manipulation"), ',')
    end; #closes file

    return bucr1_results, sucr_results, bucr2_results
end; # function
