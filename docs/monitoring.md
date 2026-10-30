# Monitoring semantics

Each cycle records a pair of outcomes against monotonic elapsed time. Cancelled
pairs and non-increasing timestamps are discarded. History holds 60 pairs; each
display median uses successful outcomes within the last five pairs. A failed
latest probe must be displayed as unavailable even if older successes exist.
Loss is the proportion of failed outcomes in the bounded history.

Degradation starts when the median difference strictly exceeds 20 ms, or both
medians strictly exceed 30 ms. The condition must remain present at each sample
for at least 10 elapsed seconds. A gap longer than five seconds resets the pending
timer. Both-slow takes precedence over a difference alert. Failures immediately
produce an explicit unreachable state.

Recovery requires a difference below 10 ms and both medians below 20 ms for six
seconds. Values on recovery boundaries retain the current alert. These defaults
are configurable observations, not proof of a particular faulty component.
