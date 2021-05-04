include("constants.jl")

function fucr_model(DF_Generators, DF_Peakers, FuelPrice, FuelPricePeakers, DF_Storage)
 FUCRmodel = direct_model(CPLEX.Optimizer())
    #set_optimizer_attribute(FUCRmodel, "CPX_PARAM_EPINT", 1e-5)
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
    @variable(FUCRmodel, fucrm_totGenVioP[g=1:GENS, 1:HRS_FUCR]>=0)
    @variable(FUCRmodel, fucrm_totGenVioN[g=1:GENS, 1:HRS_FUCR]>=0)
    @variable(FUCRmodel, fucrm_maxGenVioP[g=1:GENS, 1:HRS_FUCR]>=0)
    @variable(FUCRmodel, fucrm_minGenVioP[g=1:GENS, 1:HRS_FUCR]>=0)

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
    @variable(FUCRmodel, fucrm_demand[1:N_ZONES, 1:HRS_FUCR]>=0) # Hourly scheduled demand
    @variable(FUCRmodel, fucrm_demand_curt[1:N_ZONES, 1:HRS_FUCR]>=0) # Hourly schedule demand

    # Declaring variables for transmission system
    @variable(FUCRmodel, fucrm_voltangle[1:N_ZONES, 1:HRS_FUCR]) #voltage angle at zone/bus n in t//
    @variable(FUCRmodel, fucrm_powerflow[1:N_ZONES, 1:M_Zones, 1:HRS_FUCR]) #transmission Flow from zone n to zone m//

    # Declaring over and undergeneration decision variable
    @variable(FUCRmodel, fucrm_overgen[1:N_ZONES, 1:HRS_FUCR]>=0) #overgeneration at zone n and time t//

    # Defining the objective function that minimizes the overal cost of supplying electricity (=total variable, no-load, startup, and shutdown costs)
    @objective(FUCRmodel, Min, sum(sum(DF_Generators.IHRC_B1_HR[g]*FuelPrice[g,day]*fucrm_genOut_Block[g,1,t]
                                       +DF_Generators.IHRC_B2_HR[g]*FuelPrice[g,day]*fucrm_genOut_Block[g,2,t]
                                       +DF_Generators.IHRC_B3_HR[g]*FuelPrice[g,day]*fucrm_genOut_Block[g,3,t]
                                       +DF_Generators.IHRC_B4_HR[g]*FuelPrice[g,day]*fucrm_genOut_Block[g,4,t]
                                       +DF_Generators.IHRC_B5_HR[g]*FuelPrice[g,day]*fucrm_genOut_Block[g,5,t]
                                       +DF_Generators.IHRC_B6_HR[g]*FuelPrice[g,day]*fucrm_genOut_Block[g,6,t]
                                       +DF_Generators.IHRC_B7_HR[g]*FuelPrice[g,day]*fucrm_genOut_Block[g,7,t]
                                       +DF_Generators.NoLoadHR[g]*FuelPrice[g,day]*fucrm_genOnOff[g,t]
                                       +((DF_Generators.HotStartU_FixedCost[g]
                                       +(DF_Generators.HotStartU_HeatRate[g]*FuelPrice[g,day]))*fucrm_genStartUp[g,t])
                                       +DF_Generators.ShutdownCost[g]*fucrm_genShutDown[g, t]
                                       +(fucrm_totGenVioP[g,t]*VIOLATION_PENALTY)
                                       +(fucrm_totGenVioN[g,t]*VIOLATION_PENALTY)
                                       +(fucrm_maxGenVioP[g,t]*VIOLATION_PENALTY)
                                       +(fucrm_minGenVioP[g,t]*VIOLATION_PENALTY) for g in 1:GENS)
                                       +sum(DF_Peakers.IHRC_B1_HR[k]*FuelPricePeakers[k,day]*fucrm_peakerOut_Block[k,1,t]
                                       +DF_Peakers.IHRC_B2_HR[k]*FuelPricePeakers[k,day]*fucrm_peakerOut_Block[k,2,t]
                                       +DF_Peakers.IHRC_B3_HR[k]*FuelPricePeakers[k,day]*fucrm_peakerOut_Block[k,3,t]
                                       +DF_Peakers.IHRC_B4_HR[k]*FuelPricePeakers[k,day]*fucrm_peakerOut_Block[k,4,t]
                                       +DF_Peakers.IHRC_B5_HR[k]*FuelPricePeakers[k,day]*fucrm_peakerOut_Block[k,5,t]
                                       +DF_Peakers.IHRC_B6_HR[k]*FuelPricePeakers[k,day]*fucrm_peakerOut_Block[k,6,t]
                                       +DF_Peakers.IHRC_B7_HR[k]*FuelPricePeakers[k,day]*fucrm_peakerOut_Block[k,7,t]
                                       +DF_Peakers.NoLoadHR[k]*FuelPricePeakers[k,day]*fucrm_peakerOnOff[k,t]
                                       +((DF_Peakers.HotStartU_FixedCost[k]
                                       +(DF_Peakers.HotStartU_HeatRate[k]*FuelPricePeakers[k,day]))*fucrm_peakerStartUp[k,t])
                                       +DF_Peakers.ShutdownCost[k]*fucrm_peakerShutDown[k, t] for k in 1:PEAKERS) for t in 1:HRS_FUCR)
                                       +sum(sum((fucrm_demand_curt[n,t]*LOAD_SHED_PENALTY)
                                       +(fucrm_overgen[n,t]*OVERGEN_PENALTY) for n=1:N_ZONES) for t=1:HRS_FUCR))

    #Initialization of commitment and dispatch variables for convnentioal generatoes at t=0 (representing the last hour of previous scheduling horizon day=day-1 and t=24)
    @constraint(FUCRmodel, conInitGenOnOff[g=1:GENS], fucrm_genOnOff[g,0]==FUCR.gens.onoff_init[g]) # initial generation level for generator g at t=0
    @constraint(FUCRmodel, conInitGenOut[g=1:GENS], fucrm_genOut[g,0]==FUCR.gens.power_out[g]) # initial on/off status for generators g at t=0
    #Initialization of commitment and dispatch variables for peakers  at t=0 (representing the last hour of previous scheduling horizon day=day-1 and t=24)
    @constraint(FUCRmodel, conInitGenOnOff_Peakers[k=1:PEAKERS], fucrm_peakerOnOff[k,0]==FUCR.peakers.onoff_init[k]) # initial generation level for peaker k at t=0
    @constraint(FUCRmodel, conInitGenOut_Peakers[k=1:PEAKERS], fucrm_peakerOut[k,0]==FUCR.peakers.power_out[k]) # initial on/off status for peaker k at t=0
    #Initialization of SOC variables for storage units at t=0 (representing the last hour of previous scheduling horizon day=day-1 and t=24)
    @constraint(FUCRmodel, conInitSOC[p=1:STORG_UNITS], fucrm_storgSOC[p,0]==FUCR.soc_init[p]) # SOC for storage unit p at t=0

    #Base-Load Operation of nuclear Generators
    @constraint(FUCRmodel, conNuckBaseLoad[t=1:HRS_FUCR, g=1:GENS], fucrm_genOnOff[g,t]>=DF_Generators.Nuclear[g]) #
    @constraint(FUCRmodel, conNuclearTotGenZone[t=1:HRS_FUCR, n=1:N_ZONES], sum((fucrm_genOut[g,t]*Map_Gens[g,n]*DF_Generators.Nuclear[g]) for g=1:GENS) -fucr_prep_demand.nuclear_wa[t,n] ==0)

    #Limits on generation of cogen units
    @constraint(FUCRmodel, conCoGenBaseLoad[t=1:HRS_FUCR, g=1:GENS], fucrm_genOnOff[g,t]>=DF_Generators.Cogen[g]) #
    @constraint(FUCRmodel, conCoGenTotGenZone[t=1:HRS_FUCR, n=1:N_ZONES], sum((fucrm_genOut[g,t]*Map_Gens[g,n]*DF_Generators.Cogen[g]) for g=1:GENS) -fucr_prep_demand.cogen_wa[t,n] ==0)

    # Constraints representing technical limits of conventional generators
    #Status transition trajectory of
    @constraint(FUCRmodel, conStartUpAndDn[t=1:HRS_FUCR, g=1:GENS], (fucrm_genOnOff[g,t] - fucrm_genOnOff[g,t-1] - fucrm_genStartUp[g,t] + fucrm_genShutDown[g,t])==0)
    # Max Power generation limit in Block 1
    @constraint(FUCRmodel, conMaxPowBlock1[t=1:HRS_FUCR, g=1:GENS],  fucrm_genOut_Block[g,1,t] <= DF_Generators.IHRC_B1_Q[g]*fucrm_genOnOff[g,t] )
    # Max Power generation limit in Block 2
    @constraint(FUCRmodel, conMaxPowBlock2[t=1:HRS_FUCR, g=1:GENS],  fucrm_genOut_Block[g,2,t] <= DF_Generators.IHRC_B2_Q[g]*fucrm_genOnOff[g,t] )
    # Max Power generation limit in Block 3
    @constraint(FUCRmodel, conMaxPowBlock3[t=1:HRS_FUCR, g=1:GENS],  fucrm_genOut_Block[g,3,t] <= DF_Generators.IHRC_B3_Q[g]*fucrm_genOnOff[g,t] )
    # Max Power generation limit in Block 4
    @constraint(FUCRmodel, conMaxPowBlock4[t=1:HRS_FUCR, g=1:GENS],  fucrm_genOut_Block[g,4,t] <= DF_Generators.IHRC_B4_Q[g]*fucrm_genOnOff[g,t] )
    # Max Power generation limit in Block 5
    @constraint(FUCRmodel, conMaxPowBlock5[t=1:HRS_FUCR, g=1:GENS],  fucrm_genOut_Block[g,5,t] <= DF_Generators.IHRC_B5_Q[g]*fucrm_genOnOff[g,t] )
    # Max Power generation limit in Block 6
    @constraint(FUCRmodel, conMaxPowBlock6[t=1:HRS_FUCR, g=1:GENS],  fucrm_genOut_Block[g,6,t] <= DF_Generators.IHRC_B6_Q[g]*fucrm_genOnOff[g,t] )
    # Max Power generation limit in Block 7
    @constraint(FUCRmodel, conMaxPowBlock7[t=1:HRS_FUCR, g=1:GENS],  fucrm_genOut_Block[g,7,t] <= DF_Generators.IHRC_B7_Q[g]*fucrm_genOnOff[g,t] )
    # Total Production of each generation equals the sum of generation from its all blocks
    @constraint(FUCRmodel, conTotalGen[t=1:HRS_FUCR, g=1:GENS],  sum(fucrm_genOut_Block[g,b,t] for b=1:BLOCKS) + fucrm_totGenVioP[g,t] - fucrm_totGenVioN[g,t] ==fucrm_genOut[g,t])
    #Max power generation limit
    @constraint(FUCRmodel, conMaxPow[t=1:HRS_FUCR, g=1:GENS],  fucrm_genOut[g,t]+fucrm_genResUp[g,t] - fucrm_maxGenVioP[g,t] <= DF_Generators.MaxPowerOut[g]*fucrm_genOnOff[g,t] )
    # Min power generation limit
    @constraint(FUCRmodel, conMinPow[t=1:HRS_FUCR, g=1:GENS],  fucrm_genOut[g,t]-fucrm_genResDn[g,t] + fucrm_minGenVioP[g,t] >= DF_Generators.MinPowerOut[g]*fucrm_genOnOff[g,t] )
    # Up reserve provision limit
    @constraint(FUCRmodel, conMaxResUp[t=1:HRS_FUCR, g=1:GENS], fucrm_genResUp[g,t] <= DF_Generators.SpinningRes_Limit[g]*fucrm_genOnOff[g,t] )
    # Non-Spinning Reserve Limit
    #    @constraint(FUCRmodel, conMaxNonSpinResUp[t=1:HRS_SUCR, g=1:GENS], fucrm_genResNonSpin[g,t] <= (DF_Generators.NonSpinningRes_Limit[g]*(1-fucrm_genOnOff[g,t])*DF_Generators.FastStart[g]))
    @constraint(FUCRmodel, conMaxNonSpinResUp[t=1:HRS_SUCR, g=1:GENS], fucrm_genResNonSpin[g,t] <= 0)
    #Down reserve provision limit
    @constraint(FUCRmodel, conMaxResDown[t=1:HRS_FUCR, g=1:GENS],  fucrm_genResDn[g,t] <= DF_Generators.SpinningRes_Limit[g]*fucrm_genOnOff[g,t] )
    #Up ramp rate limit
    @constraint(FUCRmodel, conRampRateUp[t=1:HRS_FUCR, g=1:GENS], (fucrm_genOut[g,t] - fucrm_genOut[g,t-1] <=(DF_Generators.RampUpLimit[g]*fucrm_genOnOff[g, t-1]) + (DF_Generators.RampStartUpLimit[g]*fucrm_genStartUp[g,t])))
    # Down ramp rate limit
    @constraint(FUCRmodel, conRampRateDown[t=1:HRS_FUCR, g=1:GENS], (fucrm_genOut[g,t-1] - fucrm_genOut[g,t] <=(DF_Generators.RampDownLimit[g]*fucrm_genOnOff[g,t]) + (DF_Generators.RampShutDownLimit[g]*fucrm_genShutDown[g,t])))
    # Min Up Time limit with alternative formulation
    @constraint(FUCRmodel, conUpTime[t=1:HRS_FUCR, g=1:GENS], (sum(fucrm_genStartUp[g,r] for r=lb_MUT[g,t]:t)<=fucrm_genOnOff[g,t]))
    # Min down Time limit with alternative formulation
    @constraint(FUCRmodel, conDownTime[t=1:HRS_FUCR, g=1:GENS], (1-sum(fucrm_genShutDown[g,s] for s=lb_MDT[g,t]:t)>=fucrm_genOnOff[g,t]))

    # Peaker Units' constraints
    #Status transition trajectory of
    @constraint(FUCRmodel, conStartUpAndDn_Peaker[t=1:HRS_FUCR, k=1:PEAKERS], (fucrm_peakerOnOff[k,t] - fucrm_peakerOnOff[k,t-1] - fucrm_peakerStartUp[k,t] + fucrm_peakerShutDown[k,t])==0)
    # Max Power generation limit in Block 1
    @constraint(FUCRmodel, conMaxPowBlock1_Peaker[t=1:HRS_FUCR, k=1:PEAKERS],  fucrm_peakerOut_Block[k,1,t] <= DF_Peakers.IHRC_B1_Q[k]*fucrm_peakerOnOff[k,t] )
    # Max Power generation limit in Block 2
    @constraint(FUCRmodel, conMaxPowBlock2_Peaker[t=1:HRS_FUCR, k=1:PEAKERS],  fucrm_peakerOut_Block[k,2,t] <= DF_Peakers.IHRC_B2_Q[k]*fucrm_peakerOnOff[k,t] )
    # Max Power generation limit in Block 3
    @constraint(FUCRmodel, conMaxPowBlock3_Peaker[t=1:HRS_FUCR, k=1:PEAKERS],  fucrm_peakerOut_Block[k,3,t] <= DF_Peakers.IHRC_B3_Q[k]*fucrm_peakerOnOff[k,t] )
    # Max Power generation limit in Block 4
    @constraint(FUCRmodel, conMaxPowBlock4_Peaker[t=1:HRS_FUCR, k=1:PEAKERS],  fucrm_peakerOut_Block[k,4,t] <= DF_Peakers.IHRC_B4_Q[k]*fucrm_peakerOnOff[k,t] )
    # Max Power generation limit in Block 5
    @constraint(FUCRmodel, conMaxPowBlock5_Peaker[t=1:HRS_FUCR, k=1:PEAKERS],  fucrm_peakerOut_Block[k,5,t] <= DF_Peakers.IHRC_B5_Q[k]*fucrm_peakerOnOff[k,t] )
    # Max Power generation limit in Block 6
    @constraint(FUCRmodel, conMaxPowBlock6_Peaker[t=1:HRS_FUCR, k=1:PEAKERS],  fucrm_peakerOut_Block[k,6,t] <= DF_Peakers.IHRC_B6_Q[k]*fucrm_peakerOnOff[k,t] )
    # Max Power generation limit in Block 7
    @constraint(FUCRmodel, conMaxPowBlock7_Peaker[t=1:HRS_FUCR, k=1:PEAKERS],  fucrm_peakerOut_Block[k,7,t] <= DF_Peakers.IHRC_B7_Q[k]*fucrm_peakerOnOff[k,t] )
    # Total Production of each generation equals the sum of generation from its all blocks
    @constraint(FUCRmodel, conTotalGen_Peaker[t=1:HRS_FUCR, k=1:PEAKERS],  sum(fucrm_peakerOut_Block[k,b,t] for b=1:BLOCKS)>=fucrm_peakerOut[k,t])
    #Max power generation limit
    @constraint(FUCRmodel, conMaxPow_Peaker[t=1:HRS_FUCR, k=1:PEAKERS],  fucrm_peakerOut[k,t]+fucrm_peakerResUp[k,t] <= DF_Peakers.MaxPowerOut[k]*fucrm_peakerOnOff[k,t] )
    # Min power generation limit
    @constraint(FUCRmodel, conMinPow_Peaker[t=1:HRS_FUCR, k=1:PEAKERS],  fucrm_peakerOut[k,t]-fucrm_peakerResDn[k,t] >= DF_Peakers.MinPowerOut[k]*fucrm_peakerOnOff[k,t] )
    # Up reserve provision limit
    @constraint(FUCRmodel, conMaxResUp_Peaker[t=1:HRS_FUCR, k=1:PEAKERS], fucrm_peakerResUp[k,t] <= DF_Peakers.SpinningRes_Limit[k]*fucrm_peakerOnOff[k,t] )
    # Non-Spinning Reserve Limit
    @constraint(FUCRmodel, conMaxNonSpinResUp_Peaker[t=1:HRS_SUCR, k=1:PEAKERS], fucrm_peakerResNonSpin[k,t] <= (DF_Peakers.NonSpinningRes_Limit[k]*(1-fucrm_peakerOnOff[k,t])))
    #Down reserve provision limit
    @constraint(FUCRmodel, conMaxResDown_Peaker[t=1:HRS_FUCR, k=1:PEAKERS],  fucrm_peakerResDn[k,t] <= DF_Peakers.SpinningRes_Limit[k]*fucrm_peakerOnOff[k,t] )
    #Up ramp rate limit
    @constraint(FUCRmodel, conRampRateUp_Peaker[t=1:HRS_FUCR, k=1:PEAKERS], (fucrm_peakerOut[k,t] - fucrm_peakerOut[k,t-1] <=(DF_Peakers.RampUpLimit[k]*fucrm_peakerOnOff[k, t-1]) + (DF_Peakers.RampStartUpLimit[k]*fucrm_peakerStartUp[k,t])))
    # Down ramp rate limit
    @constraint(FUCRmodel, conRampRateDown_Peaker[t=1:HRS_FUCR, k=1:PEAKERS], (fucrm_peakerOut[k,t-1] - fucrm_peakerOut[k,t] <=(DF_Peakers.RampDownLimit[k]*fucrm_peakerOnOff[k,t]) + (DF_Peakers.RampShutDownLimit[k]*fucrm_peakerShutDown[k,t])))
    # Min Up Time limit with alternative formulation
    @constraint(FUCRmodel, conUpTime_Peaker[t=1:HRS_FUCR, k=1:PEAKERS], (sum(fucrm_peakerStartUp[k,r] for r=lb_MUT_Peaker[k,t]:t)<=fucrm_peakerOnOff[k,t]))
    # Min down Time limit with alternative formulation
    @constraint(FUCRmodel, conDownTime_Peaker[t=1:HRS_FUCR, k=1:PEAKERS], (1-sum(fucrm_peakerShutDown[k,s] for s=lb_MDT_Peaker[k,t]:t)>=fucrm_peakerOnOff[k,t]))

    # Renewable generation constraints
    @constraint(FUCRmodel, conSolarLimit[t=1:HRS_FUCR, n=1:N_ZONES], fucrm_solarG[n, t] + fucrm_solarGSpil[n,t]<=fucr_prep_demand.solar_wa[t,n])
    @constraint(FUCRmodel, conWindLimit[t=1:HRS_FUCR, n=1:N_ZONES], fucrm_windG[n, t] + fucrm_windGSpil[n,t]<=fucr_prep_demand.wind_wa[t,n])
    @constraint(FUCRmodel, conHydroLimit[t=1:HRS_FUCR, n=1:N_ZONES], fucrm_hydroG[n, t] + fucrm_hydroGSpil[n,t]<=fucr_prep_demand.hydro_wa[t,n])

    #=
    @constraint(FUCRmodel, conSolarLimit[t=1:HRS_FUCR, n=1:N_ZONES], fucrm_solarG[n, t] + fucrm_solarGSpil[n,t]<=0)
    @constraint(FUCRmodel, conWindLimit[t=1:HRS_FUCR, n=1:N_ZONES], fucrm_windG[n, t] + fucrm_windGSpil[n,t]<=0)
    @constraint(FUCRmodel, conHydroLimit[t=1:HRS_FUCR, n=1:N_ZONES], fucrm_hydroG[n, t] + fucrm_hydroGSpil[n,t]<=0)
    =#

    # Constraints representing technical characteristics of storage units
    # status transition of storage units between charging, discharging, and idle modes
    @constraint(FUCRmodel, conStorgStatusTransition[t=1:HRS_FUCR, p=1:STORG_UNITS], (fucrm_storgChrg[p,t]+fucrm_storgDisc[p,t]+fucrm_storgIdle[p,t])==1)
    # charging power limit
    @constraint(FUCRmodel, conStrgChargPowerLimit[t=1:HRS_FUCR, p=1:STORG_UNITS], (fucrm_storgChrgPwr[p,t] - fucrm_storgResDn[p,t])<=DF_Storage.Power[p]*fucrm_storgChrg[p,t])
    # Discharging power limit
    @constraint(FUCRmodel, conStrgDisChgPowerLimit[t=1:HRS_FUCR, p=1:STORG_UNITS], (fucrm_storgDiscPwr[p,t] + fucrm_storgResUp[p,t])<=DF_Storage.Power[p]*fucrm_storgDisc[p,t])
    # Down reserve provision limit
    @constraint(FUCRmodel, conStrgDownResrvMax[t=1:HRS_FUCR, p=1:STORG_UNITS], fucrm_storgResDn[p,t]<=DF_Storage.Power[p]*fucrm_storgChrg[p,t])
    # Up reserve provision limit`
    @constraint(FUCRmodel, conStrgUpResrvMax[t=1:HRS_FUCR, p=1:STORG_UNITS], fucrm_storgResUp[p,t]<=DF_Storage.Power[p]*fucrm_storgDisc[p,t])
    # State of charge at t
    @constraint(FUCRmodel, conStorgSOC[t=1:HRS_FUCR, p=1:STORG_UNITS], fucrm_storgSOC[p,t]==fucrm_storgSOC[p,t-1]-(fucrm_storgDiscPwr[p,t]/DF_Storage.TripEfficDown[p])+(fucrm_storgChrgPwr[p,t]*DF_Storage.TripEfficUp[p])-(fucrm_storgSOC[p,t]*DF_Storage.SelfDischarge[p]))
    # minimum energy limit
    @constraint(FUCRmodel, conMinEnrgStorgLimi[t=1:HRS_FUCR, p=1:STORG_UNITS], fucrm_storgSOC[p,t]-(fucrm_storgResUp[p,t]/DF_Storage.TripEfficDown[p])+(fucrm_storgResDn[p,t]/DF_Storage.TripEfficUp[p])>=0)
    # Maximum energy limit
    @constraint(FUCRmodel, conMaxEnrgStorgLimi[t=1:HRS_FUCR, p=1:STORG_UNITS], fucrm_storgSOC[p,t]-(fucrm_storgResUp[p,t]/DF_Storage.TripEfficDown[p])+(fucrm_storgResDn[p,t]/DF_Storage.TripEfficUp[p])<=(DF_Storage.Power[p]/DF_Storage.PowerToEnergRatio[p]))
    # Constraints representing transmission grid capacity constraints
    # DC Power Flow Calculation
    #@constraint(FUCRmodel, conDCPowerFlowPos[t=1:HRS_FUCR, n=1:N_ZONES, m=1:N_ZONES], fucrm_powerflow[n,m,t]-(TranS[n,m]*(fucrm_voltangle[n,t]-fucrm_voltangle[m,t])) ==0)
    @constraint(FUCRmodel, conDCPowerFlowNeg[t=1:HRS_FUCR, n=1:N_ZONES, m=1:N_ZONES], fucrm_powerflow[n,m,t]+fucrm_powerflow[m,n,t]==0)
    # Tranmission flow bounds (from n to m and from m to n)
    @constraint(FUCRmodel, conPosFlowLimit[t=1:HRS_FUCR, n=1:N_ZONES, m=1:N_ZONES], fucrm_powerflow[n,m,t]<=TranC[n,m])
    @constraint(FUCRmodel, conNegFlowLimit[t=1:HRS_FUCR, n=1:N_ZONES, m=1:N_ZONES], fucrm_powerflow[n,m,t]>=-TranC[n,m])
    # Voltage Angle bounds and reference point
    #@constraint(FUCRmodel, conVoltAnglUB[t=1:HRS_FUCR, n=1:N_ZONES], fucrm_voltangle[n,t]<=π)
    #@constraint(FUCRmodel, conVoltAnglLB[t=1:HRS_FUCR, n=1:N_ZONES], fucrm_voltangle[n,t]>=-π)
    #@constraint(FUCRmodel, conVoltAngRef[t=1:HRS_FUCR], fucrm_voltangle[1,t]==0)

    # Demand-side Constraints
    @constraint(FUCRmodel, conDemandLimit[t=1:HRS_FUCR, n=1:N_ZONES], fucrm_demand[n,t]+ fucrm_demand_curt[n,t] == fucr_prep_demand.wk_ahead[t,n])

    # Demand Curtailment and wind generation limits
    @constraint(FUCRmodel, conDemandCurtLimit[t=1:HRS_FUCR, n=1:N_ZONES], fucrm_demand_curt[n,t] <= LOAD_SHED_MAX);
    @constraint(FUCRmodel, conOverGenLimit[t=1:HRS_FUCR, n=1:N_ZONES], fucrm_overgen[n,t] <= OVERGEN_MAX);

    # System-wide Constraints
    #nodal balance constraint
    @constraint(FUCRmodel, conNodBalanc[t=1:HRS_FUCR, n=1:N_ZONES], sum((fucrm_genOut[g,t]*Map_Gens[g,n]) for g=1:GENS) +sum((fucrm_peakerOut[k,t]*Map_Peakers[k,n]) for k=1:PEAKERS)  + sum((fucrm_storgDiscPwr[p,t]*Map_Storage[p,n]) for p=1:STORG_UNITS) - sum((fucrm_storgChrgPwr[p,t]*Map_Storage[p,n]) for p=1:STORG_UNITS) +fucrm_solarG[n, t] +fucrm_windG[n, t] +fucrm_hydroG[n, t] - fucrm_demand[n,t] - fucrm_overgen[n,t]== sum(fucrm_powerflow[n,m,t] for m=1:M_Zones))

     #@constraint(FUCRmodel, conNodBalanc[t=1:HRS_FUCR], sum(fucrm_genOut[g,t] for g=1:GENS) + sum((fucrm_storgDiscPwr[p,t]) for p=1:STORG_UNITS) - sum((fucrm_storgChrgPwr[p,t]) for p=1:STORG_UNITS) +sum(fucrm_solarG[n, t] for n=1:N_ZONES) + sum(fucrm_windG[n, t] for n=1:N_ZONES)+ sum(fucrm_hydroG[n, t] for n=1:N_ZONES) - sum(fucr_prep_demand.wk_ahead[t,n] for n=1:N_ZONES) == 0)

    # @constraint(FUCRmodel, conNodBalanc[t=1:HRS_FUCR], sum((fucrm_genOut[g,t]) for g=1:GENS) + sum((fucrm_storgDiscPwr[p,t]) for p=1:STORG_UNITS) - sum((fucrm_storgChrgPwr[p,t]) for p=1:STORG_UNITS) +sum((fucrm_solarG[n, t]) for n=1:N_ZONES) +sum((fucrm_windG[n, t]) for n=1:N_ZONES) +sum((fucrm_hydroG[n, t]) for n=1:N_ZONES) - sum((fucr_prep_demand.wk_ahead[t,n]) for n=1:N_ZONES) == 0)
    # Minimum zonal up reserve requirement, if there are more than two zones, we should  define reserve regions for DEC and DEP
     #@constraint(FUCRmodel, conMinUpReserveReq[t=1:HRS_FUCR, n=1:N_ZONES], sum((fucrm_genResUp[g,t]*Map_Gens[g,n]) for g=1:GENS) + sum((fucrm_storgResUp[p,t]*Map_Storage[p,n]) for p=1:STORG_UNITS) >= Reserve_Req_Up[n] )
     #@constraint(FUCRmodel, conMinUpReserveReq[t=1:HRS_FUCR], sum((fucrm_genResUp[g,t]+fucrm_genResNonSpin[g,t]) for g=1:GENS) + sum((fucrm_storgResUp[p,t]) for p=1:STORG_UNITS) >= sum(Reserve_Req_Up[n] for n=1:N_ZONES))
     @constraint(FUCRmodel, conMinUpReserveReq[t=1:HRS_FUCR], sum((fucrm_genResUp[g,t]) for g=1:GENS) + sum((fucrm_peakerResUp[k,t]+fucrm_peakerResNonSpin[k,t]) for k=1:PEAKERS)+ sum((fucrm_storgResUp[p,t]) for p=1:STORG_UNITS) >= sum(Reserve_Req_Up[n] for n=1:N_ZONES))


    # Minimum down reserve requirement
    #    @constraint(FUCRmodel, conMinDnReserveReq[t=1:HRS_FUCR], sum(genResDn[g,t] for g=1:GENS) + sum(storgResDn[p,t] for p=1:STORG_UNITS) >= Reserve_Req_Dn[t] )

    t2_FUCRmodel = time_ns()
    time_FUCRmodel = (t2_FUCRmodel -t1_FUCRmodel)/1.0e9;
    @info "FUCRmodel for day: $day setup executed in (s): $time_FUCRmodel";

    open(".//outputs//csv//time_performance.csv", FILE_ACCESS_APPEND) do io
            writedlm(io, hcat("FUCRmodel", time_FUCRmodel, "day: $day",
                    "", "", "Model Setup"), ',')
    end; # closes file

    # solve the First WAUC model (FUCR)
    JuMP.optimize!(FUCRmodel)

    # Pricing general results in the terminal window
    println("Objective value: ", JuMP.objective_value(FUCRmodel))

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

    open(".//outputs//csv//time_performance.csv", FILE_ACCESS_APPEND) do io
            writedlm(io, hcat("FUCRmodel", JuMP.num_variables(FUCRmodel), "day: $day",
                    "", "", "Variables"), ',')
    end;

    @debug "FUCRmodel for day: $day optimized executed in (s):  $(solve_time(FUCRmodel))";

    open(".//outputs//csv//time_performance.csv", FILE_ACCESS_APPEND) do io
            writedlm(io, hcat("FUCRmodel", solve_time(FUCRmodel), "day: $day",
                    "", "", "Model Optimization"), ',')
    end; # closes file

    # Write the conventional generators' schedules in CSV file
    t1_write_FUCRmodel_results = time_ns()
    open(".//outputs//csv//FUCR_GenOutputs.csv", FILE_ACCESS_APPEND) do io
        for t in 1:HRS_FUCR, g=1:GENS
            writedlm(io, hcat(day, t+INIT_HR_FUCR, g, DF_Generators.UNIT_NAME[g],
                DF_Generators.MinPowerOut[g], DF_Generators.MaxPowerOut[g],
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
            writedlm(io, hcat(day, t+INIT_HR_FUCR, k, DF_Peakers.UNIT_NAME[k],
               DF_Peakers.MinPowerOut[k], DF_Peakers.MaxPowerOut[k],
               JuMP.value.(fucrm_peakerOut[k,t]), JuMP.value.(fucrm_peakerOnOff[k,t]),
               JuMP.value.(fucrm_peakerShutDown[k,t]), JuMP.value.(fucrm_peakerStartUp[k,t]),
               JuMP.value.(fucrm_peakerResUp[k,t]), JuMP.value.(fucrm_peakerResNonSpin[k,t]),
               JuMP.value.(fucrm_peakerResDn[k,t]) ), ',')
        end # ends the loop
    end; # closes file

    # Writing storage units' optimal schedules in CSV file
    open(".//outputs//csv//FUCR_StorageOutputs.csv", FILE_ACCESS_APPEND) do io
         for t in 1:HRS_FUCR, p=1:STORG_UNITS
            writedlm(io, hcat(day, t+INIT_HR_FUCR, p, DF_Storage.Name[p],
                DF_Storage.Power[p], DF_Storage.Power[p]/DF_Storage.PowerToEnergRatio[p],
                JuMP.value.(fucrm_storgChrg[p,t]), JuMP.value.(fucrm_storgDisc[p,t]),
                JuMP.value.(fucrm_storgIdle[p,t]), JuMP.value.(fucrm_storgChrgPwr[p,t]),
                JuMP.value.(fucrm_storgDiscPwr[p,t]), JuMP.value.(fucrm_storgSOC[p,t]),
                JuMP.value.(fucrm_storgResUp[p,t]), JuMP.value.(fucrm_storgResDn[p,t]) ), ',')
         end # ends the loop
    end; # closes file

    # Writing the transmission line flows in CSV file
    open(".//outputs//csv//FUCR_TranFlowOutputs.csv", FILE_ACCESS_APPEND) do io
        for t in 1:HRS_FUCR, n=1:N_ZONES, m=1:M_Zones
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
    @info "Write FUCRmodel results for day $day: $time_write_FUCRmodel_results executed in (s)";

    open(".//outputs//csv//time_performance.csv", FILE_ACCESS_APPEND) do io
            writedlm(io, hcat("FUCRmodel", time_write_FUCRmodel_results, "day: $day",
                    "", "", "Write CSV files"), ',')
    end; #closes file

    return values
end
