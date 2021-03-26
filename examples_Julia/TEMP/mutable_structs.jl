#Reference:
#https://syl1.gitbook.io/julia-language-a-concise-tutorial/language-core/custom-types

mutable struct Person
  myname::String
  age::Int64
end

struct Shoes
   shoesType::String
   colour::String
end

mutable struct Student
   s::Person
   school::String
   shoes::Shoes
   grades::Array{Float64,1}
end

function printMyActivity(self::Student)
   println("$(self.s.myname) studies at $(self.school) school")
end

struct Employee
   s::Person
   annualIncome::Float64
   company::String
   shoes::Shoes
   monthlyIncomes::Array{Float64,1}
end

function printMyActivity(self::Employee)
  println("I work at $(self.company) company")
end

gymShoes = Shoes("gym","white")
proShoes = Shoes("classical","brown")

Marc = Student(Person("Marc",15),"Nicholas School",gymShoes, [100, 90])
MrBrown = Employee(Person("Brown",45),1200.0,"ABC Corporation Inc.", proShoes, [250, 180])

John_person = Person("John",55)

John = Student(John_person,"Divinity School", proShoes, [80, 50, 95])

printMyActivity(Marc)
printMyActivity(MrBrown)
printMyActivity(John)

##
#Returning a Struct
function createStudent(name::String, age::Int64, school::String, shoes::Shoes, grades::Array{Float64,1})
   myStudent = Student(Person(name,age), school, gymShoes, grades)
   return myStudent
end

Mary = createStudent("Mary", 30, "Yale", gymShoes, [98.5, 85, 100])
printMyActivity(Mary)
print("Mary's grades are: $(Mary.grades)\n")

#Adding grades
push!(Mary.grades, 97.5)
print("Mary's grades are: $(Mary.grades)\n")

#Adding grades
push!(Mary.grades, 85.5, 88.8)
print("Mary's grades are: $(Mary.grades)\n")

Mary.school = "Nicholas School"

#Trying to modify a nonmutable struct
print("MrBrown's mobthly incomes are: $(MrBrown.monthlyIncomes)\n")
push!(MrBrown.monthlyIncomes, 850)
print("MrBrown's mobthly incomes are: $(MrBrown.monthlyIncomes)\n")

MrBrown.company = "GE"
FUCR.genoffon

C:\Users\rapiduser\Ali_Julia
