function _all_different_icn()
    network = CN.ICN(parameters=Symbol[])
    fill!(network.weights.parent, false)
    offset = 0
    for (layer, selected) in zip(network.layers,
            ((:count_equal_left, :count_equal_right), (:sum,), (:count_positive,), (:id,)))
        names = collect(keys(layer.fn))
        for operation in selected
            network.weights.parent[offset + only(findall(==(operation), names))] = true
        end
        offset += length(layer.fn)
    end
    return network
end

@testset "CompositionalNetworks error zero set and private workspaces" begin
    network = _all_different_icn()
    @test CN.check_weights_validity(network, network.weights)
    set = GHOST.ICNError(network)
    first_evaluator = GHOST._bind_error(set.f, 3)
    second_evaluator = GHOST._bind_error(set.f, 3)
    @test first_evaluator.workspace !== second_evaluator.workspace
    for values in Iterators.product(1:3, 1:3, 1:3)
        values = collect(values)
        score = Base.invokelatest(first_evaluator, values)
        @test isfinite(score) && score >= 0
        @test iszero(score) == (length(unique(values)) == 3)
    end
    model, x = _started_model()
    @constraint(model, x in set)
    optimize!(model)
    @test sort(Int.(value.(x))) == [1, 2, 3]
    compiled_set = GHOST.ICNError(CN.composition(network))
    @test Base.invokelatest(GHOST._bind_error(compiled_set.f, 3), [1, 2, 3]) == 0
end
