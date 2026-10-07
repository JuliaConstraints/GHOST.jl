struct ICNFactory{N,P}
    network::N
    parameters::P
end
struct ICNEvaluator{F,W,P}
    f::F
    workspace::W
    parameters::P
end
(evaluator::ICNEvaluator)(values) = evaluator.f(values; X=evaluator.workspace, evaluator.parameters...)

ICNError(network::CN.AbstractICN; parameters...) =
    Error(ICNFactory(deepcopy(network), (; parameters...)))
function ICNError(composition::CN.Composition; parameters...)
    composition.network isa CN.AbstractICN || throw(ArgumentError("The composition must retain its ICN network to allocate a private workspace"))
    return ICNError(composition.network; parameters...)
end
function _bind_error(factory::ICNFactory, dimension::Int)
    composition = CN.composition(factory.network)
    workspace = CN.composition_workspace(factory.network, dimension)
    return ICNEvaluator(composition.f, workspace, deepcopy(factory.parameters))
end
