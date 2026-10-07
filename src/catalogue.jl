"Declare a library constraint by name and parameters; no error implementation is required."
struct Constraint{P} <: JuMP.AbstractVectorSet
    identity::Symbol
    parameters::P
end
function Constraint(identity::Symbol; parameters...)
    haskey(Constraints.USUAL_CONSTRAINTS, identity) || throw(ArgumentError("Unknown catalogue constraint: $identity"))
    return Constraint(identity, (; parameters...))
end
struct MOICatalogue{P} <: MOI.AbstractVectorSet
    identity::Symbol
    dimension::Int
    parameters::P
end
function JuMP.moi_set(set::Constraint, dimension::Int)
    dimension > 0 || throw(ArgumentError("Catalogue constraints require a nonempty scope"))
    candidate = MOICatalogue(set.identity, dimension, deepcopy(set.parameters))
    _catalogue_variant(candidate) # Reject unavailable variants at model construction.
    return candidate
end
Base.copy(set::MOICatalogue) = MOICatalogue(set.identity, set.dimension, deepcopy(set.parameters))
MOI.supports_constraint(::Optimizer, ::Type{MOI.VectorOfVariables}, ::Type{<:MOICatalogue}) = true
MOI.supports_constraint(::Optimizer, ::Type{MOI.VectorOfVariables}, ::Type{CPE.AllEqual}) = true
MOI.supports_constraint(::Optimizer, ::Type{MOI.VectorOfVariables}, ::Type{CPE.Increasing}) = true
MOI.supports_constraint(::Optimizer, ::Type{MOI.VectorOfVariables}, ::Type{CPE.Decreasing}) = true

_is_catalogue(::Union{MOICatalogue,CPE.AllEqual,CPE.Increasing,CPE.Decreasing}) = true
_catalogue_set(set::MOICatalogue) = set
_catalogue_set(set::MOI.AllDifferent) = MOICatalogue(:all_different, set.dimension, (;))
_catalogue_set(set::CPE.AllEqual) = MOICatalogue(:all_equal, set.dimension, (;))
_catalogue_set(set::CPE.Increasing) = MOICatalogue(:ordered, set.dimension, (;))
_catalogue_set(set::CPE.Decreasing) = MOICatalogue(:ordered, set.dimension, (; reversed=true))

const _catalogue_path = joinpath(@__DIR__, "..", "resources", "catalogue.toml")
const _catalogue = TOML.parsefile(_catalogue_path)
const _saved_witnesses = Dict((Symbol(w["family"]), w["variant"]) => w for w in _catalogue["witnesses"])

function _catalogue_variant(set::MOICatalogue)
    identity, parameters = set.identity, set.parameters
    variant, prototype, allowed = if identity == :all_different
        haskey(parameters, :vals) ? ("exceptions", (; vals=[0]), (:vals,)) :
            ("numeric list", (;), ())
    elseif identity == :all_equal
        ("numeric list", (;), ())
    elseif identity == :ordered
        ("numeric list", (;), (:reversed,))
    elseif identity == :sum
        haskey(parameters, :val) || throw(ArgumentError("sum requires val"))
        haskey(parameters, :pair_vars) ?
            ("weighted scalar condition", (; pair_vars=[1,2,3], op=(==), val=2), (:pair_vars,:op,:val)) :
            ("scalar condition", (; op=(==), val=2), (:op,:val))
    elseif identity in (:minimum, :maximum)
        haskey(parameters, :val) || throw(ArgumentError("$identity requires val"))
        ("scalar condition", (; op=(==), val=2), (:op,:val))
    elseif identity == :instantiation
        haskey(parameters, :pair_vars) || throw(ArgumentError("instantiation requires pair_vars"))
        ("numeric target vector", (; pair_vars=[1,2,3]), (:pair_vars,))
    elseif identity == :count
        haskey(parameters, :vals) && haskey(parameters, :val) || throw(ArgumentError("count requires vals and val"))
        ("membership and scalar condition", (; vals=[0], op=(==), val=2), (:vals,:op,:val))
    elseif identity == :nvalues
        haskey(parameters, :val) || throw(ArgumentError("nvalues requires val"))
        ("exceptions and scalar condition", (; vals=[0], op=(==), val=2), (:vals,:op,:val))
    else
        throw(ArgumentError("No saved ICN adapter is exposed for $identity yet"))
    end
    all(key -> key in allowed, keys(parameters)) || throw(ArgumentError("Unsupported parameters for $identity / $variant"))
    haskey(_saved_witnesses, (identity,variant)) || throw(ArgumentError("No saved ICN for $identity / $variant"))
    if haskey(parameters, :op)
        parameters.op in ((==), (!=), (<), (<=), (>), (>=)) || throw(ArgumentError("Only qualified numeric scalar operators are supported"))
    end
    return variant, prototype
end

function _schema_hash(network)
    available = parentindices(network.weights)[1]
    offset = 0
    parts = String[]
    for layer in network.layers
        operations = [name for (i,name) in enumerate(keys(layer.fn)) if offset+i in available]
        push!(parts, repr((layer.name, layer.mutex, operations)))
        offset += length(layer.fn)
    end
    return bytes2hex(sha256("ICN:" * join(parts, ";")))
end

struct CatalogueEvaluator{E,S,M,B}
    evaluator::E
    set::S
    metadata::M
    reversed_buffer::B
end
function (evaluator::CatalogueEvaluator)(values)
    if get(evaluator.set.parameters, :reversed, false)
        @inbounds for i in eachindex(values)
            evaluator.reversed_buffer[i] = values[end-i+1]
        end
        return evaluator.evaluator(evaluator.reversed_buffer)
    end
    return evaluator.evaluator(values)
end

function _bind_catalogue(set::MOICatalogue, dimension::Int)
    variant, prototype = _catalogue_variant(set)
    witness = _saved_witnesses[(set.identity, variant)]
    witness["factory"] == "learnable_composition; max_depth=1" || error("Unsupported saved ICN factory")
    network = CN.learnable_composition(prototype; max_depth=1)
    _schema_hash(network) == witness["schema_sha256"] || error("Saved ICN schema differs from the installed CompositionalNetworks version")
    weights = BitVector(witness["weights"])
    CN.check_weights_validity(network, weights) || error("Invalid saved ICN weights")
    CN.apply!(network, weights) || error("Saved ICN weights could not be restored")
    parameters = set.parameters
    if set.identity == :ordered
        parameters = (;)
    elseif set.identity in (:sum,:minimum,:maximum,:count,:nvalues)
        parameters = merge((; op=(==)), parameters)
        set.identity == :nvalues && (parameters = merge((; vals=Int[]), parameters))
    end
    if haskey(parameters, :pair_vars)
        length(parameters.pair_vars) == dimension || throw(DimensionMismatch("pair_vars and constraint scope"))
    end
    evaluator = _bind_error(ICNFactory(network, deepcopy(parameters)), dimension)
    metadata = (; identity=set.identity, variant, formula=witness["formula"],
        schema_sha256=witness["schema_sha256"], checked=witness["checked"],
        provenance=_catalogue["provenance"], source_bank_sha256=_catalogue["source_bank_sha256"])
    return CatalogueEvaluator(evaluator, set, metadata, zeros(Int, dimension))
end

function _validate_catalogue(set::MOICatalogue, values)
    parameters = set.parameters
    if set.identity == :ordered
        return get(parameters, :reversed, false) ? issorted(values; rev=true) : issorted(values)
    end
    return Constraints.concept(set.identity)(values; parameters...)
end

"List shipped library constraints and their saved ICN variants, with provenance."
function catalogue()
    return [(; identity, variant, formula=record["formula"], checked=record["checked"],
        provenance=_catalogue["provenance"]) for ((identity,variant),record) in
        sort!(collect(_saved_witnesses); by=entry -> string(first(entry)))]
end
