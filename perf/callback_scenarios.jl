module CallbackScenarios
using GHOST
import CompositionalNetworks as CN

function all_different_network()
    network=CN.ICN(parameters=Symbol[])
    fill!(network.weights.parent,false)
    offset=0
    for (layer,selected) in zip(network.layers,
            ((:count_equal_left,:count_equal_right),(:sum,),(:count_positive,),(:id,)))
        names=collect(keys(layer.fn))
        for operation in selected
            network.weights.parent[offset+only(findall(==(operation),names))]=true
        end
        offset+=length(layer.fn)
    end
    CN.check_weights_validity(network,network.weights) || error("invalid ICN fixture")
    network
end

function callback_case(parameters)
    repetitions=get(parameters,"repetitions",1024)
    icn=get(parameters,"icn",false)
    warm=get(parameters,"warm",true)
    prepare=()->begin
        evaluator=icn ? GHOST._bind_error(GHOST.ICNError(all_different_network()).f,3) :
            (values->Float64((sum(values)-6)^2))
        state=GHOST.CallbackState(evaluator,zeros(Int,3),nothing,0,false)
        inputs=(Cint[1,2,3],Cint[1,1,3])
        expected=map(values->Float64(Base.invokelatest(evaluator,Int.(values))),inputs)
        all(isfinite,expected) && all(>=(0),expected) || error("invalid fixture scores")
        iszero(expected[1]) && !iszero(expected[2]) || error("original truth oracle")
        result=Ref{Cdouble}(NaN)
        # Each private ICN binding can create a new compiled callable. Warm that
        # actual trampoline specialization during fixture preparation, not timing.
        if warm
            GC.@preserve state inputs result begin
                for values in inputs
                    status=ccall(GHOST._callback_pointer[],Cint,
                        (Ptr{Cint},Csize_t,Ptr{Cdouble},Ptr{Cvoid}),values,length(values),
                        result,pointer_from_objref(state))
                    status==GHOST.CAPI.SUCCESS || error("fixture callback failed")
                end
            end
            state.calls=0
            result[]=NaN
        end
        (;state,inputs,result,expected)
    end
    operation=fixture->begin
        Base.@nospecialize fixture
        state=fixture.state::GHOST.CallbackState
        inputs=fixture.inputs::Tuple{Vector{Cint},Vector{Cint}}
        result=fixture.result::Base.RefValue{Cdouble}
        score=0.0
        GC.@preserve state inputs result begin
            for _ in 1:repetitions, values in inputs
                status=ccall(GHOST._callback_pointer[],Cint,
                    (Ptr{Cint},Csize_t,Ptr{Cdouble},Ptr{Cvoid}),values,length(values),
                    result,pointer_from_objref(state))
                status==GHOST.CAPI.SUCCESS || error("callback failed")
                score+=result[]
            end
        end
        score
    end
    verify=(fixture,score)->score==repetitions*sum(fixture.expected) &&
        fixture.state.failure===nothing && fixture.state.values==Int.(last(fixture.inputs)) &&
        iszero(fixture.expected[1])==allunique(first(fixture.inputs)) &&
        iszero(fixture.expected[2])==allunique(last(fixture.inputs))
    (;prepare,operation,verify)
end
end
wrapper_callback_case(p)=CallbackScenarios.callback_case(p)
