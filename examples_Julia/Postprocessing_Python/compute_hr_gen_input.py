#!/usr/bin/env python
# coding: utf-8
# # Computing Hourly Generation - Duke Energy
#
# 4/27/2021 \
# by [Mauricio Hernandez](mmh54@duke.edu)

# Goal:
# - Calculate the hourly power generation per unit and technology during 2019

import csv
import datetime as dt
import numpy as np
import pandas as pd
import os.path
import sys
from datetime import timedelta
from os import path

def convert_string_to_date(date_string, datetime_format):
    date_obj = dt.datetime.strptime(date_string, datetime_format)
    return date_obj

# Calculating annual generation by unit and by plant. Getting aggregated hourly generation.
def create_data_files_actuals(df_unit_sch_actuals, date_list):
    # Creating pivot table to get total generation by units name
    df_unit_sch_actuals_pivot = df_unit_sch_actuals.groupby(['UNIT_ID', 'PORTFOLIO_NAME']).sum()
    df_unit_sch_byplant = df_unit_sch_actuals.groupby(['UNIT_NAME', 'PORTFOLIO_NAME']).sum()
    df_unit_sch_byhour = df_unit_sch_actuals.groupby(['BEGIN_DATE', 'PORTFOLIO_NAME']).sum()
    df_unit_sch_bytype = df_unit_sch_actuals.groupby(['UNIT_ID','PORTFOLIO_NAME','UNIT_TYPE']).sum()

    df_unit_sch_byhour.sort_values(by=['BEGIN_DATE'], inplace=True)
    df_unit_sch_actuals_pivot.to_csv('./outputs/annual_generation_by_unit.csv', sep=',', encoding='utf-8')
    df_unit_sch_byplant.to_csv('./outputs/annual_generation_by_plant.csv', sep=',', encoding='utf-8')
    df_unit_sch_byhour.to_csv('./outputs/aggregated_hourly_generation.csv', sep=',', encoding='utf-8')
    df_unit_sch_bytype.to_csv('./outputs/aggregated_unit_type.csv', sep=',', encoding='utf-8')

    # Create results dataframe to store hourly generation by power unit
    df_unit_sch_actuals_pivot = df_unit_sch_actuals.groupby(['UNIT_ID']).sum()
    df_unit_time = pd.DataFrame(index=df_unit_sch_actuals_pivot.index, columns=date_list)
    return df_unit_time


def calculating_gen_period(ini_date, end_date):
    df_unit_time = pd.read_csv('./outputs/hourly_generation_by_unit.csv', index_col=0)

    df_lookup = pd.read_csv('./inputs/UnitLookupAndDetailTable_(DEC-DEP).csv')
    df_lookup['UNIT_ID'] = df_lookup.UNIT_NAME + '_'+ df_lookup.CC_KEY.apply(str)

    ini_date = ini_date + ' 00:00:00'
    end_date = end_date + ' 00:00:00'

    df_unit_time_period = df_unit_time.loc[:, ini_date:end_date].sum(axis=1)

    df_unit_time_period = df_unit_time_period.to_frame()
    df_unit_time_period = df_unit_time_period.rename(columns={0: 'MW'})

    df_lookup = df_lookup.set_index('UNIT_ID')
    df_lookup = df_lookup.loc[:, ['UNIT_NAME', 'UNIT_TYPE', 'PORTFOLIO_NAME']]

    #Merging dataframes
    df_result_period = pd.concat([df_lookup, df_unit_time_period], axis = 1, join="inner")

    #Store results
    df_result_period.to_csv('./outputs/df_gen_'+ ini_date.split(' ')[0] + '_to_' + end_date.split(' ')[0] + '.csv', sep=',', encoding='utf-8')
    df_result_period.groupby(['UNIT_TYPE']).sum().to_csv('./outputs/df_gen_bytype_'+ ini_date.split(' ')[0] + '_to_' + end_date.split(' ')[0] + '.csv', sep=',', encoding='utf-8')

def reshape_unit_sch_file():
   df_unit_schedule = pd.read_csv('./inputs/UnitSchedule_(DEC-DEP 2019).CSV')
   df_unit_schedule['UNIT_ID'] = df_unit_schedule.UNIT_NAME + '_'+ df_unit_schedule.CC_KEY.apply(str)

   datetime_format = '%m/%d/%Y %I:%M:%S %p'
   first_time = convert_string_to_date('1/1/2019 12:00:00 AM', datetime_format )
   last_time = convert_string_to_date('1/1/2020 12:00:00 AM', datetime_format)

   #Create list with dates from First_day to last_day
   date_list = [first_time + dt.timedelta(hours=x) for x in range(0, ((last_time-first_time).days )*24 )]
   date_str_list = []
   for date in date_list:
       date_str_list.append(date.strftime(datetime_format))

   # creating a copy of the dataframe to store only actuals
   df_unit_sch_actuals = df_unit_schedule.copy()
   #Only actual values
   df_unit_sch_actuals = df_unit_sch_actuals[df_unit_sch_actuals.EDITION_NAME == 'Actual']
   #Only these attributes are needed to get generation:
   # PORTFOLIO_NAME	 UNIT_ID UNIT_NAME	CC_KEY	UNIT_TYPE	BEGIN_DATE	MW
   df_unit_sch_actuals = df_unit_sch_actuals.loc[:, ['UNIT_ID', 'UNIT_NAME', 'PORTFOLIO_NAME', 'UNIT_TYPE', 'BEGIN_DATE', 'MW']]

   df_unit_time = create_data_files_actuals(df_unit_sch_actuals, date_list)

   df_unit = df_unit_sch_actuals.loc[:, ['UNIT_ID', 'BEGIN_DATE', 'MW']]

   # Store generation values in matrix (dataframe) where each rows represents a power unit and each column represents time
   old_index = ''
   generation_list_index = 0
   generation_list = [None] * 24 * 365

   for index, row in df_unit.iterrows():
       current_index = row['UNIT_ID']

       time = row['BEGIN_DATE']
       generation = row['MW']
       #print("Index: ", index, time, generation)

       if index == 0:
           old_index = current_index
           #print("Old index: ", current_index)

       if (old_index != current_index):
           #print("Current index: ", current_index)
           generation_list_index = 0 # restart index
           df_unit_time.loc[old_index] = generation_list

           old_index = current_index
           generation_list = [None] *24*365

       generation_list[generation_list_index] = generation
       generation_list_index = generation_list_index + 1

   #Save last value
   if generation_list_index != 0 :
       df_unit_time.loc[current_index] = generation_list

   #storing hourly generation data into CSV file
   df_unit_time.to_csv('./outputs/hourly_generation_by_unit.csv', sep=',', encoding='utf-8')

if __name__ == "__main__":
    cwd = os.getcwd()
    # Print the current working directory
    print("Current working directory: {0}".format(cwd))
    print(cwd + '\outputs\hourly_generation_by_unit.csv')
    if path.exists(cwd + '.\TEMP\outputs\hourly_generation_by_unit.csv'):
        #Format: YYY-MM-DD
        calculating_gen_period('2019-01-01', '2019-02-01')
    else:
        reshape_unit_sch_file()
