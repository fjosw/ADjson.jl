[![Run tests](https://github.com/fjosw/ADjson.jl/actions/workflows/test.yml/badge.svg)](https://github.com/fjosw/ADjson.jl/actions/workflows/test.yml) [![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
# ADjson.jl
ADjson.jl provides [ADerrors.jl](https://gitlab.ift.uam-csic.es/alberto/aderrors.jl) with input and output routines for the `json.gz` file format used within [pyerrors](https://github.com/fjosw/pyerrors).
The specifications of the `json.gz` format can be found in [the documentation of pyerrors](https://fjosw.github.io/pyerrors/pyerrors.html#export-data).

### Installation
The package depends on [ADerrors.jl](https://gitlab.ift.uam-csic.es/alberto/aderrors.jl) which depends on [bdio.jl](https://gitlab.ift.uam-csic.es/alberto/bdio.jl).
All three packages are not registered in the official Julia registry. They can be installed by running the following commands:
```
julia -e 'using Pkg; Pkg.add(url="https://gitlab.ift.uam-csic.es/alberto/bdio.jl")'
julia -e 'using Pkg; Pkg.add(url="https://gitlab.ift.uam-csic.es/alberto/ADerrors.jl")'
julia -e 'using Pkg; Pkg.add(url="https://github.com/fjosw/ADjson.jl")'
```

### Features
At the moment ADjson.jl supports only a subset of the full `json.gz`-pyerrors specification.

| | `Obs` | `List` | `Array` | `Corr` |
| :---: | :---: | :---: | :---: | :---: |
| read | :heavy_check_mark: | :heavy_check_mark: | :heavy_check_mark: | :heavy_multiplication_x: |
| write | :heavy_check_mark: | :heavy_multiplication_x: | :heavy_multiplication_x: | :heavy_multiplication_x: |

#### Notes
- ADerrors.jl always assumes that replica are labeled as `r0`, `r1`, etc. Custom replica names in `json.gz` files get lost in the conversion.
- ADerrors.jl does not support array valued constants with cross correlations. If such a constant is found in a `json.gz` file ADjson.jl throws an error.
- Reading files with gaps in the Monte Carlo history is not yet supported as not all cases supported by pyerrors can be correctly initialized in ADerrors.jl. For now ADjson.jl throws an error in case such an observable is encountered.

### Examples
A single observable can be written to a file as described in the following example
```Julia
using ADerrors
using ADjson

# Create a test observable
test_obs = uwreal(rand(100), "Test ensemble")

# Write the observable to a file with a description
dump_to_json(test_obs, "test_file", "This file contains a test observable.")

# Read the observable from disk
check = load_json("test_file")

# Check that the observable was corretly reconstructed
iamzero = test - check
uwerr(iamzero)
println(iamzero)
>>> 0.0 +/- 0.0
```

ADjson.jl can also directly write a vector of `uwreal` objects to disc
```Julia
test_obs = uwreal(rand(100), "Test ensemble") + uwreal(rand(20), "Second shorter test ensemble")
test_obs *= uwreal([1.02, 0.01], "Renormalization")

dump_to_json([test_obs, test_obs, test_obs],
             "vector_file",
             "File contains three times a test observable which is defined on two ensembles and a constant.")
```
