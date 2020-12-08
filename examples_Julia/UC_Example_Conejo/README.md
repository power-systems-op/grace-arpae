## Unit Commitment Example

This Julia Script implements a simple Unit Commitment problem described in the book Power System Operations by Conejo, A. and Baringo, L., Springer, 2018

## Description
We solve below a UC problem for a 3 h planning horizon. Three thermal generating units are used to supply demands of 160MW, 500MW, and 400MWin time periods 1, 2, and 3, respectively. Required reserves in these time periods are, respectively, 16MW, 50MW, and 40MW.

The UC is formulated based on the information of the following table

| Generating Unit #            	| 1     	| 2     	| 3     	|
|------------------------------	|-------	|-------	|-------	|
| Min. Power Output [MW]       	| 50    	| 80    	| 40    	|
| Capacity [MW]                	| 350   	| 200   	| 140   	|
| Ramping-down limit (MWh)     	| 300   	| 150   	| 100   	|
| Shutdown ramping limit [MWh] 	| 300   	| 150   	| 100   	|
| Ramping-up limit [MWh]       	| 200   	| 100   	| 100   	|
| Start-up ramping limit [MWh] 	| 200   	| 100   	| 100   	|
| Fixed cost [$]               	| 5     	| 7     	| 6     	|
| Start-up cost [$]            	| 20    	| 18    	| 5     	|
| Shut-down cost [$]           	| 0.5   	| 0.3   	| 1.0   	|
| Variable cost [$/MWh]        	| 0.100 	| 0.125 	| 0.150 	|


Generating units 1 and 2 are off-line prior to the first time period of the considered planning horizon, while generating unit 3 is online and producing 100MW.

## Expected Result


### Commitment Status of Generating Units


### Power Outputs of generating units
