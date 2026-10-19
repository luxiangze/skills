#!/usr/bin/env Rscript
suppressPackageStartupMessages({library(clusterProfiler);library(enrichplot);library(ggplot2);library(jsonlite);library(BiocParallel)})
a <- commandArgs(TRUE)
if(length(a)!=3) stop("Usage: enrich.R manifest.tsv annotation.json ENRICH_STAGE_DIR")
readtab <- function(p) read.delim(p,check.names=FALSE,quote="",comment.char="",stringsAsFactors=FALSE,na.strings=c("","NA"))
write_tsv <- function(x,p) write.table(x,p,sep="\t",quote=FALSE,row.names=FALSE,na="")
manifest <- readtab(a[1]); cfg <- fromJSON(a[2]); root <- normalizePath(a[3]); dir.create(file.path(root,"results"),showWarnings=FALSE)
alpha <- .05; min_size <- 10L; max_size <- 500L; seed <- 20261019L
norm <- function(x) sub("\\.0$","",as.character(x))
empty_ora <- function() data.frame(ID=character(),Description=character(),GeneRatio=character(),BgRatio=character(),pvalue=numeric(),p.adjust=numeric(),qvalue=numeric(),geneID=character(),Count=integer())
empty_gsea <- function() data.frame(ID=character(),Description=character(),setSize=integer(),enrichmentScore=numeric(),NES=numeric(),pvalue=numeric(),p.adjust=numeric(),qvalue=numeric(),rank=integer(),leading_edge=character(),core_enrichment=character())
dbs <- list(GO=list(tg=readtab(cfg$go_term2gene),tn=readtab(cfg$go_term2name)),KEGG=list(tg=readtab(cfg$kegg_term2gene),tn=readtab(cfg$kegg_term2name)))
for (kind in names(dbs)) {
 d <- dbs[[kind]]
 if(!all(c("term","gene") %in% names(d$tg))||!all(c("term","name") %in% names(d$tn))) stop("Mapping table schema error")
 d$tg <- unique(data.frame(term=as.character(d$tg$term),gene=norm(d$tg$gene)))
 if(anyNA(d$tg)||any(!nzchar(d$tg$gene))||any(!nzchar(d$tg$term))) stop("Empty identifiers in mapping")
 if(anyDuplicated(d$tn$term)) stop("Multiple names for one term")
 if(kind=="GO" && (!"ontology" %in% names(d$tn)||any(!d$tn$ontology %in% c("BP","MF","CC")))) stop("GO names need BP/MF/CC ontology")
 if(!all(d$tg$term %in% d$tn$term)) stop("TERM2GENE has terms without TERM2NAME")
 dbs[[kind]] <- d
}
saveplot <- function(p,stem,n=0) {
 h <- max(3.5,1.8+.48*n)
 ggsave(paste0(stem,".png"),p,width=12,height=h,dpi=300,limitsize=FALSE,bg="white")
 ggsave(paste0(stem,".pdf"),p,width=12,height=h,limitsize=FALSE,bg="white")
}
dot <- function(tab,kind,stem,gsea=FALSE) {
 if(!nrow(tab)) {
  p<-ggplot()+annotate("text",x=.5,y=.5,label="No terms passed BH adjusted p < 0.05",size=6)+theme_void(base_size=20)
  saveplot(p,stem);return(invisible(NULL))
 }
 tab<-tab[order(tab$p.adjust,tab$pvalue),,drop=FALSE]
 if(kind=="GO")tab<-do.call(rbind,lapply(split(tab,tab$ontology),function(z)head(z,10))) else tab<-head(tab,20)
 tab$label<-vapply(tab$Description,function(s)paste(strwrap(s,width=48),collapse="\n"),character(1))
 if(anyDuplicated(tab$label))tab$label<-paste0(tab$label," [",tab$ID,"]")
 tab$label<-factor(tab$label,levels=rev(unique(tab$label)))
 if(gsea) {
  p<-ggplot(tab,aes(NES,label,size=setSize,color=p.adjust))+geom_vline(xintercept=0,linetype=4)
 } else {
  tab$ratio<-vapply(strsplit(tab$GeneRatio,"/",fixed=TRUE),function(x)as.numeric(x[1])/as.numeric(x[2]),numeric(1))
  p<-ggplot(tab,aes(ratio,label,size=Count,color=p.adjust))
 }
 p<-p+geom_point(alpha=.9)+scale_color_gradient(low="#B2182B",high="#2166AC",name="BH adjusted p")+
  scale_size_continuous(range=c(3,10))+labs(x=if(gsea)"Normalized enrichment score" else "Gene ratio",y=NULL)+
  theme_bw(base_size=20)+theme(panel.grid.minor=element_blank())
 if(kind=="GO")p<-p+facet_grid(ontology~.,scales="free_y",space="free_y")
 saveplot(p,stem,nrow(tab))
}
addont <- function(tab,kind,d) {
 if(kind=="GO")tab$ontology<-d$tn$ontology[match(tab$ID,d$tn$term)]
 tab
}
summaries<-list(); mapping_rows<-list()
for(i in seq_len(nrow(manifest))) {
 m<-manifest[i,]; full<-readtab(m$results_tsv); ann<-readtab(m$annotation_tsv); raw<-readtab(m$stats_tsv)
 if(!all(c("gene_id","log2FoldChange","padj") %in% names(full))||!all(c("gene_id","stat","pvalue") %in% names(raw)))stop("Missing DE columns")
 if(anyDuplicated(full$gene_id)||anyDuplicated(ann$gene_id)||anyDuplicated(raw$gene_id))stop("Nonunique source gene IDs")
 if(!all(full$gene_id %in% raw$gene_id)||!all(full$gene_id %in% ann$gene_id))stop("DE, DDS and annotation gene sets differ")
 if(!is.null(cfg$id_map)) {
  idmap<-readtab(cfg$id_map)
  if(!all(c("gene_id","annotation_id") %in% names(idmap))||anyDuplicated(idmap$gene_id))stop("Invalid explicit ID map")
  id<-idmap$annotation_id[match(full$gene_id,idmap$gene_id)]
 } else if(!is.null(cfg$id_column)) {
  if(!cfg$id_column %in% names(ann))stop("Annotation id_column missing")
  id<-ann[[cfg$id_column]][match(full$gene_id,ann$gene_id)]
 } else {
  if(cfg$id_type!="ncbi_geneid"||!"db_xref" %in% names(ann))stop("Provide id_map or id_column for this identifier namespace")
  x<-ann$db_xref[match(full$gene_id,ann$gene_id)]
  id<-ifelse(!is.na(x)&grepl("GeneID:[0-9]+",x),sub("^.*GeneID:([0-9]+).*$","\\1",x),NA_character_)
 }
 id<-norm(id); id[is.na(id)|!nzchar(id)]<-NA_character_
 rawindex<-match(full$gene_id,raw$gene_id)
 full$annotation_id<-id; full$stat<-raw$stat[rawindex];full$test_pvalue<-raw$pvalue[rawindex]
 tested<-is.finite(full$test_pvalue)&is.finite(full$stat)
 write_tsv(full,file.path(root,"results",paste0(m$id,"_mapped_input.tsv")))
 for(kind in names(dbs)) {
  d<-dbs[[kind]]; background<-unique(na.omit(id[tested])); annotated_bg<-intersect(background,d$tg$gene)
  mapping_rows[[length(mapping_rows)+1]]<-data.frame(id=m$id,database=kind,result_genes=nrow(full),tested_genes=sum(tested),
   mapped_tested_genes=sum(tested&!is.na(id)),unique_background=length(background),annotated_background=length(annotated_bg),
   annotation_coverage=if(length(background))length(annotated_bg)/length(background) else NA_real_)
  if(!length(annotated_bg))stop("No annotated tested genes; check identifier namespace")
  for(direction in c("all","up","down")) {
   sig<-tested&!is.na(full$padj)&full$padj<alpha&abs(full$log2FoldChange)>=1
   if(direction=="up")sig<-sig&full$log2FoldChange>=1
   if(direction=="down")sig<-sig&full$log2FoldChange<=-1
   query<-unique(na.omit(id[sig])); od<-file.path(root,"results",m$id,direction);dir.create(od,recursive=TRUE,showWarnings=FALSE)
   ans<-if(length(query))enricher(query,universe=background,TERM2GENE=d$tg,TERM2NAME=d$tn[,c("term","name")],
     minGSSize=min_size,maxGSSize=max_size,pvalueCutoff=1,qvalueCutoff=1,pAdjustMethod="BH") else NULL
   # @result retains the entire test family; as.data.frame() applies p/q cutoffs.
   tab<-if(is.null(ans))empty_ora() else as.data.frame(ans@result)
   tab<-addont(tab,kind,d);keep<-tab[!is.na(tab$p.adjust)&tab$p.adjust<alpha,,drop=FALSE]
   write_tsv(tab,file.path(od,paste0(tolower(kind),"_all.tsv")));write_tsv(keep,file.path(od,paste0(tolower(kind),"_significant.tsv")))
   dot(keep,kind,file.path(od,paste0(tolower(kind),"_dotplot")))
   write_tsv(data.frame(annotation_id=query),file.path(od,paste0(tolower(kind),"_query.tsv")))
   write_tsv(data.frame(annotation_id=annotated_bg),file.path(od,paste0(tolower(kind),"_background.tsv")))
   summaries[[length(summaries)+1]]<-data.frame(id=m$id,database=kind,method="ORA",direction=direction,query_ids=length(query),
     annotated_query_ids=length(intersect(query,d$tg$gene)),tested_terms=nrow(tab),significant=nrow(keep),positive=NA_integer_,negative=NA_integer_)
  }
  ranked<-full[tested&!is.na(id),c("gene_id","annotation_id","stat","padj")]
  ranked<-ranked[order(-abs(ranked$stat),ranked$gene_id),];ranked<-ranked[!duplicated(ranked$annotation_id),]
  ranked<-ranked[order(-ranked$stat,ranked$annotation_id),]; scores<-setNames(ranked$stat,ranked$annotation_id)
  if(sum(scores>0)<1||sum(scores<0)<1)stop("GSEA needs both positive and negative original statistics")
  # Stable lexical tie order; report exact ties, keep original numeric statistics.
  od<-file.path(root,"results",m$id,"gsea");dir.create(od,recursive=TRUE,showWarnings=FALSE)
  write_tsv(ranked,file.path(od,paste0(tolower(kind),"_ranked_genes.tsv")))
  set.seed(seed)
  sizes<-table(d$tg$term[d$tg$gene %in% names(scores)])
  ans<-if(any(sizes>=min_size&sizes<=max_size))GSEA(scores,TERM2GENE=d$tg,TERM2NAME=d$tn[,c("term","name")],minGSSize=min_size,maxGSSize=max_size,
   pvalueCutoff=1,pAdjustMethod="BH",eps=0,nPermSimple=10000,seed=TRUE,verbose=FALSE,by="fgsea",BPPARAM=SerialParam()) else NULL
  tab<-if(is.null(ans))empty_gsea() else as.data.frame(ans@result)
  tab<-addont(tab,kind,d);keep<-tab[!is.na(tab$p.adjust)&tab$p.adjust<alpha,,drop=FALSE]
  write_tsv(tab,file.path(od,paste0(tolower(kind),"_all.tsv")));write_tsv(keep,file.path(od,paste0(tolower(kind),"_significant.tsv")))
  dot(keep,kind,file.path(od,paste0(tolower(kind),"_dotplot")),TRUE)
  if(nrow(keep)) {
   chosen<-head(keep$ID[order(keep$p.adjust)],3)
   curve_info<-keep[match(chosen,keep$ID),c("ID","Description","NES","p.adjust"),drop=FALSE]
   curve_info$png<-paste0(tolower(kind),"_curve_",seq_along(chosen),".png")
   curve_info$pdf_page<-seq_along(chosen)
   write_tsv(curve_info,file.path(od,paste0(tolower(kind),"_curve_manifest.tsv")))
   pdf(file.path(od,paste0(tolower(kind),"_curves.pdf")),width=11,height=9)
   for(j in seq_along(chosen)) {
    p<-gseaplot2(ans,geneSetID=chosen[j],title="",base_size=18,pvalue_table=FALSE,
     color=if(curve_info$NES[j]>0)"#B2182B" else "#2166AC")
    # Reserve outer canvas space for edge ticks in the composed GSEA panels.
    g<-grid::grobTree(aplot::gglistGrob(p),vp=grid::viewport(width=.94,height=.96))
    grid::grid.newpage();grid::grid.draw(g)
    png(file.path(od,paste0(tolower(kind),"_curve_",j,".png")),width=3300,height=2700,res=300)
    grid::grid.newpage();grid::grid.draw(g);dev.off()
   }
   dev.off()
   edges<-do.call(rbind,lapply(seq_len(nrow(keep)),function(j)data.frame(term=keep$ID[j],annotation_id=strsplit(keep$core_enrichment[j],"/",fixed=TRUE)[[1]])))
  } else {
   write_tsv(data.frame(ID=character(),Description=character(),NES=numeric(),p.adjust=numeric(),png=character(),pdf_page=integer()),file.path(od,paste0(tolower(kind),"_curve_manifest.tsv")))
   edges<-data.frame(term=character(),annotation_id=character())
   saveplot(ggplot()+annotate("text",x=0,y=0,label="No significant GSEA curves",size=6)+theme_void(),file.path(od,paste0(tolower(kind),"_curves")))
  }
  write_tsv(edges,file.path(od,paste0(tolower(kind),"_leading_edges.tsv")))
  summaries[[length(summaries)+1]]<-data.frame(id=m$id,database=kind,method="GSEA",direction="ranked",query_ids=length(scores),
   annotated_query_ids=sum(names(scores) %in% d$tg$gene),tested_terms=nrow(tab),significant=nrow(keep),positive=sum(keep$NES>0),negative=sum(keep$NES<0))
 }
}
write_tsv(do.call(rbind,summaries),file.path(root,"results/summary.tsv"));write_tsv(do.call(rbind,mapping_rows),file.path(root,"results/mapping_summary.tsv"))
write_json(list(alpha=alpha,min_size=min_size,max_size=max_size,seed=seed,ranking="Original fitted DESeq2 Wald stat; finite test p-value; independent-filter NA padj retained",
 duplicate_policy="largest absolute original stat per annotation ID",annotation=cfg,method="fgsea multilevel; BH within each comparison/database"),
 file.path(root,"results/methods.json"),auto_unbox=TRUE,pretty=TRUE)
writeLines(capture.output(sessionInfo()),file.path(root,"results/sessionInfo.txt"))
