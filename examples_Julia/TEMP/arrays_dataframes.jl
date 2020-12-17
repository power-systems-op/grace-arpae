using DataFrames

#Arrays and Dataframe example


dfGenPath = "C://Users//rapiduser//github//GRACE-ARPAE//examples_Julia//UC_DukeEnergy_Sample//inputs//data_generators.csv"
dfGenerator = CSV.read(dfGenPath, DataFrame)

myArr = [0.0, 0.0, 0.0, -0.0, -0.0, -0.0, 0.0, 0.0, 0.0, 1.0, 1.0, -0.0, -0.0, 1.0]
arrSalary = [3000.50,450_000.70,80_000.1,99_000.9,77_777.85]

m = Array{Bool}(undef, 14)

df = DataFrame(Name = ["Jon","Bill","Maria","Julia","Mark"],
               Age = [22,43,81,52,27],
               Salary = [3000.50,45000.70,60000.1,50000.9,55000.85]
               )

# These commands work
#df = DataFrame(Age = round.(Int, rand(5)), Salary = arrSalary )
#df.Salary = round.(arrSalary; digits =3)

df.Salary = arrSalary
#replace!(Salary,)

m = myArr
println("ArraySize")
println(size(m))
println(size(myArr))
println(df)


# MODIFYING DATAFRAME
println("dfGenerator.Uini")
println(dfGenerator.Uini)

arrayUini = [1, 1, 1, 0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 1, 0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 0, 0, 0, 1]
dfGenerator.Uini = arrayUini

println("dfGenerator.Uini (MODIFIED)")
println(dfGenerator.Uini)
#@. df.Salary = arrSalary
