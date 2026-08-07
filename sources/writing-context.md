# Project Context — HVTI graphics ecosystem

Why we write the way we do. The harness reads this so prose carries the right
assumptions about purpose and constraints.

## The ecosystem

- **hvtiPlotR** — ggplot2 themes and plot constructors; the R replacement for
  the historical `plot.sas` macro.
- **ggRandomForests** — graphics for random forests and variable priority
  (varPro), built on randomForestSRC.
- **temporal_hazard** — additive (Blackstone, Naftel, and Turner, 1986) hazard
  models in pure R.
- **hvti_graphics** — this recipes book, which ties the three together into a
  house style for clinical figures.

## Purpose

A single source of ggplot2 recipes for publication-quality, house-style figures
for HVTI CORR (Cardiovascular Outcomes Registries and Research, Cleveland Clinic
Heart & Vascular Institute) publications and presentations. Each recipe pairs a
figure with the code that produces it, so the next person starts from a working
script instead of a blank one.

Two ideas run through the book: a figure is built in two steps (a constructor
prepares and validates the data, then `plot()` hands you a bare ggplot you finish
with `+`), and every example stands on its own with its own sample data.

## Constraints that shape the writing

- **CORR publication standards** — figures must meet journal expectations.
- **Reproducibility** — Git, renv, dataset manifests; every figure regenerable.
- **No PHI** — never in code, prose, or example data.
- **R-first** — R is the working language; SAS is the heritage we migrate from.
- **SAS-migration heritage** — many readers trust SAS output, so we say when the
  R version matches the original (the way we checked temporal_hazard fit for fit).
