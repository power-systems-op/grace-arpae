#!/usr/bin/python
import sys
import compute_hr_gen_input as comp
import os

def main(argv):
   comp.calculating_gen_period(argv[0], argv[1])

if __name__ == "__main__":
   main(sys.argv[1:])
   # Get the current working directory
   cwd = os.getcwd()

   # Print the current working directory
   print("Current working directory: {0}".format(cwd))
