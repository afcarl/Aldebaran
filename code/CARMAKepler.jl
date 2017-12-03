module CARMAKepler

using CARMA
using Distributions
using Ensemble
using Kepler

type MultiEpochPosterior
    ts::Array{Array{Float64, 1}, 1}
    ys::Array{Array{Float64, 1}, 1}
    dys::Array{Array{Float64, 1}, 1}

    inds::Array{Array{Int, 1}, 1}
    
    allts::Array{Float64, 1}
    allys::Array{Float64, 1}
    alldys::Array{Float64, 1}
    
    P_min::Float64
    P_max::Float64

    K_min::Float64
    K_max::Float64

    ndrw::Int
    nosc::Int

    rate_min::Float64
    rate_max::Float64

    f_min::Float64
    f_max::Float64

    rms_min::Float64
    rms_max::Float64

    Q_min::Float64
    Q_max::Float64
end

function MultiEpochPosterior(ts, ys, dys, per_min, per_max, ndrw, nosc, rate_min, rate_max, f_min, f_max, Q_max)
    allts = vcat(ts...)
    allys = vcat(ys...)
    alldys = vcat(dys...)
    
    allinds = sortperm(allts)

    iallinds = invperm(allinds)
    
    inds = []
    i = 1
    for t in ts
        push!(inds, iallinds[i:i+size(t,1)-1])
        i = i+size(t,1)
    end

    allts = allts[allinds]
    allys = allys[allinds]
    alldys = alldys[allinds]

    rms_max = maximum([std(y) for y in ys])
    rms_min = minimum([std(y) for y in ys])

    T = allts[end]-allts[1]
    dtmin = minimum(diff(allts))
    
    MultiEpochPosterior(ts, ys, dys, inds, allts, allys, alldys, per_min, per_max, rms_min/100.0, 10.0*rms_max, ndrw, nosc, rate_min, rate_max, f_min, f_max, rms_min/100.0, rms_max*10.0, 1.0, Q_max)
end

type MultiEpochParams
    mu::Array{Float64, 1}
    nu::Array{Float64, 1}
    
    K::Float64
    P::Float64
    e::Float64
    omega::Float64
    chi::Float64

    drw_rms::Array{Float64,1}
    drw_rate::Array{Float64,1}

    osc_rms::Array{Float64, 1}
    osc_freq::Array{Float64, 1}
    osc_Q::Array{Float64, 1}
end

function nparams(post::MultiEpochPosterior)
    2*size(post.ts, 1) + 5 + 2*post.ndrw + 3*post.nosc
end

function to_params(post::MultiEpochPosterior, x::Array{Float64, 1})
    i = 1
    mu = zeros(size(post.ts, 1))
    nu = zeros(size(post.ts, 1))
    for j in 1:size(post.ts, 1)
        mu[j] = x[i]
        nu[j] = Parameterizations.bounded_value(x[i+1], 0.5, 2.0)
        i = i + 2
    end
    
    K = Parameterizations.bounded_value(x[i], post.K_min, post.K_max)
    P = Parameterizations.bounded_value(x[i+1], post.P_min, post.P_max)
    ecosw, esinw = Parameterizations.unit_disk_value(x[i+2:i+3])
    e = sqrt(ecosw*ecosw + esinw*esinw)
    omega = atan2(esinw, ecosw)
    chi = Parameterizations.bounded_value(x[i+4], 0.0, 1.0)
    i = i + 5

    drw_rms = zeros(post.ndrw)
    drw_rate = zeros(post.ndrw)

    rmin = post.rate_min
    for j in 1:post.ndrw
        drw_rms[j] = Parameterizations.bounded_value(x[i], post.rms_min, post.rms_max)
        drw_rate[j] = Parameterizations.bounded_value(x[i+1], rmin, post.rate_max)
        i = i + 2
        rmin = drw_rate[j]
    end

    osc_rms = zeros(post.nosc)
    osc_freq = zeros(post.nosc)
    osc_Q = zeros(post.nosc)
    freq_min = post.f_min
    for j in 1:post.nosc
        osc_rms[j] = Parameterizations.bounded_value(x[i], post.rms_min, post.rms_max)
        osc_freq[j] = Parameterizations.bounded_value(x[i+1], freq_min, post.f_max)
        osc_Q[j] = Parameterizations.bounded_value(x[i+2], post.Q_min, post.Q_max)
        i = i + 3
        freq_min = osc_freq[j]
    end

    MultiEpochParams(mu, nu, K, P, e, omega, chi, drw_rms, drw_rate, osc_rms, osc_freq, osc_Q)
end

function to_array(post::MultiEpochPosterior, p::MultiEpochParams)
    x = zeros(nparams(post))

    i = 1
    for j in 1:size(post.ts,1)
        x[i] = p.mu[j]
        x[i+1] = Parameterizations.bounded_param(p.nu[j], 0.5, 2.0)
        i = i + 2
    end

    x[i] = Parameterizations.bounded_param(p.K, post.K_min, post.K_max)
    x[i+1] = Parameterizations.bounded_param(p.P, post.P_min, post.P_max)
    x[i+2:i+3] = Parameterizations.unit_disk_param([p.e*cos(p.omega), p.e*sin(p.omega)])
    x[i+4] = Parameterizations.bounded_param(p.chi, 0.0, 1.0)
    i = i + 5

    rmin = post.rate_min
    for j in 1:post.ndrw
        x[i] = Parameterizations.bounded_param(p.drw_rms[j], post.rms_min, post.rms_max)
        x[i+1] = Parameterizations.bounded_param(p.drw_rate[j], rmin, post.rate_max)
        i = i + 2
        rmin = p.drw_rate[j]
    end

    freq_min = post.f_min
    for j in 1:post.nosc
        x[i] = Parameterizations.bounded_param(p.osc_rms[j], post.rms_min, post.rms_max)
        x[i+1] = Parameterizations.bounded_param(p.osc_freq[j], freq_min, post.f_max)
        x[i+2] = Parameterizations.bounded_param(p.osc_Q[j], post.Q_min, post.Q_max)
        i = i + 3
        freq_min = p.osc_freq[j]
    end

    x
end

function log_prior(post::MultiEpochPosterior, x::Array{Float64, 1})
    log_prior(post, to_params(post, x))
end

function bounded_logjac_value(x, low, high)
    Parameterizations.bounded_logjac(x, Parameterizations.bounded_param(x, low, high), low, high)
end

function log_prior(post::MultiEpochPosterior, p::MultiEpochParams)
    logp = 0.0
    
    for i in 1:size(post.ts, 1)
        mu = mean(post.ys[i])
        sigma = std(post.ys[i])

        logp += logpdf(Normal(mu, 10*sigma), p.mu[i])

        logp -= log(p.nu[i]) # flat in log(nu)
        logp += bounded_logjac_value(p.nu, 0.5, 2)
    end

    logp -= log(p.K)
    logp += bounded_logjac_value(p.K, post.K_min, post.K_max)

    logp -= log(p.P)
    logp += bounded_logjac_value(p.P, post.P_min, post.P_max)

    # Uniform prior on unit disk for (e*cos(omega), e*sin(omega))
    z = [p.e*cos(p.omega), p.e*sin(p.omega)]
    logp += Parameterizations.unit_disk_logjac(z, Parameterizations.unit_disk_param(z))

    # Uniform prior in chi
    logp += bounded_logjac_value(p.chi, 0.0, 1.0)

    rmin = post.rate_min
    for i in 1:post.ndrw
        logp -= log(p.drw_rms[i])
        logp += bounded_logjac_value(p.drw_rms[i], post.rms_min, post.rms_max)

        logp -= log(p.drw_rate[i])
        logp += bounded_logjac_value(p.drw_rate[i], rmin, post.rate_max)

        rmin = p.drw_rate[i]
    end

    fmin = post.f_min
    for i in 1:post.nosc
        logp -= log(p.osc_rms[i])
        logp += bounded_logjac_value(p.osc_rms[i], post.rms_min, post.rms_max)

        logp -= log(p.osc_freq[i])
        logp += bounded_logjac_value(p.osc_freq[i], fmin, post.f_max)
        fmin = p.osc_freq[i]

        logp -= log(p.osc_Q[i])
        logp += bounded_logjac_value(p.osc_Q[i], post.Q_min, post.Q_max)
    end

    logp
end

function draw_prior(post::MultiEpochPosterior, n)
    hcat([draw_prior(post) for i in 1:n]...)
end

function rand_flatlog(low, high)
    exp(log(low) + rand()*log(high/low))
end

function draw_prior(post::MultiEpochPosterior)
    nts = size(post.ts, 1)

    mus = zeros(nts)
    nus = zeros(nts)

    for i in eachindex(mus)
        mu = mean(post.ys[i])
        sigma = std(post.ys[i])

        mus[i] = mu + 10*sigma*randn()

        nus[i] = rand_flatlog(0.5, 2.0)
    end

    K = rand_flatlog(post.K_min, post.K_max)
    P = rand_flatlog(post.P_min, post.P_max)

    x = 1.0
    y = 1.0
    while x*x + y*y > 1.0
        x = rand()
        y = rand()
    end

    e = sqrt(x*x + y*y)
    omega = atan2(y,x)

    chi = rand()

    drw_rmss = zeros(post.ndrw)
    drw_rates = zeros(post.ndrw)

    for i in eachindex(drw_rmss)
        drw_rmss[i] = rand_flatlog(post.rms_min, post.rms_max)
        drw_rates[i] = rand_flatlog(post.rate_min, post.rate_max)
    end
    inds = sortperm(drw_rates)
    drw_rmss = drw_rmss[inds]
    drw_rates = drw_rates[inds]

    osc_rmss = zeros(post.nosc)
    osc_freqs = zeros(post.nosc)
    osc_Qs = zeros(post.nosc)

    for i in eachindex(osc_rmss)
        osc_rmss[i] = rand_flatlog(post.rms_min, post.rms_max)
        osc_freqs[i] = rand_flatlog(post.f_min, post.f_max)
        osc_Qs[i] = rand_flatlog(post.Q_min, post.Q_max)
    end
    inds = sortperm(osc_freqs)
    osc_rmss = osc_rmss[inds]
    osc_freqs = osc_freqs[inds]
    osc_Qs = osc_Qs[inds]

    p = MultiEpochParams(mus, nus, K, P, e, omega, chi, drw_rmss, drw_rates, osc_rmss, osc_freqs, osc_Qs)

    to_array(post, p)
end

function log_likelihood(post::MultiEpochPosterior, x::Array{Float64, 1})
    log_likelihood(post, to_params(post, x))
end

function produce_ys_dys(post::MultiEpochPosterior, p::MultiEpochParams)
    n = size(post.allts, 1)

    ys = zeros(n)
    dys = zeros(n)

    for i in eachindex(post.ts)
        ys[post.inds[i]] = post.ys[i] - p.mu[i]
        dys[post.inds[i]] = post.dys[i]*p.nu[i]
    end

    for i in eachindex(ys)
        ys[i] = ys[i] - Kepler.rv(post.allts[i], p.K, p.P, p.e, p.omega, p.chi)
    end

    ys, dys
end

function log_likelihood(post::MultiEpochPosterior, p::MultiEpochParams)
    ys, dys = produce_ys_dys(post, p)

    filt = Celerite.CeleriteKalmanFilter(0.0, p.drw_rms, p.drw_rate, p.osc_rms, p.osc_freq, p.osc_Q)

    Celerite.log_likelihood(filt, post.allts, ys, dys)
end

function residuals(post::MultiEpochPosterior, x::Array{Float64, 1})
    residuals(post, to_params(post, x))
end

function residuals(post::MultiEpochPosterior, p::MultiEpochParams)
    ys, dys = produce_ys_dys(post, p)

    filt = Celerite.CeleriteKalmanFilter(0.0, p.drw_rms, p.drw_rate, p.osc_rms, p.osc_freq, p.osc_Q)

    Celerite.residuals(filt, post.allts, ys, dys)
end

function psd(post::MultiEpochPosterior, x::Array{Float64, 1}, fs::Array{Float64, 1})
    psd(post, to_params(post, x), fs)
end

function psd(post::MultiEpochPosterior, p::MultiEpochParams, fs::Array{Float64, 1})
    filt = Celerite.CeleriteKalmanFilter(0.0, p.drw_rms, p.drw_rate, p.osc_rms, p.osc_freq, p.osc_Q)

    Celerite.psd(filt, fs)
end

end
