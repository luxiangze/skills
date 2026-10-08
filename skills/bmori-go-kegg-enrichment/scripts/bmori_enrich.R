#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
script_arg <- grep("^--file=", commandArgs(), value = TRUE)
script_path <- normalizePath(sub("^--file=", "", script_arg[[1]]))
skill_root <- normalizePath(file.path(dirname(script_path), ".."))
source(file.path(dirname(script_path), "plot_helpers.R"))

show_help <- function() {
  cat(paste(
    "Usage:",
    "  bmori_enrich.R --mode deseq2|gene-list --manifest FILE --outdir DIR [options]",
    "  bmori_enrich.R --redraw-existing --results-root DIR --figures-root DIR",
    "Options: --alpha 0.05 --lfc 1 --min-gs-size 10 --max-gs-size 500 --kegg-snapshot DIR",
    "DESeq2 manifest: contrast_id, label, results_tsv, annotation_tsv, optional filtered_tsv.",
    "Gene-list manifest: contrast_id, label, gene_set, genes_tsv, background_tsv, optional geneid_column.",
    sep = "\n"))
}

parse_args <- function(x) {
  if (any(x %in% c("-h", "--help")) || length(x) == 0L) { show_help(); quit(status = 0L) }
  out <- list()
  i <- 1L
  while (i <= length(x)) {
    key <- x[[i]]
    if (!startsWith(key, "--")) stop("Unexpected argument: ", key)
    if (key == "--redraw-existing") { out$redraw_existing <- TRUE; i <- i + 1L; next }
    if (i == length(x)) stop("Missing value for ", key)
    out[[sub("^--", "", key)]] <- x[[i + 1L]]
    i <- i + 2L
  }
  out
}

opt <- parse_args(args)
read_tsv <- function(path) read.delim(path, sep = "\t", quote = "", comment.char = "",
                                      check.names = FALSE, stringsAsFactors = FALSE,
                                      na.strings = c("", "NA"))
write_tsv <- function(x, path) write.table(x, path, sep = "\t", quote = FALSE,
                                             row.names = FALSE, na = "")
resolve_path <- function(x, manifest_dir) {
  if (is.na(x) || !nzchar(x)) return(NA_character_)
  if (grepl("^/", x)) x else file.path(manifest_dir, x)
}
normalize_gene_id <- function(x) {
  x <- trimws(as.character(x))
  x <- sub("\\.0$", "", x)
  x[is.na(x) | !nzchar(x)] <- NA_character_
  x
}
extract_ncbi_geneid <- function(x) {
  x <- as.character(x)
  has_id <- !is.na(x) & grepl("GeneID:[0-9]+", x, perl = TRUE)
  out <- rep(NA_character_, length(x))
  out[has_id] <- sub("^.*GeneID:([0-9]+).*$", "\\1", x[has_id], perl = TRUE)
  out
}
read_ids <- function(path, col = NULL) {
  tab <- read_tsv(path)
  if (ncol(tab) == 0L) stop("No columns in gene list: ", path)
  if (is.null(col) || is.na(col) || !nzchar(col)) col <- if ("GeneID" %in% names(tab)) "GeneID" else names(tab)[1]
  if (!col %in% names(tab)) stop("ID column '", col, "' not found in ", path)
  unique(na.omit(normalize_gene_id(tab[[col]])))
}

if (isTRUE(opt$redraw_existing)) {
  if (is.null(opt$`results-root`) || is.null(opt$`figures-root`)) stop("--redraw-existing requires --results-root and --figures-root")
  result_root <- normalizePath(opt$`results-root`)
  figure_root <- opt$`figures-root`
  summary <- read_tsv(file.path(result_root, "summary.tsv"))
  for (i in seq_len(nrow(summary))) {
    row <- summary[i, , drop = FALSE]
    id <- row$contrast[[1]]; set <- row$gene_set[[1]]; label <- row$contrast_label[[1]]
    tab_dir <- file.path(result_root, id, set)
    fig_dir <- file.path(figure_root, id, set)
    go <- read_tsv(file.path(tab_dir, "go_significant.tsv"))
    if (nrow(go)) {
      go <- do.call(rbind, lapply(split(go, go$ONTOLOGY), function(z) {
        z[order(z$p.adjust, z$pvalue, -z$Count), , drop = FALSE][seq_len(min(10L, nrow(z))), , drop = FALSE]
      }))
    }
    save_enrichment_dotplot(go, "GO", paste(label, set, "GO", sep = " | "),
                            file.path(fig_dir, "go_dotplot.png"), file.path(fig_dir, "go_dotplot.pdf"), 30L)
    kegg <- read_tsv(file.path(tab_dir, "kegg_significant.tsv"))
    save_enrichment_dotplot(kegg, "KEGG", paste(label, set, "KEGG", sep = " | "),
                            file.path(fig_dir, "kegg_dotplot.png"), file.path(fig_dir, "kegg_dotplot.pdf"), 20L)

    full_kegg <- read_tsv(file.path(tab_dir, "kegg_enrichment.tsv"))
    sensitivity <- file.path(result_root, "threshold_sensitivity")
    variants <- list(
      list(id = "bh_padj_0.10", label = "BH-adjusted p < 0.10", name = "kegg_padj_lt_0.10.tsv",
           png = "kegg_dotplot_padj_lt_0.10.png", pdf = "kegg_dotplot_padj_lt_0.10.pdf",
           keep = function(x) !is.na(x$p.adjust) & x$p.adjust < 0.10),
      list(id = "nominal_p_0.05", label = "Nominal p < 0.05 (exploratory; not FDR-controlled)", name = "kegg_nominal_p_lt_0.05.tsv",
           png = "kegg_dotplot_nominal_p_lt_0.05.png", pdf = "kegg_dotplot_nominal_p_lt_0.05.pdf",
           keep = function(x) !is.na(x$pvalue) & x$pvalue < 0.05)
    )
    for (v in variants) {
      table_dir <- file.path(sensitivity, v$id, id, set)
      if (!dir.exists(table_dir)) next
      tab_path <- file.path(table_dir, v$name)
      if (file.exists(tab_path)) kegg_v <- read_tsv(tab_path) else kegg_v <- full_kegg[v$keep(full_kegg), , drop = FALSE]
      out_dir <- file.path(figure_root, "threshold_sensitivity", v$id, id, set)
      save_enrichment_dotplot(kegg_v, "KEGG", paste(label, set, v$label, sep = " | "),
                              file.path(out_dir, v$png), file.path(out_dir, v$pdf), 20L)
    }
  }
  message("Redrew saved enrichment figures under ", figure_root)
  quit(status = 0L)
}

required_opts <- c("mode", "manifest", "outdir")
if (!all(required_opts %in% names(opt))) stop("Required options: --mode, --manifest, --outdir")
mode <- opt$mode
if (!mode %in% c("deseq2", "gene-list")) stop("--mode must be deseq2 or gene-list")
alpha <- as.numeric(opt$alpha %||% "0.05")
lfc_cutoff <- as.numeric(opt$lfc %||% "1")
min_gs_size <- as.integer(opt$`min-gs-size` %||% "10")
max_gs_size <- as.integer(opt$`max-gs-size` %||% "500")
manifest_path <- normalizePath(opt$manifest)
manifest_dir <- dirname(manifest_path)
out_root <- opt$outdir
dir.create(out_root, recursive = TRUE, showWarnings = FALSE)
kegg_dir <- opt$`kegg-snapshot` %||% file.path(skill_root, "assets/kegg_bmor_20260924")

suppressPackageStartupMessages({
  library(AnnotationDbi)
  library(clusterProfiler)
  library(GO.db)
  library(org.Bmori.eg.db)
})

org_go <- AnnotationDbi::select(org.Bmori.eg.db,
  keys = AnnotationDbi::keys(org.Bmori.eg.db, keytype = "GID"), keytype = "GID",
  columns = c("GO", "ONTOLOGY"))
org_go$GID <- normalize_gene_id(org_go$GID)
org_go$GO <- as.character(org_go$GO)
org_go$ONTOLOGY <- as.character(org_go$ONTOLOGY)
org_go <- unique(org_go[grepl("^GO:[0-9]{7}$", org_go$GO) & org_go$ONTOLOGY %in% c("BP", "MF", "CC") & !is.na(org_go$GID), c("GID", "GO", "ONTOLOGY")])
ancestor_by_ontology <- list(BP = as.list(GO.db::GOBPANCESTOR), MF = as.list(GO.db::GOMFANCESTOR), CC = as.list(GO.db::GOCCANCESTOR))
expanded <- lapply(names(ancestor_by_ontology), function(ont) {
  direct <- org_go[org_go$ONTOLOGY == ont, c("GID", "GO"), drop = FALSE]
  genes_by_term <- split(direct$GID, direct$GO)
  ancestors <- ancestor_by_ontology[[ont]]
  rows <- lapply(names(genes_by_term), function(goid) {
    terms <- unique(c(goid, ancestors[[goid]])); terms <- terms[grepl("^GO:[0-9]{7}$", terms)]
    genes <- unique(genes_by_term[[goid]])
    data.frame(term = rep(terms, each = length(genes)), gene = rep(genes, times = length(terms)), ONTOLOGY = ont)
  })
  do.call(rbind, rows)
})
go_pairs <- unique(do.call(rbind, expanded))
go_names <- AnnotationDbi::select(GO.db, keys = unique(go_pairs$term), keytype = "GOID", columns = c("TERM", "ONTOLOGY"))
go_names <- unique(go_names[!is.na(go_names$TERM) & go_names$ONTOLOGY %in% c("BP", "MF", "CC"), c("GOID", "TERM", "ONTOLOGY")])
go_pairs <- merge(go_pairs, go_names, by.x = c("term", "ONTOLOGY"), by.y = c("GOID", "ONTOLOGY"))
go_term2gene <- unique(go_pairs[, c("term", "gene")])
go_term2name <- unique(data.frame(term = go_names$GOID, name = go_names$TERM))
go_term_ontology <- unique(go_pairs[, c("term", "ONTOLOGY")])

read_kegg_pairs <- function(path) read.delim(path, header = FALSE, sep = "\t", quote = "",
  check.names = FALSE, stringsAsFactors = FALSE)
conv <- read_kegg_pairs(file.path(kegg_dir, "conv_ncbi_geneid.txt"))
link <- read_kegg_pairs(file.path(kegg_dir, "link_pathway.txt"))
pathway_names <- read_kegg_pairs(file.path(kegg_dir, "list_pathway.txt"))
conv_a <- as.character(conv[[1]]); conv_b <- as.character(conv[[2]])
kegg_raw <- ifelse(grepl("^bmor:", conv_a), conv_a, conv_b)
ncbi_raw <- ifelse(grepl("^ncbi-geneid:", conv_a), conv_a, conv_b)
conv_gene <- unique(data.frame(kegg_gene = sub("^bmor:", "", kegg_raw), gene = normalize_gene_id(sub("^ncbi-geneid:", "", ncbi_raw))))
conv_gene <- conv_gene[grepl("^bmor:", kegg_raw) & grepl("^ncbi-geneid:", ncbi_raw), , drop = FALSE]
link_a <- as.character(link[[1]]); link_b <- as.character(link[[2]])
link_gene_raw <- ifelse(grepl("^bmor:", link_a), link_a, link_b)
link_path_raw <- ifelse(grepl("^path:", link_a), link_a, link_b)
links <- unique(data.frame(kegg_gene = sub("^bmor:", "", link_gene_raw), term = sub("^path:", "", link_path_raw)))
links <- links[grepl("^bmor:", link_gene_raw) & grepl("^path:", link_path_raw), , drop = FALSE]
kegg_term2gene <- unique(merge(links, conv_gene, by = "kegg_gene")[, c("term", "gene")])
if (!nrow(kegg_term2gene)) stop("KEGG snapshot did not produce any NCBI GeneID mappings")
path_a <- as.character(pathway_names[[1]]); path_b <- as.character(pathway_names[[2]])
kegg_term2name <- unique(data.frame(term = sub("^path:", "", path_a), name = sub(" - Bombyx mori.*$", "", path_b)))

empty_enrichment <- function() data.frame(ID=character(), Description=character(), GeneRatio=character(), BgRatio=character(), pvalue=numeric(), p.adjust=numeric(), qvalue=numeric(), geneID=character(), Count=integer())
run_enrich <- function(query, universe, t2g, t2n) {
  if (!length(query) || !nrow(t2g)) return(NULL)
  clusterProfiler::enricher(gene = unique(query), universe = unique(universe), TERM2GENE = t2g, TERM2NAME = t2n,
    pAdjustMethod = "BH", pvalueCutoff = 1, qvalueCutoff = 1, minGSSize = min_gs_size, maxGSSize = max_gs_size)
}
as_table <- function(x) {
  if (is.null(x)) return(empty_enrichment())
  tab <- as.data.frame(x)
  if (!nrow(tab)) return(empty_enrichment())
  tab$RichFactor <- vapply(strsplit(tab$GeneRatio, "/", fixed=TRUE), function(z) as.numeric(z[1])/as.numeric(z[2]), numeric(1)) /
    vapply(strsplit(tab$BgRatio, "/", fixed=TRUE), function(z) as.numeric(z[1])/as.numeric(z[2]), numeric(1))
  tab
}
all_summary <- list()
manifest <- read_tsv(manifest_path)
if (mode == "deseq2") {
  needed <- c("contrast_id", "label", "results_tsv", "annotation_tsv")
  if (!all(needed %in% names(manifest))) stop("DESeq2 manifest requires: ", paste(needed, collapse = ", "))
  worksets <- list()
  for (i in seq_len(nrow(manifest))) {
    m <- manifest[i, , drop=FALSE]
    full <- read_tsv(resolve_path(m$results_tsv, manifest_dir))
    annotation <- read_tsv(resolve_path(m$annotation_tsv, manifest_dir))
    if (!all(c("gene_id", "log2FoldChange", "padj") %in% names(full))) stop("DESeq2 result columns missing for ", m$contrast_id)
    if (!all(c("gene_id", "db_xref") %in% names(annotation))) stop("Annotation requires gene_id and db_xref for ", m$contrast_id)
    ann <- data.frame(gene_id=as.character(annotation$gene_id), GeneID=extract_ncbi_geneid(annotation$db_xref))
    ann <- ann[!duplicated(ann$gene_id), , drop=FALSE]
    id_map <- setNames(ann$GeneID, ann$gene_id)
    full$GeneID <- normalize_gene_id(unname(id_map[as.character(full$gene_id)]))
    sig <- full[!is.na(full$padj) & full$padj < alpha & !is.na(full$log2FoldChange) & abs(full$log2FoldChange) >= lfc_cutoff, , drop=FALSE]
    if ("filtered_tsv" %in% names(manifest) && !is.na(m$filtered_tsv) && nzchar(m$filtered_tsv)) {
      supplied <- read_tsv(resolve_path(m$filtered_tsv, manifest_dir))
      if (!setequal(as.character(sig$gene_id), as.character(supplied$gene_id))) stop("Filtered table disagrees with thresholds for ", m$contrast_id)
    }
    sig$direction <- ifelse(sig$log2FoldChange > 0, "up", "down")
    worksets[[length(worksets)+1L]] <- list(contrast_id=m$contrast_id, label=m$label,
      background=unique(na.omit(full$GeneID)), sets=list(all=sig, up=sig[sig$log2FoldChange>0,,drop=FALSE], down=sig[sig$log2FoldChange<0,,drop=FALSE]))
  }
} else {
  needed <- c("contrast_id", "label", "gene_set", "genes_tsv", "background_tsv")
  if (!all(needed %in% names(manifest))) stop("Gene-list manifest requires: ", paste(needed, collapse = ", "))
  worksets <- lapply(seq_len(nrow(manifest)), function(i) {
    m <- manifest[i,,drop=FALSE]
    id_col <- if ("geneid_column" %in% names(manifest)) as.character(m$geneid_column) else "GeneID"
    list(contrast_id=m$contrast_id, label=m$label,
      background=read_ids(resolve_path(m$background_tsv, manifest_dir), id_col),
      sets=setNames(list(data.frame(GeneID=read_ids(resolve_path(m$genes_tsv, manifest_dir), id_col))), as.character(m$gene_set)))
  })
}

for (entry in worksets) {
  if (!grepl("^[A-Za-z0-9._-]+$", entry$contrast_id)) stop("contrast_id must be filesystem-safe: ", entry$contrast_id)
  for (set_name in names(entry$sets)) {
    if (!grepl("^[A-Za-z0-9._-]+$", set_name)) stop("gene_set must be filesystem-safe: ", set_name)
    set <- entry$sets[[set_name]]
    if (mode == "deseq2") {
      query_ids <- unique(na.omit(as.character(set$GeneID)))
      query_table <- data.frame(gene_id=set$gene_id, GeneID=set$GeneID,
        log2FoldChange=set$log2FoldChange, padj=set$padj,
        direction=if (set_name == "all") set$direction else set_name)
    } else {
      query_ids <- unique(na.omit(normalize_gene_id(set$GeneID)))
      query_table <- data.frame(GeneID=query_ids, gene_set=set_name)
    }
    background <- unique(na.omit(normalize_gene_id(entry$background)))
    if (!length(background)) stop("No mapped background IDs for ", entry$contrast_id)
    query_ids <- intersect(query_ids, background)
    go_universe <- intersect(background, unique(go_term2gene$gene))
    kegg_universe <- intersect(background, unique(kegg_term2gene$gene))
    go_query <- intersect(query_ids, go_universe)
    kegg_query <- intersect(query_ids, kegg_universe)
    table_dir <- file.path(out_root, entry$contrast_id, set_name)
    figure_dir <- file.path(dirname(out_root), "figures", basename(out_root), entry$contrast_id, set_name)
    dir.create(table_dir, recursive=TRUE, showWarnings=FALSE); dir.create(figure_dir, recursive=TRUE, showWarnings=FALSE)
    write_tsv(query_table, file.path(table_dir, "input_genes.tsv"))

    go <- as_table(run_enrich(go_query, go_universe, go_term2gene, go_term2name))
    if (nrow(go)) go$ONTOLOGY <- go_term_ontology$ONTOLOGY[match(go$ID, go_term_ontology$term)] else go$ONTOLOGY <- character()
    go_sig <- go[!is.na(go$p.adjust) & go$p.adjust < alpha, , drop=FALSE]
    write_tsv(go, file.path(table_dir,"go_enrichment.tsv")); write_tsv(go_sig,file.path(table_dir,"go_significant.tsv"))
    go_plot <- go_sig
    if (nrow(go_plot)) go_plot <- do.call(rbind, lapply(split(go_plot, go_plot$ONTOLOGY), function(z) z[order(z$p.adjust,z$pvalue,-z$Count),,drop=FALSE][seq_len(min(10L,nrow(z))),,drop=FALSE]))
    save_enrichment_dotplot(go_plot,"GO",paste(entry$label,set_name,"GO",sep=" | "),file.path(figure_dir,"go_dotplot.png"),file.path(figure_dir,"go_dotplot.pdf"),30L,alpha)

    kegg <- as_table(run_enrich(kegg_query, kegg_universe, kegg_term2gene, kegg_term2name))
    kegg_sig <- kegg[!is.na(kegg$p.adjust) & kegg$p.adjust < alpha,,drop=FALSE]
    write_tsv(kegg,file.path(table_dir,"kegg_enrichment.tsv")); write_tsv(kegg_sig,file.path(table_dir,"kegg_significant.tsv"))
    kegg_sig <- kegg_sig[order(kegg_sig$p.adjust,kegg_sig$pvalue,-kegg_sig$Count),,drop=FALSE]
    save_enrichment_dotplot(kegg_sig,"KEGG",paste(entry$label,set_name,"KEGG",sep=" | "),file.path(figure_dir,"kegg_dotplot.png"),file.path(figure_dir,"kegg_dotplot.pdf"),20L,alpha)
    for (variant in c("bh_padj_0.10","nominal_p_0.05")) {
      selected <- if (variant == "bh_padj_0.10") kegg[!is.na(kegg$p.adjust)&kegg$p.adjust<0.10,,drop=FALSE] else kegg[!is.na(kegg$pvalue)&kegg$pvalue<0.05,,drop=FALSE]
      selected <- selected[order(selected$p.adjust,selected$pvalue,-selected$Count),,drop=FALSE]
      sens_table <- file.path(out_root,"threshold_sensitivity",variant,entry$contrast_id,set_name)
      sens_figure <- file.path(dirname(out_root),"figures",basename(out_root),"threshold_sensitivity",variant,entry$contrast_id,set_name)
      dir.create(sens_table,recursive=TRUE,showWarnings=FALSE); dir.create(sens_figure,recursive=TRUE,showWarnings=FALSE)
      nm <- if (variant == "bh_padj_0.10") "kegg_padj_lt_0.10.tsv" else "kegg_nominal_p_lt_0.05.tsv"
      pn <- if (variant == "bh_padj_0.10") "kegg_dotplot_padj_lt_0.10.png" else "kegg_dotplot_nominal_p_lt_0.05.png"
      pf <- sub("\\.png$", ".pdf", pn)
      write_tsv(selected,file.path(sens_table,nm))
      cap <- if (variant == "bh_padj_0.10") "BH-adjusted p < 0.10" else "Nominal p < 0.05 (exploratory; not FDR-controlled)"
      save_enrichment_dotplot(selected,"KEGG",paste(entry$label,set_name,cap,sep=" | "),file.path(sens_figure,pn),file.path(sens_figure,pf),20L,alpha)
    }
    all_summary[[length(all_summary)+1L]] <- data.frame(contrast_id=entry$contrast_id,label=entry$label,gene_set=set_name,
      query_input=length(if(mode=="deseq2") unique(na.omit(set$GeneID)) else unique(na.omit(set$GeneID))),
      query_in_background=length(query_ids),background_geneids=length(background),go_background=length(go_universe),kegg_background=length(kegg_universe),
      go_mapped_query=length(go_query),kegg_mapped_query=length(kegg_query),go_tested_terms=nrow(go),kegg_tested_terms=nrow(kegg),
      go_significant=sum(!is.na(go$p.adjust)&go$p.adjust<alpha),kegg_significant=sum(!is.na(kegg$p.adjust)&kegg$p.adjust<alpha),
      kegg_bh_0.10=sum(!is.na(kegg$p.adjust)&kegg$p.adjust<0.10),kegg_nominal_0.05=sum(!is.na(kegg$pvalue)&kegg$pvalue<0.05))
    message(entry$contrast_id,"/",set_name,": query ",length(query_ids),"; GO sig ",sum(!is.na(go$p.adjust)&go$p.adjust<alpha),"; KEGG sig ",sum(!is.na(kegg$p.adjust)&kegg$p.adjust<alpha))
  }
}
summary <- do.call(rbind,all_summary)
write_tsv(summary,file.path(out_root,"summary.tsv"))
kegg_info <- readLines(file.path(kegg_dir,"README.txt"),warn=FALSE)
writeLines(c(paste("Mode:",mode),paste("Generated:",format(Sys.time(),"%Y-%m-%d %H:%M:%S %Z")),
  paste("R:",R.version.string),paste("clusterProfiler:",packageVersion("clusterProfiler")),
  paste("OrgDb:",packageVersion("org.Bmori.eg.db")),"GO: direct OrgDb GO annotations expanded with GO.db ancestors; OrgDb GOALL is empty.",
  paste("Thresholds: BH <",alpha,"; gene set sizes",min_gs_size,"to",max_gs_size),paste("KEGG snapshot:",paste(kegg_info,collapse=" | "))),
  con=file.path(out_root,"analysis_metadata.txt"))
capture.output(sessionInfo(),file=file.path(out_root,"sessionInfo.txt"))
message("Analysis complete: ",normalizePath(out_root))
