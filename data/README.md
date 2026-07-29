# Data

SOEP data is not redistributable and is not included in this repository.

## Access

The German Socio-Economic Panel is free for research use. Apply at
[diw.de/soep](https://www.diw.de/soep). Access is granted under a data
distribution contract, which is why no raw files appear here.

## Required files

Place the following in this directory before running the script:

| File | Contents used |
|---|---|
| `pl.RData` | Big Five items (`plh0212`–`plh0226`, `plh0255`), worry about financial markets (`plh0034`), risk items (`plh0198`, `plh0204_v2`) |
| `hl.csv` | Stock market participation (`hlc0107_v2`) |
| `biobirth.csv` | Birth year and sex |
| `pgen.csv` | Net labour income (`pglabnet`), years of education (`pgbilzeit`) |
| `pwealth.csv` | Net wealth (`w0111a`–`w0111e`) and net debt (`w0011a`–`w0011e`), five multiply-imputed values each |
| `pbrutto.csv` | Household position (`stell_h`), used to identify heads of household |

## Sample construction

Waves 2005, 2009, 2013 and 2017. SOEP codes missing values as negatives, which are
converted to `NA` before any aggregation. The wealth variables are supplied as five
multiple imputations; the script averages across them.

Because the wealth module is not fielded in every wave, wealth and debt for 2005 and
2009 are carried from the 2002 module and for 2013 from 2007. This is noted in the
figures and discussed in the paper.
