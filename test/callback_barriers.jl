function callback_status(state,values,result;count=length(values))
    GC.@preserve state values result begin
        ccall(GHOST._callback_pointer[],Cint,
            (Ptr{Cint},Csize_t,Ptr{Cdouble},Ptr{Cvoid}),values,count,result,
            pointer_from_objref(state))
    end
end
function callback_cycles(state,values,result,repetitions)
    for _ in 1:repetitions
        callback_status(state,values,result)==GHOST.CAPI.SUCCESS || error("callback failed")
    end
    nothing
end

@testset "Latest-world callback barrier and private inputs" begin
    # This callable is defined after the native trampoline was initialized.
    late=Core.eval(@__MODULE__,:(values->Float64(sum(values))+0.5))
    states=ntuple(_->GHOST.CallbackState(late,zeros(Int,3),nothing,0,false),2)
    values=Cint[1,2,3];result=Ref{Cdouble}(-99)
    for state in states
        @test callback_status(state,values,result)==GHOST.CAPI.SUCCESS
        @test result[]==6.5
        @test state.calls==1
        @test state.values==[1,2,3]
        @test state.failure===nothing
    end
    @test states[1].values!==states[2].values
    @test states[1].score!==states[2].score
    states[1].values[1]=99
    @test states[2].values==[1,2,3]
    @test values==Cint[1,2,3]
    callback_cycles(states[1],values,result,1024)
    @test (@allocated callback_cycles(states[1],values,result,1024))<=128
end

@testset "Native exception boundary retains the first failure" begin
    values=Cint[1,2,3];result=Ref{Cdouble}(-99)
    for score in (-1.0,NaN,Inf)
        state=GHOST.CallbackState(_->score,zeros(Int,3),nothing,0,false)
        @test callback_status(state,values,result)==GHOST.CAPI.ERROR_SOLVER
        @test state.failure.ex isa DomainError
        @test state.calls==1
        first_failure=state.failure
        @test callback_status(state,values,result)==GHOST.CAPI.ERROR_SOLVER
        @test state.failure===first_failure
        @test result[]==-99
    end
    objective=GHOST.CallbackState(_->-3.5,zeros(Int,3),nothing,0,true)
    @test callback_status(objective,values,result)==GHOST.CAPI.SUCCESS
    @test result[]==-3.5
    malformed=GHOST.CallbackState(sum,zeros(Int,3),nothing,0,false)
    @test callback_status(malformed,values,result;count=2)==GHOST.CAPI.ERROR_SOLVER
    @test malformed.failure.ex isa DimensionMismatch
    @test malformed.calls==0
    @test result[]==-3.5
    throws=GHOST.CallbackState(_->throw(ArgumentError("callback sentinel")),zeros(Int,3),nothing,0,false)
    @test callback_status(throws,values,result)==GHOST.CAPI.ERROR_SOLVER
    @test throws.failure.ex isa ArgumentError
end
