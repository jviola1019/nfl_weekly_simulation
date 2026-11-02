# Each contract's traded volume over the 48 hours before kickoff, summed from the raw hourly candles that
# reports/2026-10-28/feasibility/kalshi_candles.R saved (its <out_dir>/raw/). Run from the repository root:
#   Rscript reports/2026-10-29/hypotheses/kalshi_candle_volume.R <out_csv.gz> <raw_dir> [<raw_dir> ...]
suppressPackageStartupMessages(library(data.table))
args <- commandArgs(trailingOnly = TRUE); out <- args[1]; dirs <- args[-1]
files <- list.files(dirs, pattern = "^candles_[0-9]+\\.json\\.gz$", full.names = TRUE)
num <- function(v) suppressWarnings(as.numeric(v))
vol <- rbindlist(lapply(files, function(f) {
  j <- jsonlite::fromJSON(gzfile(f), simplifyVector = TRUE)$markets
  if (!NROW(j)) return(NULL)
  rbindlist(lapply(seq_len(NROW(j)), function(i) {
    cs <- j$candlesticks[[i]]
    data.table(ticker = j$market_ticker[i], candles = NROW(cs), volume_48h = if (NROW(cs)) sum(num(cs$volume_fp), na.rm = TRUE) else 0)
  }))
}))
vol <- vol[, .(candles = sum(candles), volume_48h = sum(volume_48h)), by = ticker]
fwrite(vol, out)
cat(sprintf("files %d; contracts %d; median 48 h volume %.0f contracts\n", length(files), nrow(vol), stats::median(vol$volume_48h)))
