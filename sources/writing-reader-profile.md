# Reader Profiles — documentation audiences

A menu of selectable audiences for the `ehrlinger-writing` harness. Write for
ONE persona at a time, not a blend. The active persona is chosen per task
(explicit choice → repo `CLAUDE.md` default → ask). The `hvtiGraphics` recipes
book defaults to persona (a); the public CRAN packages (`ggRandomForests`,
`temporal_hazard`) default to persona (d).

*Retitled 2026-07-16: this was "HVTI graphics documentation", but the harness
also governs two public CRAN packages whose readers have no HVTI context. See
(d).*

## (a) HVTI/CORR biostatistician — DEFAULT for the recipes book

The CORR biostatistics team adopting the house plotting style.

- **Already knows:** R, ggplot2, survival analysis, the CORR datasets.
- **Wants from a recipe:** all three at once — runnable code to copy, a call on
  which plot to use, and the meaning of a specific argument. They open a recipe
  for any of the three, often in the same sitting.
- **Lands when:** the code runs as written, the argument is shown in context,
  the recipe says when to use the plot, and the figure comes with a reading
  guide.
- **Bounces when:** the recipe opens with a wall of code before saying what the
  plot is for, or shows a figure with no guide on how to read it.
- **Watch for:** the reader hand-rolling a plot in raw ggplot instead of using
  the `hvtiPlotR`/`ggRandomForests` constructor that already makes it. Second,
  drifting off house style by skipping the `hv_*` theme or the two-step S3
  workflow.

## (b) Clinical researcher / surgeon — figure consumer

Clinical researchers and surgeons do not read the book. They receive the
exported figure. Persona (a) is the one who, on their behalf, picks the right
plot and writes or says how to read it. So this is not a prose audience — it is
a constraint on persona (a)'s prose: when writing for the biostatistician,
remember the figure will be handed to a clinician who never saw the recipe. The
recipe should make the figure self-explanatory, so the reading guide carries
over to the person who only sees the plot.

## (c) External R user migrating from SAS — bilingual

Knows both the SAS workflow and R. Anchors: `%kaplan`, `plot.sas`,
PROC LIFETEST/PHREG, the Blackstone-Naftel-Turner additive hazard. The need is
not hand-holding through R; it is confirmation that the R output matches the
SAS original they already trust.

- **Already knows:** the SAS workflow AND R.
- **Wants from a recipe:** confirmation the R output matches the SAS original
  they trust.
- **Lands when:** the recipe ties the R function to the SAS macro it replaces
  and states that the numbers match.
- **Bounces when:** the R version is presented with no bridge to, or no
  reconciliation against, the SAS they know.

## (d) Public CRAN R user — DEFAULT for ggRandomForests / temporal_hazard

Someone who found the package on CRAN or GitHub and is reading `?fn` or a
vignette. No HVTI, no CORR, no access to the internal datasets, and no idea who
we are. They are a peer — often a statistician or a data scientist — but every
piece of shared context personas (a)–(c) rely on is absent.

- **Already knows:** R and ggplot2; random forests in general terms. Often
  `randomForestSRC`. Rarely `varPro`, which is new and thinly documented.
- **Wants from the docs:** what the function returns, what an argument
  actually does, and an example that runs on data they already have.
- **Lands when:** the example runs as written on a stock dataset (`mtcars`,
  `pbc`, `Boston`); the surprising behaviour is named *before* they trip over
  it; and the doc says which function to reach for and on what scale to read
  the result.
- **Bounces when:** the docs assume internal context, cite a dataset they can't
  obtain, or document the happy path and leave the footgun to be discovered
  mid-analysis.
- **Watch for:** *inherited upstream behaviour presented as ours.* Much of what
  surprises this reader originates in `varPro` or `randomForestSRC`, and from
  the outside they cannot tell which package to blame or where to file. Say
  when a behaviour is upstream's, name the upstream function, and give the
  lever that works around it. Second, examples that depend on a fit too
  expensive to run — if it can't be shown cheaply, show the inspection step
  instead of the whole computation.
