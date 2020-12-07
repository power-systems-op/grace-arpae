using JuMP, Gurobi

model = Model(Gurobi.Optimizer)
set_optimizer_attribute(model, "TimeLimit", 100)
set_optimizer_attribute(model, "Presolve", 0)

print("hello World")


@variable(model, x >= 0)
@constraint(model, c, 2x >= 1)
@objective(model, Min, x)


print("hello World!!")
