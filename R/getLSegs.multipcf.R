getLSegs.multipcf <- function(allTracks,
                              lCTS,
                              lSe,
                              lGCT,
                              lNormals=NULL,
                              allchr,
                              segmentation_alpha=0.01,
                              normalize=F,
                              svinput=NULL,
                              MC.CORES=1)
{
    ## #############################################################
    suppressPackageStartupMessages(require(parallel))
    suppressPackageStartupMessages(require(copynumber))
    ## #############################################################
    smoothAll <- function(lCTS, lSe, lGCT, lNormals, allchr, MC.CORES)
    {
        lCTSs <- parallel::mclapply(lCTS, function(lCT)
        {
            lCTS <- smoothCoverageTrack(lCT=lCT,lSe=lSe,lGCT=lGCT, lNormals=lNormals)
            names(lCTS) <- allchr
            lCTS
        },mc.cores=MC.CORES)
        cat("\n")
        lCTSs
    }
    applyOriginalPositions <- function(out, tmpdata)
    {
        nprobes <- out$n.probes
        start.ind <- c(1,cumsum(nprobes)+1)
        start.ind <- start.ind[-length(start.ind)]
        end.ind <- cumsum(nprobes)
        starts <- tmpdata$start
        ends <- tmpdata$end
        widths <-ends-starts
        starts <- starts-widths/2
        ends <- ends+widths/2
        out$start.pos <- starts[start.ind]
        out$end.pos <- ends[end.ind]
        out
    }
    ## #############################################################
    print("Smoothing all tracks")
    lCTSs <- smoothAll(lCTS,lSe, lGCT, lNormals, allchr, MC.CORES=MC.CORES)
    ## #############################################################
    runMultiPCF <- function(allT, penalties, nchr, svinput, mc.cores=1)
    {
        chr_pcfed <- mclapply(1:nchr,function(i)
        {
            widths <- (allT$lCTS[[1]][[i]][,"end"]-allT$lCTS[[1]][[i]][,"start"])
            tmpdata <- data.frame("chr"=rep(i,nrow(allT$lCTS[[1]][[i]])),
                                  pos=round(allT$lCTS[[1]][[i]][,"start"]+widths/2),
                                  start=allT$lCTS[[1]][[i]][,"start"]+widths/4,
                                  end=allT$lCTS[[1]][[i]][,"end"]-widths/4,
                                  do.call("cbind",lapply(allT$lCTS,function(x)
                                  {
                                      x[[i]]$smoothed
                                  })))
            rmcc <- which(colnames(tmpdata)%in%c("start","end"))
            out <- NULL
            if(!is.null(svinput))
            {
                sv_condchr <- gsub("chr","",svinput[,1])==gsub("chr","",allchr[i])
                svinput <- svinput[sv_condchr,]
                if(sum(sv_condchr)>0)
                    out <- sc_getBreakpoints_multipcf(tmpdata, svinput, penalties, normalize)
            }
            if(is.null(svinput) | is.null(out))
            {
                out <- lapply(penalties,function(penalty)
                {
                    invisible(capture.output(suppressMessages({ok <- copynumber::multipcf(data=tmpdata[,-rmcc],
                                                                                          gamma=penalty,
                                                                                          normalize=normalize)})))
                    ok
                })
            }
            out[[1]] <- applyOriginalPositions(out[[1]], tmpdata)
            out
        },mc.cores=mc.cores)
        names(chr_pcfed) <- paste0("chr",1:nchr)
        chr_pcfed
    }
    ## #############################################################
    nchr <- length(lCTS[[1]])
    allT <- list(lCTS=lCTSs)
    penalties <- 1/segmentation_alpha ## rough translation from CBS pval to pcf penalty
    ## #############################################################
    print("Segmenting all chromosomes across tracks")
    allsegs <- runMultiPCF(allT,
                           penalties=penalties,
                           nchr=nchr,
                           svinput,
                           mc.cores=MC.CORES)
    ## #############################################################
    allTracks.processed <- mclapply(1:length(allTracks), function(i)
    {
        allTracks[[i]]$lSegs <- lapply(allsegs,function(x)
        {
            x <- x[[1]]
            list(data=NULL,
                 output=data.frame(ID="Sample.ID",
                                   chrom=x[,"chrom"],
                                   loc.start=as.numeric(as.character(x[,"start.pos"])),
                                   loc.end=as.numeric(as.character(x[,"end.pos"])),
                                   num.mark=as.numeric(as.character(x[,"n.probes"])),
                                   seg.mean=as.numeric(as.character(x[,5+i]))))
        })
        names(allTracks[[i]]$lSegs) <- allchr
        allTracks[[i]]$lCTS <- lCTSs[[i]]
        names(allTracks[[i]]$lCTS) <- allchr
        allTracks[[i]]
    },mc.cores=MC.CORES)
    names(allTracks.processed) <- names(allTracks)
    allTracks.processed
}
