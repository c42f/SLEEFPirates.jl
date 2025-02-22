module SLEEFPirates
if isdefined(Base, :Experimental) && isdefined(Base.Experimental, Symbol("@max_methods"))
  @eval Base.Experimental.@max_methods 1
end
using Base: llvmcall
using Base.Math:
  uinttype, exponent_bias, exponent_mask, significand_bits, IEEEFloat, exponent_raw_max

using VectorizationBase
using Static: True, False, One, lt, StaticInt

using VectorizationBase:
  vzero,
  AbstractSIMD,
  _Vec,
  fma_fast,
  data,
  VecUnroll,
  NativeTypes,
  FloatingTypes,
  vIEEEFloat,
  vfmadd,
  vfnmadd,
  vfmsub,
  vfnmsub,
  Double,
  dadd,
  dadd2,
  dsub,
  dsub2,
  dmul,
  dsqu,
  dsqrt,
  ddiv,
  drec,
  scale,
  dnormalize


import IfElse: ifelse

export Vec, sigmoid_fast, tanh_fast, PReLu, gelu, softplus, silu, Elu
#, loggamma

const FloatType64 = Union{Float64,AbstractSIMD{<:Any,Float64}}
const FloatType32 = Union{Float32,AbstractSIMD{<:Any,Float32}}
const FloatType = Union{FloatType64,FloatType32}
const IntegerType64 = Union{Int64,AbstractSIMD{<:Any,Int64}}
const IntegerType32 = Union{Int32,AbstractSIMD{<:Any,Int32}}
const IntegerType = Union{IntegerType64,IntegerType32}

fpinttype(::Type{Float64}) = Int
fpinttype(::Type{Float32}) = Int32
function fpinttype(::Type{Vec{N,Float64}}) where {N}
  Vec{N,Int}
end
function fpinttype(::Type{Vec{N,Float32}}) where {N}
  Vec{N,Int32}
end


## constants

const MLN2 =
  6.931471805599453094172321214581765680755001343602552541206800094933936219696955e-01 # log(2)
const MLN2E = 1.442695040888963407359924681001892137426645954152985934135449406931 # log2(e)

const M_PI = 3.141592653589793238462643383279502884 # pi
const PI_2 =
  1.570796326794896619231321691639751442098584699687552910487472296153908203143099     # pi/2
const PI_4 =
  7.853981633974483096156608458198757210492923498437764552437361480769541015715495e-01 # pi/4
const M_1_PI = 0.318309886183790671537767526745028724 # 1/pi
const M_2_PI = 0.636619772367581343075535053490057448 # 2/pi
const M_4_PI =
  1.273239544735162686151070106980114896275677165923651589981338752471174381073817     # 4/pi

const MSQRT2 =
  1.414213562373095048801688724209698078569671875376948073176679737990732478462102 # sqrt(2)
const M1SQRT2 =
  7.071067811865475244008443621048490392848359376884740365883398689953662392310596e-01 # 1/sqrt(2)

const M2P13 =
  1.259921049894873164767210607278228350570251464701507980081975112155299676513956 # 2^1/3
const M2P23 =
  1.587401051968199474751705639272308260391493327899853009808285761825216505624206 # 2^2/3

const MLOG10_2 = 3.3219280948873623478703194294893901758648313930

const MDLN10E(::Type{Float64}) = Double(0.4342944819032518, 1.098319650216765e-17) # log10(e)
const MDLN10E(::Type{Float32}) = Double(0.4342945f0, -1.010305f-8)

const MDLN2E(::Type{Float64}) = Double(1.4426950408889634, 2.0355273740931033e-17) # log2(e)
const MDLN2E(::Type{Float32}) = Double(1.442695f0, 1.925963f-8)

const MDLN2(::Type{Float64}) =
  Double(0.693147180559945286226764, 2.319046813846299558417771e-17)  # log(2)
const MDLN2(::Type{Float32}) = Double(0.69314718246459960938f0, -1.904654323148236017f-9)

const MDPI(::Type{Float64}) = Double(3.141592653589793, 1.2246467991473532e-16) # pi
const MDPI(::Type{Float32}) = Double(3.1415927f0, -8.742278f-8)
const MDPI2(::Type{Float64}) = Double(1.5707963267948966, 6.123233995736766e-17) # pi/2
const MDPI2(::Type{Float32}) = Double(1.5707964f0, -4.371139f-8)

const MD2P13(::Type{Float64}) = Double(1.2599210498948732, -2.589933375300507e-17) # 2^1/3
const MD2P13(::Type{Float32}) = Double(1.2599211f0, -2.4018702f-8)

const MD2P23(::Type{Float64}) = Double(1.5874010519681996, -1.0869008194197823e-16) # 2^2/3
const MD2P23(::Type{Float32}) = Double(1.587401f0, 1.9520385f-8)

# Split pi into four parts (each is 26 bits)
const PI_A(::Type{Float64}) = 3.1415926218032836914
const PI_B(::Type{Float64}) = 3.1786509424591713469e-08
const PI_C(::Type{Float64}) = 1.2246467864107188502e-16
const PI_D(::Type{Float64}) = 1.2736634327021899816e-24

const PI_A(::Type{Float32}) = 3.140625f0
const PI_B(::Type{Float32}) = 0.0009670257568359375f0
const PI_C(::Type{Float32}) = 6.2771141529083251953f-7
const PI_D(::Type{Float32}) = 1.2154201256553420762f-10

const PI_XD(::Type{Float32}) = 1.2141754268668591976f-10
const PI_XE(::Type{Float32}) = 1.2446743939339977025f-13

# split 2/pi into upper and lower parts
const M_2_PI_H = 0.63661977236758138243
const M_2_PI_L = -3.9357353350364971764e-17

# Split log(10) into upper and lower parts
const L10U(::Type{Float64}) = 0.30102999566383914498
const L10L(::Type{Float64}) = 1.4205023227266099418e-13

const L10U(::Type{Float32}) = 0.3010253906f0
const L10L(::Type{Float32}) = 4.605038981f-6

# Split log(2) into upper and lower parts
const L2U(::Type{Float64}) = 0.69314718055966295651160180568695068359375
const L2L(::Type{Float64}) = 0.28235290563031577122588448175013436025525412068e-12

const L2U(::Type{Float32}) = 0.693145751953125f0
const L2L(::Type{Float32}) = 1.428606765330187045f-06

const TRIG_MAX(::Type{Float64}) = 1e14
const TRIG_MAX(::Type{Float32}) = 1.0f7

const SQRT_MAX(::Type{Float64}) = 1.3407807929942596355e154
const SQRT_MAX(::Type{Float32}) = 18446743523953729536.0f0

include("estrin.jl")
include("utils.jl")  # utility functions
# include("double.jl") # Dekker style double double functions
include("priv.jl")   # private math functions
include("exp.jl")    # exponential functions
include("log.jl")    # logarithmic functions
include("trig.jl")   # trigonometric and inverse trigonometric functions
include("hyp.jl")    # hyperbolic and inverse hyperbolic functions
include("misc.jl")   # miscallenous math functions including pow and cbrt
include("rectifier.jl")
# if Int === Int64
#     if isfile(joinpath(@__DIR__, "svmlwrap.jl"))
#         include("svmlwrap.jl")
#     elseif Sys.islinux()
#         @warn "Building SLEEFPirates is likely to increase performance of some functions."
#     end
# end

# fallback definitions

@generated function to_vecunrollscalar(v::Vec{W,T}, ::StaticInt{N}) where {N,W,T}
  t = Expr(:tuple)
  for n ∈ 0:N
    push!(t.args, :(VectorizationBase.extractelement(v, $n)))
  end
  Expr(:block, Expr(:meta, :inline), :(VecUnroll($t)))
end
@generated function to_vecunrollscalar(
  v::VecUnroll{M,W,T,V},
  ::StaticInt{N},
) where {M,W,T,N,V<:VectorizationBase.AbstractSIMDVector{W,T}}
  t = Expr(:tuple)
  n = 0
  q = Expr(:block, Expr(:meta, :inline), :(d = VectorizationBase.data(v)))
  dobreak = false
  for m ∈ 0:M
    vm = Symbol(:v_, m)
    push!(q.args, :($vm = getfield(d, $(m + 1))))
    for w ∈ 0:W-1
      push!(t.args, :(VectorizationBase.extractelement($vm, $w)))
      dobreak = n == N
      dobreak && break
      n += 1
    end
    dobreak && break
  end
  push!(q.args, :(VecUnroll($t)))
  q
end

for func in (
  :sin,
  :cos,
  :tan,
  :asin,
  :acos,
  :atan,
  :sinh,
  :cosh,
  :tanh,
  :asinh,
  :acosh,
  :atanh,
  :log,
  :log2,
  :log10,
  :log1p,
  :expm1,
  :cbrt,
  :sin_fast,
  :cos_fast,
  :tan_fast,
  :asin_fast,
  :acos_fast,
  :atan_fast,# :atan2_fast,
  :log_fast,
  :log2_fast,
  :log10_fast,
  :cbrt_fast,
)#, :exp, :exp2, :exp10
  @eval begin
    @inline $func(a::Float16) = Float16.($func(Float32(a)))
    @inline $func(x::Real) = $func(float(x))
    @inline $func(v::AbstractSIMD{W,I}) where {W,I<:Integer} = $func(float(v))
    @inline $func(i::MM) = $func(Vec(i))
    @inline $func(v::VecUnroll{N,1,T,T}) where {N,T<:NativeTypes} =
      to_vecunrollscalar($func(VectorizationBase.transpose_vecunroll(v)), StaticInt{N}())
  end
end
@inline function sincos(v::VecUnroll{N,1,T,T}) where {N,T<:NativeTypes}
  s, c = sincos(VectorizationBase.transpose_vecunroll(v))
  to_vecunrollscalar(s, StaticInt{N}()), to_vecunrollscalar(c, StaticInt{N}())
end
@inline function sincos_fast(v::VecUnroll{N,1,T,T}) where {N,T<:NativeTypes}
  s, c = sincos_fast(VectorizationBase.transpose_vecunroll(v))
  to_vecunrollscalar(s, StaticInt{N}()), to_vecunrollscalar(c, StaticInt{N}())
end
# Tπ(::Type{T}) where {T} = promote_type(T, typeof(π))(π)
for func ∈ (:sin, :cos)
  funcpi = Symbol(func, :pi)
  funcfast = Symbol(func, :_fast)
  funcpifast = Symbol(func, :pi_fast)
  @eval @inline $funcpi(v::AbstractSIMD{W,T}) where {W,T} =
    $func(vbroadcast(Val{W}(), Tπ(T) * v))
  @eval @inline Base.$funcpi(v::AbstractSIMD{W,T}) where {W,T} = $func(T(π) * v)
  @eval @inline $funcpifast(v::AbstractSIMD{W,T}) where {W,T} = $funcfast(T(π) * v)
  @eval @inline $funcpi(i::MM) = $funcpi(float(i))
end
if VERSION ≥ v"1.6"
  @inline Base.sincospi(v::AbstractSIMD{W,T}) where {W,T} = sincos(T(π) * v)
  @inline Base.sincospi(v::Vec{W,T}) where {W,T} = sincos(T(π) * v)
end
@inline sincospi_fast(v::AbstractSIMD{W,T}) where {W,T} = sincos_fast(T(π) * v)
@inline sincospi_fast(v::Vec{W,T}) where {W,T} = sincos_fast(T(π) * v)

for func in (:sinh, :cosh, :tanh, :asinh, :acosh, :atanh, :log1p, :expm1)#, :exp, :exp2, :exp10
  @eval begin
    @inline Base.$func(
      x::AbstractSIMD{W,T},
    ) where {W,T<:Union{Float32,Float64,Int32,UInt32,Int64,UInt64}} = $func(x)
    @inline Base.$func(x::MM) = $func(Vec(x))
  end
end
for func ∈ (:sin, :cos, :tan, :asin, :acos, :atan, :log, :log2, :log10, :cbrt, :sincos)
  func_fast = Symbol(func, :_fast)
  @eval begin
    @inline Base.$func(x::AbstractSIMD) = $func_fast(float(x))
    @inline Base.FastMath.$func_fast(x::AbstractSIMD) = $func_fast(float(x))
  end
end
@inline Base.FastMath.atan_fast(a::T, b::Number) where {T<:AbstractSIMD} =
  atan_fast(a, T(b))
@inline Base.FastMath.atan_fast(a::Number, b::T) where {T<:AbstractSIMD} =
  atan_fast(T(a), b)
@inline Base.FastMath.atan_fast(a::T, b::T) where {T<:AbstractSIMD} = atan_fast(a, b)
@inline Base.FastMath.atan_fast(a::AbstractSIMD, b::AbstractSIMD) =
  ((c, d) = promote(a, b); atan_fast(c, d))
for func in (:atan, :hypot, :pow)
  func2 = func === :pow ? :^ : func
  ptyp = func === :pow ? :FloatingTypes : :NativeTypes
  @eval begin
    @inline $func(y::Real, x::Real) = $func(promote(float(y), float(x))...)
    @inline $func(a::Float16, b::Float16) = Float16($func(Float32(a), Float32(b)))
    # @inline Base.$func2(x::AbstractSIMD{W,T}, y::Vec{W,T}) where {W,T<:Union{Float32,Float64}} = $func(x, Vec(y))
    # @inline Base.$func2(x::Vec{W,T}, y::AbstractSIMD{W,T}) where {W,T<:Union{Float32,Float64}} = $func(Vec(x), y)
    @inline Base.$func2(x::AbstractSIMD{W,T}, y::T) where {W,T<:Union{Float32,Float64}} =
      $func(x, convert(Vec{W,T}, y))
    @inline Base.$func2(x::T, y::AbstractSIMD{W,T}) where {W,T<:Union{Float32,Float64}} =
      $func(convert(Vec{W,T}, x), y)
    @inline Base.$func2(
      x::AbstractSIMD{W,T1},
      y::T2,
    ) where {W,T1<:Union{Float32,Float64},T2<:$ptyp} = $func(x, convert(Vec{W,T1}, y))
    @inline Base.$func2(
      x::T2,
      y::AbstractSIMD{W,T1},
    ) where {W,T1<:Union{Float32,Float64},T2<:NativeTypes} = $func(convert(Vec{W,T1}, x), y)
    @inline Base.$func2(
      x::AbstractSIMD{W,T},
      y::AbstractSIMD{W,T},
    ) where {W,T<:Union{Float32,Float64}} = $func(x, y)
    @inline $func(v1::AbstractSIMD{W,I}, v2::AbstractSIMD{W,I}) where {W,I<:Integer} =
      $func(float(v1), float(v2))
  end
end
@inline ldexp(x::Float16, q::Int) = Float16(ldexpk(Float32(x), q))

# @inline logit(x) = log(Base.FastMath.div_fast(x,Base.FastMath.sub_fast(one(x),x)))
# @inline invlogit(x) = Base.FastMath.inv_fast(Base.FastMath.add_fast(one(x), exp(Base.FastMath.sub_fast(x))))
# @inline nlogit(x) = log(Base.FastMath.div_fast(Base.FastMath.sub_fast(one(x),x), x))
# @inline ninvlogit(x) = Base.FastMath.inv_fast(Base.FastMath.add_fast(one(x), exp(x)))
# @inline log1m(x) = log1p(Base.FastMath.sub_fast(x))

max_tanh(::Type{Float64}) =
  19.06154746539849599509609553228539867418786340504817671278462587964799037885145
max_tanh(::Type{Float32}) =
  9.010913339828708369989037671244720498805572920317272822795576296065428827978905f0

@inline function tanh_fast(x::Union{Float32,AbstractSIMD{<:Any,Float32}})
  # stolen from https://github.com/FluxML/NNlib.jl/pull/345
  # https://github.com/FluxML/NNlib.jl/blob/5dd04df4e95f9f9b70d6232fac546f3e98899fc2/src/activations.jl#L766-L773
  x2 = abs2(x)
  n0 = muladd(1.587199f-8, x2, 2.2332108f-5)
  d0 = muladd(8.7767893f-7, x2, 0.0003453992f0)
  n1 = muladd(n0, x2, 0.0035974074f0)
  d1 = muladd(d0, x2, 0.026262015f0)
  n2 = muladd(n1, x2, 0.1346604f0)
  d2 = muladd(d1, x2, 0.4679937f0)
  n = muladd(n2, x2, 1.0f0)
  d = muladd(d2, x2, 1.0f0)
  ifelse(x2 < 66.0f0, @fastmath(x * (n / d)), sign(x))
end
@inline function tanh_fast(x::Union{Float64,AbstractSIMD{<:Any,Float64}})
  exp2xm1 = expm1_fast(Base.FastMath.add_fast(x, x))
  # Division is faster than approximate inversion in
  # t = Base.FastMath.mul_fast(exp2xm1, Base.FastMath.inv_fast(Base.FastMath.add_fast(exp2xm1, typeof(x)(2))))
  t = Base.FastMath.div_fast(exp2xm1, Base.FastMath.add_fast(exp2xm1, typeof(x)(2)))
  ifelse(abs(x) > max_tanh(eltype(x)), copysign(one(x), x), t)
end
@inline tanh_fast(x::IntegerType) = tanh_fast(float(x))
@inline Base.FastMath.tanh_fast(x::AbstractSIMD) = tanh_fast(x)
@inline function Base.:(^)(
  x::AbstractSIMD{W,<:Base.BitInteger},
  y::AbstractSIMD{W,<:Base.BitInteger},
) where {W}
  float(x)^y
end
# sigmoid_max(::Type{Float64}) = 36.42994775023704665301938332748370611415146834112402863375388447785857586583462
# sigmoid_max(::Type{Float32}) = 17.3286794841963099036462718631317335849086302638474573162299687307067828965093f0

# @inline sigmoid_fast(x) = Base.FastMath.inv_fast(Base.FastMath.add_fast(one(x), exp(Base.FastMath.sub_fast(x))))
@inline sigmoid_fast(x) =
  inv(Base.FastMath.add_fast(one(x), Base.exp(Base.FastMath.sub_fast(x))))
# `inv_fast` was slower than `inv`
# @inline sigmoid_fast(x) = Base.FastMath.inv_fast(Base.FastMath.add_fast(one(x), exp(Base.FastMath.sub_fast(x))))



# Commented out, because it probably isn't relocatable =/
# if Sys.islinux() && Sys.ARCH === :x86_64
#     mvl = find_library("libmvec.so", ["/usr/lib64/", "/usr/lib", "/lib/x86_64-linux-gnu"])
#     if mvl !== "libmvec.so"
#         @eval const MVECLIB = $mvl
#         VectorizationBase.REGISTER_SIZE ≥ 16 && include("svmlwrap16.jl")
#         VectorizationBase.REGISTER_SIZE ≥ 32 && include("svmlwrap32.jl")
#         VectorizationBase.REGISTER_SIZE ≥ 64 && include("svmlwrap64.jl")
#     end
# end

# We should minimize precompilation, because of the need for relocatability =/

# include("precompile.jl")
# _precompile_()


end # module
