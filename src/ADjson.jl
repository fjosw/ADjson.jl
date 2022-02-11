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

        if !(entry["type"] in ["Obs", "List"])
            error("Type '" * entry["type"] * "' is not implemented." )
        end

        res = Vector{uwreal}()
        out_length = parse(Int,(entry["layout"]))
        for element in entry["data"]

            conc_deltas = [Float64[] for b in 1:out_length]
            int_cnfg_numbers = Int[]
            rep_lengths = Int[]

            for rep in element["replica"]
                my_arr = rep["deltas"]
                @cast deltas[i][j] := my_arr[j][i]
                cnfg_numbers = convert(Array{Int,1}, deltas[1])

                for ch in 1:length(cnfg_numbers)
                    if ch != cnfg_numbers[ch]
                        error("Irregular Monte Carlo chain cannot be safely read into ADerrors.")
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
                    push!(res, uwreal(Vector{Float64}(conc_deltas[i]), element["id"], rep_lengths))
                    # For irregular Monte Carlo chains one could use but this is not save
                    # push!(res, uwreal(Vector{Float64}(conc_deltas[i]), element["id"], rep_lengths, int_cnfg_numbers, sum(rep_lengths)))
                end
            else
                for i in 1:out_length
                    res[i] += uwreal(Vector{Float64}(conc_deltas[i]), element["id"], rep_lengths)
                    # For irregular Monte Carlo chains one could use but this is not save
                    res[i] += uwreal(Vector{Float64}(conc_deltas[i]), element["id"], rep_lengths, int_cnfg_numbers, sum(rep_lengths))
                end
            end
        end

        for i in 1:out_length
            res[i] += entry["value"][i]
        end

        if length(res) == 1
            push!(res_list, res[1])
        else
            push!(res_list, res)
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
    jsonstring["program"] = "ADjson 0.1"
    jsonstring["who"] = ENV["USER"]
    jsonstring["host"] = gethostname() * ", " * Sys.MACHINE
    jsonstring["date"] = Dates.format(now(localzone()), "Y-mm-dd HH:MM:SS zzzz")
    jsonstring["version"] = "0.2"
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
        jsonstring["obsdata"][index]["data"] = []

        for i in 1:convert(Int32, ADerrors.unique_ids!(p, ws))
            push!(jsonstring["obsdata"][index]["data"], Dict{String, Any}())        
            jsonstring["obsdata"][index]["data"][i]["id"] = ADerrors.get_name_from_id(p.ids[i], ws)
            jsonstring["obsdata"][index]["data"][i]["replica"] = []

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
                println("Covobs case?")
                println([convert(Int32, 1)])
            end

            # Write data
            rep_indices = prepend!(cumsum(convert(Vector{Int32}, ws.fluc[ws.map_ids[p.ids[i]]].ivrep)), 0)
            for j in 1:length(my_rep_names)
                tmp = []
                push!(jsonstring["obsdata"][index]["data"][i]["replica"], Dict{String, Any}())
                jsonstring["obsdata"][index]["data"][i]["replica"][j]["name"] = my_rep_names[j]            
                push!(tmp, idc[rep_indices[j] + 1:rep_indices[j + 1]])
                push!(tmp, dt[rep_indices[j] + 1:rep_indices[j + 1]])
                @cast deltas[i][j] := tmp[j][i]
                jsonstring["obsdata"][index]["data"][i]["replica"][j]["deltas"] = deltas
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
