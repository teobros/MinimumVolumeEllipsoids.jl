module MinimumVolumeEllipsoids

using Distributions
using LinearAlgebra
using PDMats
using SparseArrays

export minvol
export rand

function minvol(X::AbstractMatrix, tol::Real=1e-7, KKY::Integer=0, maxit::Integer=100000)
    n, m = size(X)

    n100 = max(n, 100);
    n50000 = max(n, 50000);

    mxv = zeros(1, maxit)
    mnv = zeros(1, maxit)
    flagstep = zeros(1, maxit)
    λhist = zeros(1, maxit)
    mvarerrhist = zeros(1, maxit)
    improv = zeros(1, maxit)
    iter = 1

    if KKY >= 1
        u = vec((1 / m) * ones(m, 1))
    else
        u = initwt(X)
    end

    # Initialize Cholesky Factor
    upos = findall(u .> 0)
    A = Diagonal(sqrt.(u[upos])) * X[:, upos]
    _, R = qr(A)
    R = Cholesky(R, :U, 0)
    factor = 1

    RX = R.U' \ X
    var = sum(RX .* RX, dims=1) |> vec
    maxvar, maxj = findmax(var)

    act = [1:m;]
    XX = copy(X)
    mm = m
    oldmm = m

    # Use the Harman-Pronzato test to see if columns of X can be eliminated.
    ept = maxvar - n
    thresh = n * (1 + ept / 2 - (ept * (4 + ept - 4 / n))^.5 / 2)
    e = findall((var .> thresh) .| (u .> 1e-8))
    act = act[e]
    XX = X[:, e]
    mm = length(e)

    # If only n columns remain, recompute u and R
    if mm == n
        u = (1 / n) * ones(n, 1)
        upos = findall(u .> 1e-8)
        A = Diagonal(sqrt(u)) * XX'
        _, R = qr(A)
        R = Cholesky(R, :U, 0)
        factor = 1
        RX = R.U' \ XX
        var = sum(RX .* RX, dims=1) |> vec
    else
        var = var[e]
        u = u[e] / sum(u[e])
        upos = findall(u .> 1e-8)
    end
    oldmm = mm

    # Find "furthest" and "cloest" points
    maxvar, maxj = findmax(var)
    minvar, ind = findmin(var[upos])
    minj = upos[ind]
    mnvup = minvar

    mxv[iter] = maxvar
    mnv[iter] = minvar

    if KKY == 1
        mnvup = n
    end

    while ((maxvar > (1 + tol) * n) || (mnvup < (1 - tol) * n)) && iter < maxit
        if maxvar + mnvup > 2 * n
            j = maxj
            mvar = maxvar
        else
            j = minj
            mvar = mnvup
        end

        flag_recompute = false
        xj = XX[:, j]
        Rxj = R.U' \ xj
        Mxj = factor * (R.U \ Rxj)
        mvarn = factor * (Rxj' * Rxj)
        mvarerror = abs(mvarn - mvar) / max(1, mvar)
        mvarerrhist[iter] = mvarerror
        if (mvarerror > 1e-8)
            flag_recompute = true
        end
        mvar = mvarn

        # COMPUTE STEPSIZE LAM (MAY BE NEGATIVE), EPSILON, AND
        # IMPROVEMENT IN LOGDET
        λ = (mvar  - n) / ((n - 1) * mvar)
        ep = mvar / n - 1
        uj = u[j]
        λ = max(λ, -uj)
        λhist[iter] = λ
        if λ < -u[j] + 1e-8
            flagstep[iter] = 1
        elseif λ < 0
            flagstep[iter] = 2
        elseif u[j] < 1e-8
            flagstep[iter] = 3
        else
            flagstep[iter] = 4
        end

        # Update u and make sure it stays nonnegative
        imp = log(1 + λ * mvar) - n * log(1 + λ)
        uold = u
        u[j] = max(uj + λ, 0)
        u = (1 / (1 + λ)) * u
        upos = findall(u .> 1e-8)

        if iter > 1 && iter - 1 == floor((iter - 1 / n50000) * n50000)
            upos = findall(uold .> 0)
            M = XX[:, upos] * Diagonal(uold[upos]) * XX[:, upos]'
            normdiff = norm(factor * M - R.U' * R.U) / (factor * norm(M))
            if normdiff > 1e-8
                flag_recompute = true
            end
        end

        if flag_recompute
            upos = findall(u .> 0)
            A = Diagonal(sqrt.(u[upos])) * XX[:, upos]'
            _, R = qr(A)
            R = Cholesky(R, :U, 0)
            factor = 1
            RX = R.U' \ XX
            var = sum(RX .* RX, dims=1) |> vec
        else
            xx = sqrt(abs(λ) * factor) * xj
            if λ > 0
                lowrankupdate!(R, xx)
            else
                lowrankdowndate!(R, xx)
            end
            factor = factor * (1 + λ)
        end

        maxvar, maxj = findmax(var)

        if iter > 1 && (iter - 1 == floor((iter - 1 / n100) * n100))
            ept = maxvar - n
            thresh = n * (1 + ept / 2 - (ept / 2) * (4 + ept - 4 / n)^.5 / 2)
            e = findall(var > thresh | u' .> 1e-8)
            if length(e) < mm
                act = act[e]
                XX = XX[:, e]
                mm = length(e)
                if mm == n
                    u = (1 / n) * ones(n, 1)
                    uold = u
                    upos = findall(u .> 1e-8)
                    A = Diagonal(sqrt.(u)) * XX'
                    _, R = qr(A)
                    R = Cholesky(R, :U, 0)
                    factor = 1
                    RX = R.U' \ XX
                    var = sum(RX .* RX, dims=1) |> vec
                    maxvar, maxj = findmax(var)
                else
                    var = var[e]
                    u = u[e] / sum(u[e])
                    uold = uold[e] / sum(uold[e])
                    upos = findall(u .> 1e-8)
                    maxvar, maxj = findmax(var)
                end
                oldmm = mm
            end
        end

        upos = findall(u .> 0)
        minvar, ind = findmin(var[upos])
        minj = upos[ind]
        mnvup = minvar
        iter += 1
        improv[iter] = imp
        mxv[iter] = maxvar
        mnv[iter] = minvar
        if KKY == 1
            mnvup = n
        end
    end

    mxv = mxv[1:iter]
    mnv = mnv[1:iter]
    flagstep = flagstep[1:iter]
    improv = improv[1:iter]
    λhist = λhist[1:iter]
    uu = zeros(m, 1)
    uu[act] = u
    u = uu
    varr = -ones(m, 1)
    varr[act] = var
    var = varr
    iter -= iter

    return u, R
end

    """
    initwt(X)

Obtain the initial weights `u` using the Kumar-Yildirim algorithm, taking into account that
`X` represents [X, -X].
"""
function initwt(X::AbstractMatrix)

    n, m = size(X)
    u = zeros(m, 1)
    Q = 1.0 * I(n)
    d = Q[:, 1]

    for j in 1:n
        # compute the maximizer of | d'*x | over the columns of X.
        dX = abs.(d' * X) |> vec
        maxdX, ind = findmax(dX)
        u[ind] = 1

        j == n && break

        # update Q
        y = X[:, ind]
        z = Q' * y

        if j > 1
            z[1:j - 1] = zeros(j - 1, 1)
        end

        ζ = norm(z)
        zj = z[j]
        if zj < 0
            ζ = -ζ
        end
        zj += ζ
        z[j] = zj
        Q = Q - (Q * z) * ((1 / (ζ * zj)) * z')
        d = Q[:, j + 1]
    end

    u /= n
    return vec(u)
end

function Base.rand(S::AbstractMatrix, z::Vector{<:Real}, m::Integer)
    n = size(S, 1)
    X = randn(n, m)
    X = X ./ kron(ones(n, 1), sqrt.(sum(X.^2, dims=1)))
    R = ones(n, 1) * rand(1, m).^(1 / n)
    sphere = R .* X
    ellipsoid = cholesky(S).U * sphere
    return ellipsoid * sqrt(n) + z .* ones(1, m)
end

end # module