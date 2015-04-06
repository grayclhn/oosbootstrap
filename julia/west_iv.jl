## Taken from version 0.4
cld{T<:Integer }(x::T, y::T) = div(x,y)+(!signbit(x$y)&(rem(x,y)!=0))

function makedata!(y::Vector{Float64}, w::Matrix{Float64}, z::Matrix{Float64})
    # We're storing the initial errors v in the vector y to save
    # memory. The code matches the mathematics better using v as an
    # alias for y.
    v = y
    randn!(v); randn!(w); randn!(z)
    for i in 1:length(y)
        w[i,1] = z[i,1] + v[i]
        w[i,2] = z[i,2] + v[i]
        y[i] = w[i,1] + w[i,2] + v[i] # This line writes over v[i] as well.
    end
end

# oosstat! constructs the OOS test statistic corresponding to example
# 5.2 in his 1996 Econometrica paper
#
# f - the vector that will hold the out-of-sample statistics; this vector
#     is overwritten by the function.
# y - data: the target varable, n-vector
# w - a matrix with the predictors; (n × k) each column corresponds to
#     a different forecasting model. The models will be estimated with IV
# z - a matrix with the instruments for each model (n × k)
# ZW_t - preallocated storage for the recursive window matrices Z[i,1:t]'*W[i,1:t];
#        this array is written over by the function (2 × 2 × k)
# ZY_t - preallocated storage for the recursive window vector Z[i,1:t]'*Y[1:t];
#        this matrix is written over by the function, (2 × k)
# l_t  - preallocated storage for the period t forecast loss, k-vector
function oosstat!(ZW_t::Array{Float64,3}, ZY_t::Matrix{Float64}, l_t::Vector{Float64},
                  f::Vector{Float64}, y::Vector{Float64}, w::Matrix{Float64},
                  z::Matrix{Float64})
    oosstat!(ZW_t, ZY_t, l_t, f, y, w, z, [1:length(y)])
end

function oosstat!(ZW_t::Array{Float64,3}, ZY_t::Matrix{Float64}, l_t::Vector{Float64},
                  f::Vector{Float64}, y::Vector{Float64}, w::Matrix{Float64},
                  z::Matrix{Float64}, bootindex::Vector{Int})
    R = length(y) - length(f)
    _,_,k = size(ZW_t)
    # Initialize ZW_t and ZY_t
    bootinit = bootindex[1:R]
    for i in 1:k
        ZW_t[1, 1, i] = R
        ZW_t[1, 2, i] = sum(w[bootinit,i])
        ZW_t[2, 1, i] = sum(z[bootinit,i])
        ZW_t[2, 2, i] = sum(w[bootinit, i] .* z[bootinit, i])
        ZY_t[1, i] = sum(y[bootinit])
        ZY_t[2, i] = sum(y[bootinit] .* z[bootinit, i])
    end
    # Update with next observation and produce forecasts
    for t = (R+1):length(y)
        boot_t = bootindex[t]
        for i in 1:k
            # Calculate the loss for the previously estimated model
            coef = ZW_t[:,:,i] \ ZY_t[:,i]
            l_t[i] = (y[boot_t] - (coef[1] + coef[2] * w[boot_t,i]))^2
            t == length(y) && break
            # Update estimates with the current observation.
            ZW_t[1,1,i] += 1.
            ZW_t[1,2,i] += w[boot_t,i]
            ZW_t[2,1,i] += z[boot_t,i]
            ZW_t[2,2,i] += w[boot_t,i] * z[boot_t,i]
            ZY_t[1,i] += y[boot_t]
            ZY_t[2,i] += z[boot_t,i] * y[boot_t]
        end
        f[t-R] = l_t[1] - l_t[2]
    end
    mean(f)
end

function runmc!(oosstat::Vector{Float64}, oostest::BitVector, nboot, P, R, α)
    n = P + R
    y = Array(Float64, n)
    w = Array(Float64, n, 2)
    z = Array(Float64, n, 2)
    ZW = Array(Float64, 2, 2, 2)
    ZY = Array(Float64, 2, 2)
    l = Array(Float64, 2)
    yboot = similar(y)
    wboot = similar(w)
    zboot = similar(z)
    f = Array(Float64,  P)
    bootindex = Array(Int, n)
    oosboot = Array(Float64, nboot)
    for i in 1:length(oosstat)
        makedata!(y, w, z)
        oosstat[i] = oosstat!(ZW, ZY, l, f, y, w, z)
        for j in 1:nboot
            rand!(1:n, bootindex)
            oosboot[j] = oosstat!(ZW, ZY, l, f, y, w, z, bootindex)
        end
        bootcrit = quantile(oosboot - mean(oosboot), [α/2, 1 - α/2])
        oostest[i] = oosstat[i] < bootcrit[1] || oosstat[i] > bootcrit[2]
    end
end

nsim = 600
mcstat = Array(Float64, nsim)
mctest = BitArray(nsim)
@time runmc!(mcstat, mctest, 499, 120, 240, 0.1)
mean(mctest)
