#!/usr/bin/env Rscript
# Recover results() statistics from the fitted DDS, never from lfcShrink output.
suppressPackageStartupMessages({library(DESeq2); library(ggplot2); library(jsonlite)})
a <- commandArgs(TRUE)
if (length(a) != 1) stop("Usage: export_stats.R DIFFERENTIAL_STAGE_DIR")
root <- normalizePath(a[1])
state <- fromJSON(file.path(root, "stage.json"), simplifyVector=FALSE)
readtab <- function(p) read.delim(p, check.names=FALSE, quote="", comment.char="", stringsAsFactors=FALSE)
write_tsv <- function(x,p) write.table(x,p,sep="\t",quote=FALSE,row.names=FALSE,na="")
one <- function(paths, what) { if (length(paths)!=1) stop("Expected one ",what,", got ",length(paths)); paths[1] }
allfiles <- list.files(file.path(root,"results"), recursive=TRUE, full.names=TRUE)
out <- file.path(root,"results","original_stats"); dir.create(out,recursive=TRUE,showWarnings=FALSE)
fig <- file.path(root,"results","figures"); dir.create(fig,recursive=TRUE,showWarnings=FALSE)
manifest <- counts <- list()
for (c in state$contrasts) {
  prefix <- paste0(c$id,"_")
  matches <- allfiles[startsWith(basename(allfiles),prefix)]
  ddsfile <- one(matches[grepl("\\.dds\\.rld\\.rds$",matches)],"DDS")
  fullfile <- one(matches[grepl("\\.deseq2\\.results\\.tsv$",matches)],"full DESeq2 results")
  annfile <- one(matches[grepl("_deseq2\\.annotated\\.tsv$",matches)],"annotation")
  dds <- readRDS(ddsfile)
  original <- as.data.frame(results(dds,contrast=c(c$variable,c$target,c$reference),independentFiltering=FALSE))
  if (!all(c("stat","pvalue","log2FoldChange","lfcSE") %in% names(original))) stop("DDS has no Wald statistics")
  stats <- data.frame(gene_id=rownames(original),original,check.names=FALSE)
  path <- file.path(out,paste0(c$id,".stats.tsv")); write_tsv(stats,path)
  full <- readtab(fullfile)
  index <- match(full$gene_id,stats$gene_id)
  if (anyNA(index)) stop("DDS and DE gene IDs differ")
  ok <- is.finite(full$pvalue) & is.finite(stats$pvalue[index])
  # The fitted test p-values must survive shrinkage unchanged.
  if (any(abs(full$pvalue[ok]-stats$pvalue[index][ok]) > 1e-7)) stop("Original contrast differs from saved DE results")
  signed <- ok & is.finite(full$log2FoldChange) & full$log2FoldChange!=0 & stats$log2FoldChange[index]!=0
  if(any(sign(full$log2FoldChange[signed])!=sign(stats$log2FoldChange[index][signed]))) stop("Original contrast direction differs from saved effects")
  z <- stats$stat[index][ok]; pv <- stats$pvalue[index][ok]
  if (any(abs(2*pnorm(-abs(z))-pv)>1e-7)) stop("DDS is not a standard two-sided Wald test")
  full$change <- ifelse(!is.na(full$padj)&full$padj<.05&full$log2FoldChange>=1,"Up",
                       ifelse(!is.na(full$padj)&full$padj<.05&full$log2FoldChange<=-1,"Down","Not significant"))
  n <- table(factor(full$change,levels=c("Down","Not significant","Up")))
  labels <- setNames(paste0(names(n)," (",n,")"),names(n))
  finite <- is.finite(full$log2FoldChange)&is.finite(full$padj)
  v <- full[finite,]; v$y <- -log10(pmax(v$padj,.Machine$double.xmin))
  p <- ggplot(v,aes(log2FoldChange,y,color=change))+geom_point(alpha=.4,size=1.75)+
    geom_hline(yintercept=-log10(.05),linetype=4)+geom_vline(xintercept=c(-1,1),linetype=4)+
    scale_color_manual(values=c(Down="blue",`Not significant`="black",Up="red"),breaks=names(n),labels=labels,drop=FALSE)+
    labs(x="log2 fold change",y="-log10 adjusted p-value",color=NULL)+theme_bw(base_size=20)
  for (ext in c("png","pdf")) ggsave(file.path(fig,paste0(c$id,"_volcano.",ext)),p,width=10,height=7,dpi=300,bg="white")
  manifest[[length(manifest)+1]] <- data.frame(id=c$id,label=paste(c$target,"vs",c$reference),results_tsv=fullfile,annotation_tsv=annfile,stats_tsv=path)
  counts[[length(counts)+1]] <- data.frame(id=c$id,up=unname(n["Up"]),down=unname(n["Down"]),total=sum(n[c("Up","Down")]))
}
write_tsv(do.call(rbind,manifest),file.path(out,"enrichment_manifest.tsv"))
write_tsv(do.call(rbind,counts),file.path(out,"DEG_summary.tsv"))
writeLines(capture.output(sessionInfo()),file.path(out,"sessionInfo.txt"))
writeLines("Wald statistics exported from fitted DDS results(), independentFiltering=FALSE. Shrunken LFC remains in the separate original differential results.",file.path(out,"method.txt"))
