---
title: "Funnel plots for risk-adjusted indicators"
author: "Chris Mainey"
date: "10 April 2019"
output: html_document
---

```{r setup, include=FALSE}
knitr::opts_chunk$set(echo = TRUE)
```

## Funnel plots

This is an implementation of the funnel plot processes, and overdispersion methods described in:<br>
[Statistical methods for healthcare regulation: rating, screening and surveillance. Spiegelhalter et al (2012)](https://rss.onlinelibrary.wiley.com/doi/full/10.1111/j.1467-985X.2011.01010.x)<br>
[Funnel plots for comparing institutional performance. Spiegelhalter (2004)](https://onlinelibrary.wiley.com/doi/10.1002/sim.1970)<br>
[Handeling over-dispersion of performance indicators. Spiegelhalter (2005)](https://qualitysafety.bmj.com/content/14/5/347)<br>
    
It draws funnel plots using `ggplot2` and allows users to specify whether they want 'overdispersed' limits, setting a Winsorisation percentage (default 10%)

There is a variant method for this, used in the NHS' Summary Hospital Mortality Indicator'<br>
[Summary Hospital-level Mortality Indicator, NHS Digital, SHMI specification](https://digital.nhs.uk/data-and-information/publications/ci-hub/summary-hospital-level-mortality-indicator-shmi) <br>

This uses a log-transformation and truncation of the distribution for calculating overdispersion, whereas Spieglehalter's methods use a square-root and Winsorisation.


This package was originally developed for use in CM's PhD project, but published on github in case it's of use for others.


We will load the `medpar` dataset from Hilbe's `COUNT` package.  This is based on 1991 Medicare files for the state of Arizona _(Hilbe, Joseph M (2014), Modeling Count Data, Cambridge University Press Hilbe)_
We will first load the data and build a simple predicitive model using a Poisson GLM.


```{r data, warning=FALSE, message=FALSE}
library(CMFunnels)
library(COUNT)
library(ggplot2)

# lets use the \'medpar\' dataset from the \'COUNT\' package. Little reformatting needed
data(medpar)
medpar$provnum<-factor(medpar$provnum)
medpar$los<-as.numeric(medpar$los)

mod<- glm(los ~ hmo + died + age80 + factor(type), family="poisson", data=medpar)
summary(mod)

```

Now we have a regression that we can use to get a predicted `los` that we will compare to observed `los`:

```{r, prediction}

medpar$prds<- predict(mod, type="response")

```

Make a funnel plot object with normal Poisson limits, and outliers labelled

```{r, funnel1, message=FALSE, fig.align='center', fig.retina=5, collpse=TRUE}

my_plot<-funnel_plot(predictions=medpar$prds,observed=medpar$los, group = medpar$provnum, 
            title = 'Length of Stay Funnel plot for `medpar` data', 
            Poisson_limits = TRUE, OD_Tau2 = FALSE,label_outliers = TRUE)

my_plot[3]
```

<br><br>

Now that looks like too many outliers: or __overdispersion__.
So lets check: <br>
The following ratio should be 1 if our data are conforming to Poisson distribution assumption (conditional mean = variance).  If it is greater than 1, we have overdispersion:

```{r, ODcheck, message=FALSE}

sum(mod$weights * mod$residuals^2)/mod$df.residual

```


This suggest the variance is 6.24 times the condition mean, and definitely overdispersed.
This is a huge topic, but applying overdispersed limits using SHMI or Spieglehalter methods adjust for this:

```{r, funnel2, message=FALSE, fig.align='center', fig.retina=5, collapse=TRUE}

my_plot2<-funnel_plot(predictions=medpar$prds,observed=medpar$los, group = medpar$provnum, 
            title = 'Length of Stay Funnel plot for `medpar` data', 
            Poisson_limits = FALSE, OD_Tau2 = TRUE, method = "SHMI",label_outliers = TRUE)

my_plot2[3]
```

<br><br>
These methods can be used for any similar indicators, e.g. standardised mortality ratios, readmissions etc.

__Please read the package documentation for more info__
