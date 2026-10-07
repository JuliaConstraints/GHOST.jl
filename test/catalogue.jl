@testset "Library constraints need no user error function" begin
    @test length(GHOST.catalogue()) == 11
    for (identity, parameters) in ((:all_different,(;)), (:all_equal,(;)),
            (:ordered,(;)), (:ordered,(; reversed=true)),
            (:sum,(; val=3)), (:sum,(; op=(<=),val=1,pair_vars=[-1,2,1])),
            (:minimum,(; op=(>=),val=0)), (:maximum,(; op=(<),val=2)),
            (:instantiation,(; pair_vars=[0,1,2])), (:count,(; vals=[0,1],val=2)),
            (:nvalues,(; val=2)), (:all_different,(; vals=[0])))
        set = JuMP.moi_set(GHOST.Constraint(identity; parameters...), 3)
        evaluator = GHOST._bind_catalogue(set, 3)
        for assignment in Iterators.product(-1:2, -1:2, -1:2)
            values = collect(assignment)
            score = Base.invokelatest(evaluator, values)
            @test isfinite(score) && score >= 0
            @test iszero(score) == GHOST._validate_catalogue(set, values)
        end
    end
    @test_throws ArgumentError JuMP.moi_set(GHOST.Constraint(:ordered; op=(<)), 3)
    @test_throws ArgumentError JuMP.moi_set(GHOST.Constraint(:sum), 3)
    @test_throws ArgumentError JuMP.moi_set(GHOST.Constraint(:cumulative), 3)
    model = Model(GHOST.Optimizer)
    set_time_limit_sec(model, 0.05)
    @variable(model, 1 <= x[1:3] <= 3, Int)
    set_start_value.(x, [1,2,3])
    @constraint(model, x in MOI.AllDifferent(3))
    @constraint(model, x in GHOST.Constraint(:sum; val=6))
    optimize!(model)
    @test sort(Int.(value.(x))) == [1,2,3]
    @test sum(value.(x)) == 6
    states = unsafe_backend(model).session.callbacks
    @test length(states) == 2
    @test all(state -> state.f isa GHOST.CatalogueEvaluator, states)
    @test states[1].f.evaluator.workspace !== states[2].f.evaluator.workspace
    @test all(state -> state.f.metadata.checked > 0, states)
end
