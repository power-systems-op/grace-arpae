## Unit Commitment Example

This Julia Script implements a simple Unit Commitment problem described in the book Power System Operations by Conejo, A. and Baringo, L., Springer, 2018

## Description
We solve below a UC problem for a 3 h planning horizon. Three thermal generating units are used to supply demands of 160MW, 500MW, and 400MWin time periods 1, 2, and 3, respectively. Required reserves in these time periods are, respectively,
16MW, 50MW, and 40MW.



<img src="https://render.githubusercontent.com/render/math?math=e^{i \pi} = x -1">
<br>
<img src="https://render.githubusercontent.com/render/math?math=e^{i %2B\pi} =x%2B1">
<br>
<img src="https://render.githubusercontent.com/render/math?math=\large e^{i\pi} = -1">

| Generating Unit #        	| 1   	| 2   	| 3   	|
|--------------------------	|-----	|-----	|-----	|
| Min. Power Output [MW]   	| 50  	| 80  	| 40  	|
| Capacity [MW]            	| 350 	| 200 	| 140 	|
| Ramping-down limit (MWh) 	| 300 	| 150 	| 100 	|

## Expected Result
