@testset "JuMP/MOI model interface" begin
    optimizer = GHOST.Optimizer()
    @test MOI.is_empty(optimizer)
    @test MOI.get(optimizer, MOI.TerminationStatus()) == MOI.OPTIMIZE_NOT_CALLED
    @test MOI.get(optimizer, MOI.ResultCount()) == 0
    @test MOI.supports_incremental_interface(optimizer)
    @test MOI.supports_constraint(optimizer, MOI.VariableIndex, MOI.Integer)
    @test MOI.supports_constraint(optimizer, MOI.VectorOfVariables, GHOST.MOIError{typeof(sum)})
    @test !MOI.supports_constraint(optimizer, MOI.ScalarQuadraticFunction{Float64}, MOI.LessThan{Float64})
    @test_throws MOI.UnsupportedAttribute MOI.set(optimizer, MOI.RawOptimizerAttribute("unknown"), 1)
    @test_throws ArgumentError MOI.set(optimizer, MOI.NumberOfThreads(), 0)
    @test_throws ArgumentError MOI.set(optimizer, MOI.TimeLimitSec(), 0.0)
    @test_throws ArgumentError MOI.set(optimizer, MOI.TimeLimitSec(), Inf)
    @test_throws ArgumentError MOI.set(optimizer, MOI.RawOptimizerAttribute("plateau_probability"), 101)
    v = MOI.add_variable(optimizer)
    MOI.add_constraint(optimizer, v, MOI.Integer())
    MOI.add_constraint(optimizer, v, MOI.Interval(1.0, 3.0))
    MOI.set(optimizer, MOI.VariableName(), v, "x")
    MOI.set(optimizer, MOI.VariablePrimalStart(), v, 2.0)
    @test MOI.get(optimizer, MOI.VariableName(), v) == "x"
    @test MOI.get(optimizer, MOI.VariableIndex, "x") == v
    @test MOI.get(optimizer, MOI.NumberOfVariables()) == 1
    @test MOI.get(optimizer, MOI.VariablePrimalStart(), v) == 2.0
    destination = GHOST.Optimizer()
    map = MOI.copy_to(destination, optimizer)
    @test MOI.get(destination, MOI.VariableName(), map[v]) == "x"
    @test MOI.get(destination, MOI.VariablePrimalStart(), map[v]) == 2.0
    @test_throws MOI.ResultIndexBoundsError MOI.get(optimizer, MOI.VariablePrimal(), v)
    MOI.empty!(optimizer)
    @test MOI.is_empty(optimizer)
    @test !MOI.is_valid(optimizer, v)

    model = Model(GHOST.Optimizer)
    @variable(model, 1 <= x[1:3] <= 3, Int)
    @constraint(model, x in GHOST.Error(values -> length(values) - length(unique(values))))
    @objective(model, Min, sum(x))
    @test num_variables(model) == 3
    @test num_constraints(model; count_variable_in_set_constraints=false) == 1
end
