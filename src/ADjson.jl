module ADjson

using GZip
using JSON
using TensorCast
using Dates
using TimeZones
using ADerrors


"""
    load_json(fname::String)

Load data from a json.gz file

# Currently supported datatypes
- `Obs`
- `List`

# Arguments
- `fname::string`: File name. Suffix '.json.gz' is automatically added if not specified explicitly.

# Notes
- ADerrors always assumes that replica are labeled as r0, r1, etc. Custom replica names get lost in the conversion.
- Irregular Monte Carlo chains are currently not supported as not all cases pyerrors can output can be safely converted to ADerrors
"""
function load_json(fname::String)

    if !endswith(fname, ".json.gz")
        fname *= ".json.gz"
    end

    if !(isfile(fname) || islink(fname))
        error("File '" * fname * "' does not exist.")
    end

    df = GZip.open(fname, "r") do io
        JSON.parse(io)
    end

    println("Data has been written using ", df["program"])
    println("Format version ", df["version"])
    println("Written by ", df["who"], " on ", df["date"], " on host ", df["host"])
    if haskey(df, "description")
        println("\nDescription: ", df["description"])
    end

    res_list = Vector{Any}()

    for entry in df["obsdata"]
        if !(entry["type"] in ["Obs", "List", "Array", "Corr"])
            error("Type '" * entry["type"] * "' is not implemented." )
        end

        res = Vector{uwreal}()
        out_length = prod([parse(Int, o) for o in split(entry["layout"], ", ")])

        if haskey(entry, "data")
            for element in entry["data"]
                conc_deltas = [Float64[] for b in 1:out_length]
                int_cnfg_numbers = Int[]
                rep_lengths = Int[]

                for rep in element["replica"]
                    my_arr = rep["deltas"]
                    @cast deltas[i][j] := my_arr[j][i]
                    cnfg_numbers = convert(Array{Int,1}, deltas[1])

                    if length(element["replica"]) > 1
                        for ch in 1:length(cnfg_numbers)
                            if ch != cnfg_numbers[ch]
                                error("Irregular Monte Carlo chains for multiple replica cannot be safely read into ADerrors.")
                            end
                        end
                    end

                    append!(int_cnfg_numbers, cnfg_numbers)
                    append!(rep_lengths, length(cnfg_numbers))
                    for i in 1:out_length
                        append!(conc_deltas[i], Vector{Float64}(deltas[i + 1]))
                    end
                end

                if length(res) == 0
                    for i in 1:out_length
                        if length(element["replica"]) > 1
                            push!(res, uwreal(Vector{Float64}(conc_deltas[i]), element["id"], rep_lengths))
                        else
                            push!(res, uwreal(Vector{Float64}(conc_deltas[i]), element["id"], int_cnfg_numbers, int_cnfg_numbers[end]))
                        end
                    end
                else
                    for i in 1:out_length
                        if length(element["replica"]) > 1
                            res[i] += uwreal(Vector{Float64}(conc_deltas[i]), element["id"], rep_lengths)
                        else
                            res[i] += uwreal(Vector{Float64}(conc_deltas[i]), element["id"], int_cnfg_numbers, sum(rep_lengths))
                        end
                    end
                end
            end
        end

        if haskey(entry, "cdata")
            for element in entry["cdata"]
                if element["layout"] != "1, 1"
                   error("ADerror does not support non-scalar constants at the moment.")
                end

                if length(res) == 0
                    for i in 1:out_length
                        push!(res, uwreal([0.0, sqrt(element["grad"][1][i] * element["cov"][1] * element["grad"][1][i])], element["id"]))
                    end
                else
                    for i in 1:out_length
                        res[i] += uwreal([0.0, sqrt(element["grad"][1][i] * element["cov"][1] * element["grad"][1][i])], element["id"])
                    end
                end
            end
        end

        for i in 1:out_length
            res[i] += entry["value"][i]
        end

        if length(res) == 1
            push!(res_list, res[1])
        else
            push!(res_list, reshape(res, Tuple(Int(x) for x in [parse(Int, o) for o in split(entry["layout"], ", ")])))
        end
    end

    if length(res_list) == 1
        return res_list[1]
    else
        return res_list
    end
end


"""
    dump_to_json(p, fname::String, description="", indent=1)

Dump data to a json.gz file

# Currently supported datatypes
- `Obs`

# Arguments
- `p::uwreal` or `p::Vector{uwreal}`: Data to be written to the file
- `fname::String`: File name. Suffix '.json.gz' is automatically added if not specified explicitly.
- `description::String`: Optional description to be added to the file
- `indent::Int`: Indent of the json structure. Use `ident=nothing` for smallest file size but less human readability.
"""
function dump_to_json(data, fname::String, description="", indent=1)
    jsonstring = Dict{String, Any}()
    jsonstring["program"] = "ADjson 1.0"
    jsonstring["who"] = ENV["USER"]
    jsonstring["host"] = gethostname() * ", " * Sys.MACHINE
    jsonstring["date"] = Dates.format(now(localzone()), "Y-mm-dd HH:MM:SS zzzz")
    jsonstring["version"] = "1.0"
    jsonstring["obsdata"] = []
    if !isempty(description)
        jsonstring["description"] = description
    end

    ws = ADerrors.wsg

    vec_data = Vector{uwreal}()
    if data isa uwreal
        push!(vec_data, data)
    elseif data isa Vector{uwreal}
        append!(vec_data, data)
    else
        error("Unkown data type.")
    end

    for (index, p) in enumerate(vec_data)
        push!(jsonstring["obsdata"], Dict{String, Any}())
        jsonstring["obsdata"][index]["layout"] = "1"
        jsonstring["obsdata"][index]["type"] = "Obs"
        jsonstring["obsdata"][index]["value"] = [p.mean]

        i_data = 0
        i_cdata = 0
        for i in 1:convert(Int32, ADerrors.unique_ids!(p, ws))
            # Collect and rename replica names
            my_rep_names = Vector{String}()
            for el in ADerrors.get_repnames_from_id(p.ids[i], ws)
                loc = findlast("_", el)
                push!(my_rep_names, el[1:Vector{Int}(loc)[1] - 1] * "|" * el[Vector{Int}(loc)[1] + 1:end])
            end

            # Get deltas
            dt = zeros(Float64, ws.fluc[ws.map_ids[p.ids[i]]].nd)
            for j in 1:length(p.prop)
                if (p.prop[j] && (ws.map_nob[j] == p.ids[i]))
                    dt .= dt .+ p.der[j] .* ws.fluc[j].delta
                end
            end

            idc = convert(Vector{Int32}, ADerrors.get_repidc_from_id(p.ids[i], ws))
            if length(idc) == 2
                # Write covobs data
                i_cdata += 1
                if !haskey(jsonstring["obsdata"][index], "cdata")
                    jsonstring["obsdata"][index]["cdata"] = []
                end
                push!(jsonstring["obsdata"][index]["cdata"], Dict{String, Any}())
                jsonstring["obsdata"][index]["cdata"][i_cdata]["id"] = ADerrors.get_name_from_id(p.ids[i], ws)
                jsonstring["obsdata"][index]["cdata"][i_cdata]["layout"] = "1, 1"
                jsonstring["obsdata"][index]["cdata"][i_cdata]["cov"] = [dt[1] ^ 2]
                jsonstring["obsdata"][index]["cdata"][i_cdata]["grad"] = [[1.0]]
            else
                # Write Monte Carlo data
                i_data += 1
                if !haskey(jsonstring["obsdata"][index], "data")
                    jsonstring["obsdata"][index]["data"] = []
                end
                push!(jsonstring["obsdata"][index]["data"], Dict{String, Any}())
                jsonstring["obsdata"][index]["data"][i_data]["id"] = ADerrors.get_name_from_id(p.ids[i], ws)
                jsonstring["obsdata"][index]["data"][i_data]["replica"] = []
                rep_indices = prepend!(cumsum(convert(Vector{Int32}, ws.fluc[ws.map_ids[p.ids[i]]].ivrep)), 0)
                for j in 1:length(my_rep_names)
                    for delta_entry in dt[rep_indices[j] + 1:rep_indices[j + 1]]
                        if isapprox(delta_entry, 0.0; atol=1e-14)
                            error("Irregular Monte Carlo chain cannot be safely written to json.gz file.")
                        end
                    end
                    tmp = []
                    push!(jsonstring["obsdata"][index]["data"][i_data]["replica"], Dict{String, Any}())
                    jsonstring["obsdata"][index]["data"][i_data]["replica"][j]["name"] = my_rep_names[j]
                    push!(tmp, idc[rep_indices[j] + 1:rep_indices[j + 1]])
                    push!(tmp, dt[rep_indices[j] + 1:rep_indices[j + 1]])
                    @cast deltas[i][j] := tmp[j][i]
                    jsonstring["obsdata"][index]["data"][i_data]["replica"][j]["deltas"] = deltas
                end
            end
        end
    end
    if !endswith(fname, ".json.gz")
        fname *= ".json.gz"
    end

    GZip.open(fname, "w") do f
        JSON.print(f, jsonstring, indent)
    end
end

export load_json, dump_to_json

end # module
