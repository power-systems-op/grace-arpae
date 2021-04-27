# Steps to install Python in Atom
# https://python.plainenglish.io/6-simple-steps-for-a-python-setup-in-atom-ca3100711f62
using PyCall
math = pyimport("math")
math.sin(math.pi / 4)

#Format: YYY-MM-DD
run(`python UC_BAU_postprocess.py '2019-01-01' '2019-01-02'`)
