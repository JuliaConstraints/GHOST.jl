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

@testset "Single and vector MOI deletion invalidate native ownership" begin
    optimizer=GHOST.Optimizer()
    variables=MOI.add_variables(optimizer,4)
    constraints=[MOI.add_constraint(optimizer,variable,MOI.Integer()) for variable in variables]
    MOI.delete(optimizer,first(constraints))
    @test !MOI.is_valid(optimizer,first(constraints))
    MOI.delete(optimizer,constraints[2:3])
    @test all(index->!MOI.is_valid(optimizer,index),constraints[2:3])
    MOI.delete(optimizer,first(variables))
    @test !MOI.is_valid(optimizer,first(variables))
    MOI.delete(optimizer,variables[2:3])
    @test all(index->!MOI.is_valid(optimizer,index),variables[2:3])
    @test MOI.get(optimizer,MOI.NumberOfVariables())==1
    @test MOI.is_valid(optimizer,last(variables))
    session=GHOST.CAPI.Session(false)
    optimizer.session=session
    MOI.delete(optimizer,last(constraints))
    @test session.ptr==C_NULL
    @test optimizer.session===nothing
    @test MOI.get(optimizer,MOI.ResultCount())==0
    @test MOI.get(optimizer,MOI.TerminationStatus())==MOI.OPTIMIZE_NOT_CALLED
end
