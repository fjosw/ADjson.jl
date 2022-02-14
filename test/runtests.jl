using ADerrors
using ADjson
using Test

# Check if file produced by pyerrors can be read.
tmp = load_json("./data/pyerrors_out")
display(tmp)
println()

# Check if file with a constant produced by pyerrors can be read.
tmp =load_json("./data/covobs_out")
display(tmp)
println()

# Check if file containing and array produced by pyerrors can be read.
tmp = load_json("./data/array_out")
display(tmp)
println()

# Check if file containing a correlator produced by pyerrors can be read.
tmp = load_json("./data/corr_out")
display(tmp)
println()

# Check if file containing a gapped observable produced by pyerrors can be read.
tmp = load_json("./data/gapped_out")
display(tmp)
println()

# Write file to disk, read it and check equality
test = uwreal(rand(4000), "Test ensemble")
dump_to_json(test, "test_file", "File containing an observable defined on 4000 random samples")
test2= load_json("test_file")
println()

iamzero = test - test2
uwerr(iamzero)
@test isapprox(iamzero.mean, 0.0; atol = 1e-14)
@test isapprox(iamzero.err, 0.0; atol = 1e-14)


# Write file containing constant to disk, read it and check equality
test *= uwreal([1.1, 0.2], "Constant")
dump_to_json(test, "constant_file", "File containing Monte carlo data and a constant with error")
test2= load_json("constant_file")
println()

iamzero = test - test2
uwerr(iamzero)
@test isapprox(iamzero.mean, 0.0; atol = 1e-14)
@test isapprox(iamzero.err, 0.0; atol = 1e-14)

# Test exceptions
gapped_observable = uwreal(Vector{Float64}(collect(1:2:20)), "go", collect(1:2:20), 20)
@test_throws ErrorException dump_to_json(gapped_observable, "this_should_not_work")

@test_throws ErrorException load_json("this_file_does_not_exist")
