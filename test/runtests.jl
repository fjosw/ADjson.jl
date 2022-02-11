using ADerrors
using ADjson
using Test

# Check if file produced by pyerrors can be read.
load_json("./data/pyerrors_out")

# Write file to disk, read it and check equality
test = uwreal(rand(100), "Test ensemble")
dump_to_json(test, "test_file", "my description")
test2= load_json("test_file")

iamzero = test - test2
uwerr(iamzero)
@test isapprox(iamzero.mean, 0.0; atol = 1e-14)
@test isapprox(iamzero.err, 0.0; atol = 1e-14)
