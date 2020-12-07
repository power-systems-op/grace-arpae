using JuMP, CPLEX

#Preparing optimization model
m = Model(CPLEX.Optimizer)
model = Model(CPLEX.Optimizer)
set_optimizer_attribute(m, "CPX_PARAM_EPINT", 1e-8)


c = [ 1; 2; 5]
A = [-1  1  3;
      1  3 -7]
b = [-5; 10]

println("Size of c: ", size(c))
println("Size of A: ", size(A))
println("Size of b: ", size(b))


@variable(m, x[1:3] >= 0)
@objective(m, Max, sum( c[i]*x[i] for i=1:3) )

@constraint(m, constraint[j=1:2], sum( A[j,i]*x[i] for i=1:3 ) <= b[j] )

#@constraint(m, constraint1, sum( A[1,i]*x[i] for i=1:3) <= b[1] )
#@constraint(m, constraint2, sum( A[2,i]*x[i] for i=1:3) <= b[2] )

@constraint(m, bound, x[1] <= 10)

optimize!(m)

print(m)

println("Optimal Solutions:")
for i=1:3
  println("x[$i] = ", JuMP.value(x[i]))
end

println("Dual Variables:")
for j=1:2
  println("dual[$j] = ", JuMP.dual(constraint[j]))
end

println("Size of x: ", size(x))
