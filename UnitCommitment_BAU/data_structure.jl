"""
Generators struct

"""

mutable struct SysGenerator
	unit_id::Array{String}
	status_init::Array{Int64,1}
	power_init::Array{Float64,1}
	uptime_init::Array{Int64,1}
	downtime_init::Array{Int64,1}
	hr_b1::Array{Float64,1}
	hr_b2::Array{Float64,1}
	hr_b3::Array{Float64,1}
	hr_b4::Array{Float64,1}
	hr_b5::Array{Float64,1}
	hr_b6::Array{Float64,1}
	hr_b7::Array{Float64,1}
	hr_b1_qty::Array{Float64,1}
	hr_b2_qty::Array{Float64,1}
	hr_b3_qty::Array{Float64,1}
	hr_b4_qty::Array{Float64,1}
	hr_b5_qty::Array{Float64,1}
	hr_b6_qty::Array{Float64,1}
	hr_b7_qty::Array{Float64,1}
	noload_hr::Array{Float64,1}
	shutdown_cost::Array{Int64,1}
	hot_startup_fixcost::Array{Float64,1}
	hot_startup_hr::Array{Float64,1}
	down_time_min::Array{Int64,1}
	up_time_min::Array{Int64,1}
	power_maxout::Array{Int64,1}
	power_minout::Array{Int64,1}
	spin_res_limit::Array{Int64,1}
	ramp_up_limit::Array{Int64,1}
	ramp_shutdn_limit::Array{Int64,1}
	isnuclear::Array{Int64,1}
	iscogen::Array{Int64,1}
	isNG_fired::Array{Int64,1}
end

mutable struct Storage
	name::Array{String}
	power::Array{Int64,1}
	pwr_ratio_min::Array{Float64,1}
	selfdischarge::Array{Int64,1}
	trip_effic_up::Array{Float64,1}
	trip_effic_dn::Array{Float64,1}
	pwr_toenergy_ratio::Array{Float64,1}
	soc_init::Array{Float64,1}
end

mutable struct UnitsResults
	onoff_init::Array{Int64,1}
	power_out::Array{Float64,1}
	uptime_init::Array{Float64,1}
	dntime_init::Array{Float64,1}
end

mutable struct UC_Results
	gens::UnitsResults
	peakers::UnitsResults
	soc_init::Array{Float64,1}
end

"""
Demand Data Pre-Processing for FUCR and SUCR models
wk_ahead: week-ahead demand data for the first UC run at 6 am
solarg_wa: week-ahead SolarG data for the first UC run at 6 am
windg_wa: week-ahead WindG data for the first UC run at 6 am
hydrog_wa: week-ahead HydroG data for the first UC run at 6 am
nuclearg_wa: week-ahead WindG data for the first UC run at 6 am
cogeng_wa: week-ahead HydroG data for the first UC run at 6 am
"""
mutable struct DemandPreprocGens
	wk_ahead::Array{Int64,2}
	solar_wa::Array{Int64,2}
	wind_wa::Array{Int64,2}
	hydro_wa::Array{Int64,2}
	nuclear_wa::Array{Int64,2}
	cogen_wa::Array{Int64,2}
end
#= STRUCT DemandPreprocGens, Also for SUCR model
wk_ahead::Array{Float64,1} 		<- FUCR_WA_Demand
solar_wa::Array{Float64,1}		<- FUCR_WA_SolarG
wind_wa::Array{Float64,1}      <- FUCR_WA_WindG
hydro_wa::Array{Float64,1}     <- FUCR_WA_HydroG
nuclear_wa::Array{Float64,1}   <- FUCR_WA_NuclearG
cogen_wa::Array{Float64,1}     <- FUCR_WA_CogenG
=#

#=
struct  			<- DF_Generators
unit_id				<-UNIT_ID::Array{String}
status_init 		<- StatusInit
power_init 			<-	PowerInit
uptime_init 		<-	UpTimeInit
downtime_init		<-	DownTimeInit
hr_b1 				<- IHRC_B1_HR
...
hr_b7 				<- IHRC_B8_HR
hr_b1_qty 			<- IHRC_B1_Q
...
hr_b7_qty 			<- IHRC_B8_Q
noload_hr 			<- NoLoadHR::Array{Float64,1}
shutdown_cost 		<- ShutdownCost::Array{Int64,1}
hot_startup_fixcost <- HotStartU_FixedCost::Array{Float64,1}
hot_startup_hr 		<- HotStartU_HeatRate::Array{Float64,1}
down_time_min		<- MinDownTime::Array{Int64,1}
up_time_min			<- MinUpTime::Array{Int64,1}
power_maxout		<- MaxPowerOut::Array{Int64,1}
power_minout		<- MinPowerOut::Array{Int64,1}
spin_res_limit		<- SpinningRes_Limit::Array{Int64,1}
ramp_up_limit		<- RampUpLimit::Array{Int64,1}
ramp_shutdn_limit	<- RampShutDownLimit::Array{Int64,1}
isnuclear 			<- Nuclear::Array{Int64,1}
iscogen				<- Cogen::Array{Int64,1}
isNG_fired			<- NaturalGasFired::Array{Int64,1}

------------
Storage, data_storage.csv
name::Array{String}                  <- DF_Storage.Name::Array{String}
power::Array{Int64,1}                <- DF_Storage.Power::Array{Int64,1}
pwr_ratio_min::Array{Float64,1}      <- DF_Storage.MinPwrRatio::Array{Float64,1}
selfdischarge::Array{Int64,1}        <- DF_Storage.SelfDischarge::Array{Int64,1}
trip_effic_up::Array{Float64,1}      <- DF_Storage.TripEfficUp::Array{Float64,1}
trip_effic_dn::Array{Float64,1}      <- DF_Storage.TripEfficDown::Array{Float64,1}
pwr_toenergy_ratio::Array{Float64,1} <- DF_Storage.PowerToEnergRatio::Array{Float64,1}
soc_init::Array{Float64,1}           <- DF_Storage.SOCInit::Array{Float64,1}
----------

struct UC_Results
onoff_init::Array{Int64,1} 			<- FUCR_Init_genOnOff
power_out::Array{Float64,1}         <- FUCR_Init_genOut
uptime_init::Array{Float64,1}       <- FUCR_Init_UpTime
downtime_init::Array{Float64,1}     <- FUCR_Init_DownTime
soc_init::Array{Float64,1}          <- FUCR_Init_storgSOC


FUCR_Init_UpTime_Peaker
=#

#=
peakers = SysGenerator(DF_Generators.UNIT_ID,
            DF_Peakers.StatusInit,
            DF_Peakers.PowerInit,
            DF_Peakers.UpTimeInit,
            DF_Peakers.DownTimeInit,
            DF_Peakers.IHRC_B1_HR,
            DF_Peakers.IHRC_B2_HR,
            DF_Peakers.IHRC_B3_HR,
            DF_Peakers.IHRC_B4_HR,
            DF_Peakers.IHRC_B5_HR,
            DF_Peakers.IHRC_B6_HR,
            DF_Peakers.IHRC_B7_HR,
            DF_Peakers.IHRC_B1_Q,
            DF_Peakers.IHRC_B2_Q,
            DF_Peakers.IHRC_B3_Q,
            DF_Peakers.IHRC_B4_Q,
            DF_Peakers.IHRC_B5_Q,
            DF_Peakers.IHRC_B6_Q,
            DF_Peakers.IHRC_B7_Q,
            DF_Peakers.NoLoadHR,
            DF_Peakers.ShutdownCost,
            DF_Peakers.HotStartU_FixedCost,
            DF_Peakers.HotStartU_HeatRate ,
            DF_Peakers.MinDownTime,
            DF_Peakers.MinUpTime,
            DF_Peakers.MaxPowerOut,
            DF_Peakers.MinPowerOut,
            DF_Peakers.SpinningRes_Limit,
            DF_Peakers.RampUpLimit,
            DF_Peakers.RampShutDownLimit,
            DF_Peakers.Nuclear,
            DF_Peakers.Cogen,
            DF_Peakers.NaturalGasFired,
)

storage = Storage(
	DF_Storage.Name,
	DF_Storage.Power,
	DF_Storage.MinPwrRatio,
	DF_Storage.SelfDischarge,
	DF_Storage.TripEfficUp,
	DF_Storage.TripEfficDown,
	DF_Storage.PowerToEnergRatio,
	DF_Storage.SOCInit
)

=#
