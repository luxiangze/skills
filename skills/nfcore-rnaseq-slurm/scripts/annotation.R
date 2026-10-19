#!/usr/bin/env Rscript
# Generate runtime mapping tables; no database or snapshot is redistributed.
suppressPackageStartupMessages({library(AnnotationDbi);library(GO.db);library(jsonlite)})
a <- commandArgs(TRUE)
if (length(a)<4) stop("Usage: annotation.R OrgDb.sqlite|org.PACKAGE keytype KEGG_CODE OUTPUT_DIR [KEGG_SNAPSHOT_DIR]")
db <- if (file.exists(a[1])) loadDb(normalizePath(a[1])) else {
  if (!requireNamespace(a[1],quietly=TRUE)) stop("Install requested OrgDb in this stage's renv first")
  get(a[1],envir=asNamespace(a[1]))
}
keytype <- a[2]; code <- a[3]; out <- a[4]
if(!keytype %in% keytypes(db))stop("Invalid keytype; available: ",paste(keytypes(db),collapse=", "))
if(!(keytype=="ENTREZID"||(keytype=="GID"&&code=="bmor")))stop("Use ENTREZID, or the known NCBI-GeneID-valued GID column of the Bombyx OrgDb; otherwise supply explicit common-namespace tables")
dir.create(out,recursive=TRUE,showWarnings=FALSE); out <- normalizePath(out)
norm <- function(x) sub("\\.0$","",as.character(x))
tab <- select(db,keys=keys(db,keytype),keytype=keytype,columns=c("GO","ONTOLOGY"))
tab$id <- norm(tab[[keytype]])
tab <- unique(tab[!is.na(tab$GO)&grepl("^GO:[0-9]{7}$",tab$GO)&tab$ONTOLOGY %in% c("BP","MF","CC")&!is.na(tab$id),c("GO","ONTOLOGY","id")])
ancestor <- list(BP=as.list(GOBPANCESTOR),MF=as.list(GOMFANCESTOR),CC=as.list(GOCCANCESTOR))
groups <- split(tab,interaction(tab$ONTOLOGY,tab$GO,drop=TRUE))
go_rows <- lapply(groups,function(group) {
  term <- group$GO[1]; ont <- group$ONTOLOGY[1]
  parents <- ancestor[[ont]][[term]]
  terms <- unique(c(term,parents[!is.na(parents)&grepl("^GO:[0-9]{7}$",parents)]))
  ids <- unique(group$id)
  data.frame(term=rep(terms,each=length(ids)),gene=rep(ids,times=length(terms)))
})
go <- unique(do.call(rbind,go_rows)); known <- intersect(unique(go$term),keys(GO.db,keytype="GOID"))
go <- go[go$term %in% known,]
names <- select(GO.db,keys=known,keytype="GOID",columns=c("TERM","ONTOLOGY"))
gonames <- unique(data.frame(term=names$GOID,name=names$TERM,ontology=names$ONTOLOGY))
write_tsv <- function(x,p) write.table(x,p,sep="\t",quote=FALSE,row.names=FALSE,na="")
write_tsv(go,file.path(out,"go_term2gene.tsv"));write_tsv(gonames,file.path(out,"go_term2name.tsv"))
kdir <- if (length(a)>=5) normalizePath(a[5]) else file.path(out,paste0("kegg_",code,"_",format(Sys.Date(),"%Y%m%d")))
if (length(a)<5) {
  dir.create(kdir,recursive=TRUE,showWarnings=FALSE)
  endpoints <- c(list_pathway=paste0("list/pathway/",code),link_pathway=paste0("link/pathway/",code),conv_ncbi_geneid=paste0("conv/ncbi-geneid/",code))
  for (key in names(endpoints)) download.file(paste0("https://rest.kegg.jp/",endpoints[[key]]),file.path(kdir,paste0(key,".txt")),quiet=TRUE,mode="wb")
  writeLines(paste("Retrieved",format(Sys.time(),tz="UTC"),"UTC from official KEGG REST"),file.path(kdir,"retrieved.txt"))
}
raw <- function(file) read.delim(file.path(kdir,file),header=FALSE,quote="",comment.char="",colClasses="character")
links <- raw("link_pathway.txt"); pathways <- raw("list_pathway.txt"); conv <- raw("conv_ncbi_geneid.txt")
# KEGG conv orientations vary with source/target; identify the namespace, never assume it.
kcol <- if (any(startsWith(conv[[1]],paste0(code,":")))) 1 else 2
ncol <- 3-kcol; good <- startsWith(conv[[ncol]],"ncbi-geneid:")
lookup <- setNames(sub("^ncbi-geneid:","",conv[[ncol]][good]),conv[[kcol]][good])
genes <- unname(lookup[links[[1]]]); keep <- !is.na(genes)
kg <- unique(data.frame(term=sub("^path:","",links[[2]][keep]),gene=norm(genes[keep])))
kn <- data.frame(term=sub("^path:","",pathways[[1]]),name=pathways[[2]])
write_tsv(kg,file.path(out,"kegg_term2gene.tsv")); write_tsv(kn,file.path(out,"kegg_term2name.tsv"))
config <- list(go_term2gene=file.path(out,"go_term2gene.tsv"),go_term2name=file.path(out,"go_term2name.tsv"),
 kegg_term2gene=file.path(out,"kegg_term2gene.tsv"),kegg_term2name=file.path(out,"kegg_term2name.tsv"),id_type="ncbi_geneid",
 provenance=list(OrgDb=if(file.exists(a[1])) normalizePath(a[1]) else a[1],OrgDb_metadata=metadata(db),
 GO_db=as.character(packageVersion("GO.db")),GO_method="Direct associations plus ontology ancestors; obsolete/unresolved terms excluded",
 KEGG_snapshot=normalizePath(kdir),mapping_generated=as.character(Sys.Date())))
record <- c(file.path(kdir,"retrieved.txt"),file.path(kdir,"README.txt"))
record <- record[file.exists(record)]
if(!length(record))stop("KEGG snapshot needs a retrieval/provenance record; add retrieved.txt or README.txt with its actual source date")
config$provenance$KEGG_retrieval_record <- paste(readLines(record[1],warn=FALSE),collapse="\n")
write_json(config,file.path(out,"annotation.json"),pretty=TRUE,auto_unbox=TRUE)
writeLines(capture.output(sessionInfo()),file.path(out,"sessionInfo.txt"))
