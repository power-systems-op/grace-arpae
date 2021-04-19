#Reference: https://docs.julialang.org/en/v1/manual/performance-tips/index.html
#A global variable might have its value, and therefore its type, change at any point. This makes it difficult for the compiler to optimize code using global variables.

global x = rand(10_000)

function sum_global_type()
    s = 0.0
    for i in x::Vector{Float64}
        s += i
    end
    return s
end


function sum_global()
   s = 0.0
   for i in x
	   s += i
   end
   return s
end;

@time sum_global_type()
@time sum_global()

#=
function pos(x)
	if x < 0
		return 0
	else
		return x
	end
end

pos(-1)
pos(2.5)

typeof(pos(-1))
typeof(pos(2.5))
=#
