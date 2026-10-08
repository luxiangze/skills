wrap_term_labels <- function(x, width = 42L) {
  vapply(as.character(x), function(z) paste(strwrap(z, width = width), collapse = "\n"),
         character(1), USE.NAMES = FALSE)
}

plot_height_by_rows <- function(labels, n_rows, type = c("KEGG", "GO"), ontologies = NULL) {
  type <- match.arg(type)
  labels <- as.character(labels)
  extra_lines <- if (length(labels)) sum(pmax(0L, lengths(strsplit(labels, "\n", fixed = TRUE)) - 1L)) else 0L
  if (type == "KEGG") {
    if (n_rows == 0L) return(2.35)
    return(max(2.45, min(13, 1.75 + 0.34 * n_rows + 0.11 * extra_lines)))
  }
  if (n_rows == 0L) return(3.05)
  ontologies <- ontologies %||% rep("BP", n_rows)
  counts <- table(factor(ontologies, levels = c("BP", "MF", "CC")))
  facet_heights <- ifelse(counts > 0, 0.72 + as.numeric(counts) * 0.31, 0.68)
  max(3.35, min(15, 1.25 + sum(facet_heights) + 0.10 * extra_lines))
}

`%||%` <- function(x, y) if (is.null(x)) y else x

save_empty_enrichment_plot <- function(type, caption, png_path, pdf_path, alpha = 0.05) {
  suppressPackageStartupMessages(library(ggplot2))
  label <- if (type == "GO") "No GO terms passed this filter" else "No KEGG pathways passed this filter"
  p <- ggplot() +
    annotate("text", x = 0.5, y = 0.5, label = label, size = 4.2) +
    coord_cartesian(xlim = c(0, 1), ylim = c(0, 1), clip = "off") +
    labs(caption = caption) +
    theme_void(base_size = 11) +
    theme(plot.background = element_rect(fill = "white", color = NA),
          plot.caption = element_text(size = 8.5, hjust = 0.5, margin = margin(t = 7)))
  height <- if (type == "GO") 3.05 else 2.35
  ggsave(png_path, p, width = 9, height = height, units = "in", dpi = 300, bg = "white")
  ggsave(pdf_path, p, width = 9, height = height, units = "in", device = grDevices::pdf, bg = "white")
  invisible(p)
}

save_enrichment_dotplot <- function(tab, type, caption, png_path, pdf_path,
                                    max_terms = NULL, alpha = 0.05) {
  suppressPackageStartupMessages(library(ggplot2))
  type <- match.arg(type, c("GO", "KEGG"))
  dir.create(dirname(png_path), recursive = TRUE, showWarnings = FALSE)
  dir.create(dirname(pdf_path), recursive = TRUE, showWarnings = FALSE)
  if (is.null(tab) || nrow(tab) == 0L) {
    return(save_empty_enrichment_plot(type, caption, png_path, pdf_path, alpha))
  }
  required <- c("Description", "GeneRatio", "Count", "p.adjust")
  if (!all(required %in% names(tab))) stop("Missing plotting columns: ", paste(setdiff(required, names(tab)), collapse = ", "))
  tab <- tab[order(tab$p.adjust, tab$pvalue %||% tab$p.adjust, -tab$Count), , drop = FALSE]
  if (!is.null(max_terms) && nrow(tab) > max_terms) tab <- tab[seq_len(max_terms), , drop = FALSE]
  tab$GeneRatioNumeric <- vapply(strsplit(as.character(tab$GeneRatio), "/", fixed = TRUE),
                                 function(z) as.numeric(z[[1]]) / as.numeric(z[[2]]), numeric(1))
  tab$Label <- wrap_term_labels(tab$Description)
  tab$Label <- factor(tab$Label, levels = rev(unique(tab$Label)))
  p <- ggplot(tab, aes(x = GeneRatioNumeric, y = Label)) +
    geom_point(aes(size = Count, color = p.adjust), alpha = 0.9) +
    scale_color_gradient(low = "#B2182B", high = "#2166AC", name = "BH adjusted p") +
    scale_size_continuous(range = c(2.5, 8), name = "Genes") +
    labs(title = NULL, subtitle = NULL, caption = caption, x = "Gene ratio", y = NULL) +
    theme_bw(base_size = 11) +
    theme(plot.title = element_blank(), plot.subtitle = element_blank(),
          axis.text.x = element_text(size = 9), axis.text.y = element_text(size = 9),
          axis.title.x = element_text(size = 10), legend.text = element_text(size = 9),
          legend.title = element_text(size = 9.5),
          plot.caption = element_text(size = 8.5, hjust = 0.5, margin = margin(t = 7)),
          panel.grid.minor = element_blank(), strip.text.y = element_text(face = "bold", size = 9.5))
  if (type == "GO") {
    if (!"ONTOLOGY" %in% names(tab)) stop("GO table requires ONTOLOGY (BP/MF/CC)")
    tab$ONTOLOGY <- factor(tab$ONTOLOGY, levels = c("BP", "MF", "CC"))
    label_levels <- unique(c(levels(tab$Label), "No significant terms"))
    tab$Label <- factor(as.character(tab$Label), levels = label_levels)
    missing_ontologies <- setdiff(c("BP", "MF", "CC"), unique(as.character(tab$ONTOLOGY)))
    empty_panels <- data.frame(
      ONTOLOGY = factor(missing_ontologies, levels = c("BP", "MF", "CC")),
      Label = factor(rep("No significant terms", length(missing_ontologies)), levels = label_levels),
      GeneRatioNumeric = rep(0, length(missing_ontologies)),
      stringsAsFactors = FALSE
    )
    p <- ggplot(tab, aes(x = GeneRatioNumeric, y = Label)) +
      geom_point(aes(size = Count, color = p.adjust), alpha = 0.9) +
      geom_text(data = empty_panels, aes(x = GeneRatioNumeric, y = Label,
        label = "No significant terms"), inherit.aes = FALSE, hjust = 0, size = 3) +
      scale_color_gradient(low = "#B2182B", high = "#2166AC", name = "BH adjusted p") +
      scale_size_continuous(range = c(2.5, 8), name = "Genes") +
      facet_grid(ONTOLOGY ~ ., scales = "free_y", space = "free_y", drop = TRUE) +
      labs(title = NULL, subtitle = NULL, caption = caption, x = "Gene ratio", y = NULL) +
      theme_bw(base_size = 11) +
      theme(plot.title = element_blank(), plot.subtitle = element_blank(),
            axis.text.x = element_text(size = 9), axis.text.y = element_text(size = 9),
            axis.title.x = element_text(size = 10), legend.text = element_text(size = 9),
            legend.title = element_text(size = 9.5),
            plot.caption = element_text(size = 8.5, hjust = 0.5, margin = margin(t = 7)),
            panel.grid.minor = element_blank(), strip.text.y = element_text(face = "bold", size = 9.5))
  }
  height <- plot_height_by_rows(tab$Label, nrow(tab), type,
                                if (type == "GO") as.character(tab$ONTOLOGY) else NULL)
  ggsave(png_path, p, width = if (type == "GO") 10 else 9, height = height,
         units = "in", dpi = 300, limitsize = FALSE, bg = "white")
  ggsave(pdf_path, p, width = if (type == "GO") 10 else 9, height = height,
         units = "in", device = grDevices::pdf, limitsize = FALSE, bg = "white")
  invisible(p)
}
