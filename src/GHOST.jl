module GHOST

import JuMP
import MathOptInterface as MOI
import GHOST_jll
import CompositionalNetworks as CN
import ConstraintProgrammingExtensions as CPE
import Constraints
using Libdl
using TOML, SHA

include("CAPI.jl")
include("callbacks.jl")
include("sets.jl")
include("objective.jl")
include("MOI_wrapper.jl")

"Create a JuMP error set from a CompositionalNetworks ICN or Composition."
function ICNError end
include("icn.jl")
include("catalogue.jl")

__init__() = _initialize_callbacks!()

end
