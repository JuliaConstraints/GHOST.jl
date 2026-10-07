function _started_model(; threads=1, objective=false)
    model = Model(GHOST.Optimizer)
    set_time_limit_sec(model, 0.05)
    set_optimizer_attribute(model, MOI.NumberOfThreads(), threads)
    set_optimizer_attribute(model, "error_backend", "native")
    @variable(model, 1 <= x[1:3] <= 3, Int)
    set_start_value.(x, [1, 2, 3])
    @constraint(model, x in MOI.AllDifferent(3))
    objective && @objective(model, Min, 2x[1] + x[2] + 7)
    return model, x
end

@testset "Native results checked in original integer model" begin
    for threads in (1, 2)
        model, x = _started_model(; threads)
        optimize!(model)
        @test termination_status(model) == MOI.LOCALLY_SOLVED
        @test primal_status(model) == MOI.FEASIBLE_POINT
        @test sort(Int.(value.(x))) == [1, 2, 3]
        @test_throws MOI.ResultIndexBoundsError MOI.get(backend(model), MOI.VariablePrimal(2), index(x[1]))
    end
    model, x = _started_model(; objective=true)
    @constraint(model, x[1] + x[2] >= 3)
    optimize!(model)
    @test termination_status(model) == MOI.TIME_LIMIT
    @test primal_status(model) == MOI.FEASIBLE_POINT
    @test sort(Int.(value.(x))) == [1, 2, 3]
    @test value(x[1]) + value(x[2]) >= 3
    @test objective_value(model) == 2value(x[1]) + value(x[2]) + 7
    set_upper_bound(x[1], 1)
    @test termination_status(model) == MOI.OPTIMIZE_NOT_CALLED
    optimize!(model)
    @test value(x[1]) == 1

    impossible, y = _started_model()
    @constraint(impossible, sum(y) == 9)
    optimize!(impossible)
    @test termination_status(impossible) == MOI.TIME_LIMIT
    @test primal_status(impossible) == MOI.NO_SOLUTION
    @test result_count(impossible) == 0

    fixed = Model(GHOST.Optimizer)
    set_time_limit_sec(fixed, 0.02)
    @variable(fixed, z, Int)
    fix(z, 7)
    optimize!(fixed)
    @test value(z) == 7

    continuous = Model(GHOST.Optimizer)
    @variable(continuous, 1 <= c <= 2)
    @test_throws ArgumentError optimize!(continuous)
    unbounded = Model(GHOST.Optimizer)
    @variable(unbounded, u, Int)
    @test_throws ArgumentError optimize!(unbounded)
end

@testset "Julia callback ownership and exception boundary" begin
    model, x = _started_model()
    @constraint(model, x in GHOST.Error(values -> abs(sum(values) - 6)))
    GC.gc()
    optimize!(model)
    @test sum(value.(x)) == 6
    optimizer = unsafe_backend(model)
    state = only(optimizer.session.callbacks)
    @test state.calls > 0
    @test state.failure === nothing
    input_buffer = state.values
    optimize!(model)
    @test only(optimizer.session.callbacks).values !== input_buffer

    for score in (-1.0, NaN, Inf)
        invalid, y = _started_model()
        @constraint(invalid, y in GHOST.Error(_ -> score))
        @test_throws DomainError optimize!(invalid)
    end
    counter = Ref(0)
    failure, y = _started_model()
    @constraint(failure, y in GHOST.Error(values -> begin
        counter[] += 1
        counter[] > 1 && error("callback sentinel")
        0.0
    end))
    @test_throws ErrorException optimize!(failure)
    @test termination_status(failure) == MOI.OTHER_ERROR

    parallel, p = _started_model(; threads=2)
    @constraint(parallel, p in GHOST.Error(values -> abs(sum(values) - 6)))
    @test_throws ArgumentError optimize!(parallel)

    # Functional isolation test, not a throughput comparison.
    jobs = [Threads.@spawn begin
        worker_model, variables = _started_model()
        @constraint(worker_model, variables in GHOST.Error(values -> abs(sum(values) - 6)))
        optimize!(worker_model)
        (Int.(value.(variables)), only(unsafe_backend(worker_model).session.callbacks).values)
    end for _ in 1:2]
    results = fetch.(jobs)
    @test all(result -> sort(result[1]) == [1, 2, 3], results)
    @test results[1][2] !== results[2][2]
end
