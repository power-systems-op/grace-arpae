using Dates
using DelimitedFiles
using Statistics
using TimerOutputs

const to = TimerOutput();

# Logging file
io_log = open(
    string(
        ".\\log\\perform_results_",
        Dates.format(now(), "yyyy-mm-dd_HH-MM-SS"),
        ".txt",
    ),
    "w",
)


function randmsq_timed(rows::Int64, cols::Int64)
 @timeit to "randmsq" begin
    x = @timeit to "rand" rand(rows, cols)
    y = @timeit to "mean" mean(x.^2, dims=1)
    return y
    end
end


for i in 0:9
    n_rows = 5_000 + 5_000*i
    n_cols = 5_000 + 5_000*i
    size = n_rows*n_cols

    write(io_log, "Size:\t$size, Rows:\t$n_rows, Columns:\t$n_cols\n")
    randmsq_timed(n_rows, n_cols);
    print_timer(to)
    write(io_log, "$to\n\n\n")

end

close(io_log);
