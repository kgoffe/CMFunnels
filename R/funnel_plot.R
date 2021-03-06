#' @title Funnel Plots for Incident Reporting
#' @description This is an implementation of funnel plots described Spiegelhalter (2005).
#' There are several of parameters for the input, with the assumption that  you will want smooth,
#'  overdispersed, funnel limits plotted based on the DerSimmonian Laird \eqn{\tau^2} additive random
#' effects models.
#'
#' @param predictions A vector of model predictions.  Used as denominator of the Y-axis and the scale of the x-axis
#' @param observed  A vector of the observed value.  Used as numerator of the Y-axis
#' @param group A vector of group names or a factor.  Used to aggreagate and group points on plots
#' @param title Plot title
#' @param label_outliers Add group labels to outliers on plot. (default=TRUE)
#' @param Poisson_limits Draw exact limits based only on data points with no iterpolation. (default=FALSE)
#' @param OD_Tau2 Draw overdispersed limits? Using Speigelhalter's (2012) Tau2 (default=TRUE)
#' @param method Either "CQC" or "SHMI" (default). There are a few methods for standardisation.  CQC/Spiegelhalter
#' uses a square root transformation and winsorizes by replaceing values, SHMI uses log transformation and winsorizes
#' by truncation. CQC method is default.
#' @param Winsorize_by Proportion of the distribution for winsorization. Default is 10 \% (0.1)
#' @param multiplier Scale relative risk and funnel by this factor. Default to 1, but 100 is used for HSMR
#' @param x_label Title for the funnel plot x-axis.  Usually expected deaths, readmissions, incidents etc.
#' @param y_label Title for the funnel plot y-axis.  Usually a standardised ratio.
#'
#' @return a list of the funnel plot as ggplot2 object, the limits table and the base table for plot.
#' @export
#' @details
#'    Outliers are marked based on the grouping, controlled by `label_outliers` .
#'    Overdispersion can be factored in based on the methods in \href{https://rss.onlinelibrary.wiley.com/doi/full/10.1111/j.1467-985X.2011.01010.x}{Spiegelhalter et al (2012)}, set `OD_Tau2` to FALSE to suppress this.
#'    To use Poisson limits set `Poisson_limits=TRUE`. This uses 2 & 3 \eqn{\sigma} limits.
#'    It deliberatley avoids red-amber-green colouring, but you could extract this from the ggplot object and change manually if you like.
#'
#' @examples \dontrun{
#'     a<-funnel_plot(my_preds, my_observed, "organisation", '2015/16', 'Poisson model')
#'     #Access the plot
#'     a[[3]]
#'
#'     #Access the
#'     }
#'
#'
#' @seealso \href{https://rss.onlinelibrary.wiley.com/doi/full/10.1111/j.1467-985X.2011.01010.x}{Statistical methods for healthcare regulation: rating, screening and surveillance. Spiegelhalter et al (2012)}
#'    \href{https://onlinelibrary.wiley.com/doi/10.1002/sim.1970}{Funnel plots for comparing institutional performance. Spiegelhalter (2004)}
#'    \href{https://qualitysafety.bmj.com/content/14/5/347}{Handeling over-dispersion of performance indicators. Spiegelhalter (2005)}
#'
#' @importFrom scales comma
#' @importFrom arm rescale
#' @importFrom ggrepel geom_text_repel
#' @importFrom dplyr select filter arrange mutate summarise group_by %>% n
#' @importFrom stats predict qchisq quantile sd
#' @import ggplot2


funnel_plot<-function(predictions, observed, group, title, label_outliers=TRUE,
                      Poisson_limits=FALSE, OD_Tau2=TRUE, method="SHMI", Winsorize_by = 0.1,
                      multiplier = 1, x_label="Expected", y_label="Standardised Ratio"){



  #build inital dataframe of obs/prdicted, with error message caught here in 'try'

  if(missing(predictions)){
    stop("Need to specify model predictions")}
  if(missing(observed)){
    stop("Need to supply observed")}
  if(missing(title)){
    title<-("Untitled Funnel Plot")}
  if(missing(observed)){
    stop("Need to supply the column name for observed events")}

  if(class(predictions)[1]  == "array"){
  predictions<-as.numeric(predictions)
  }


  mod_plot<- data.frame(preds=predictions, obs=observed, grp=group)

  mod_plot_agg<- mod_plot %>%
    dplyr::group_by(grp) %>%
    dplyr::summarise(observed=as.numeric(sum(obs)),
                   predicted=as.numeric(sum(preds)),
                   rr=observed/predicted
                   )

  #mod_plot_agg

  #Determine the range of plots
  max_preds<-dplyr::summarise(mod_plot_agg, ceiling(max(predicted))) %>% as.numeric()
  min_ratio<-dplyr::summarise(mod_plot_agg, multiplier * min(observed/predicted)) %>% as.numeric()
  max_ratio<-dplyr::summarise(mod_plot_agg, multiplier * max(observed/predicted)) %>% as.numeric()


  ##Winsorisation

  if(method=="CQC"){

    mod_plot_agg <- mod_plot_agg %>%
      mutate(y=sqrt(observed/predicted),
             S= 1/(2*sqrt(predicted)),
             rrS2= S^2,
             Uzscore_CQC=2*(sqrt(observed) - sqrt(predicted)),
             LCI2= multiplier*(1-(1.959964 * sqrt(1/rrS2))^2),
             UCI2= multiplier*(1+(1.959964 * sqrt(1/rrS2)) ^2),
             LCI3= multiplier*(1-(3.090232 * sqrt(1/rrS2))^2),
             UCI3= multiplier*(1+(3.090232 * sqrt(1/rrS2)) ^2)

      )


    lz=quantile(x = mod_plot_agg$Uzscore_CQC, Winsorize_by)
    uz=quantile(x = mod_plot_agg$Uzscore_CQC, (1- Winsorize_by))

    mod_plot_agg<-mod_plot_agg %>%
      dplyr::mutate( Winsorised = ifelse(Uzscore_CQC>=lz & Uzscore_CQC<=uz, 0, 1),
                     Wuzscore= ifelse(Uzscore_CQC<lz, lz, ifelse(Uzscore_CQC>uz,lz,Uzscore_CQC)),
                     Wuzscore2= Wuzscore^2)

    phi<- mod_plot_agg %>%
      dplyr::summarise(phi=(1/as.numeric(n())) * sum(Wuzscore2)) %>%
      as.numeric()

    Tau2<- mod_plot_agg %>%
           dplyr::summarise(Tau2= max(0,
                                      ((n()*phi) - (n()-1))/

                                (sum(1/rrS2) -(sum(1/(S))/sum(1/rrS2)))
                                )
                            ) %>%
      as.numeric()

    mod_plot_agg <- mod_plot_agg %>%
      dplyr::mutate(
        phi=phi,
        Tau2=Tau2,
        Wazscore = (y-1)/ sqrt(((1/(2*sqrt(predicted)))^2)+Tau2),
        ODLCI=  multiplier*((1-(1.959964 * sqrt(((1/(2*sqrt(predicted)))^2)+Tau2)))^2),
        ODUCI=  multiplier*((1+(1.959964 * sqrt(((1/(2*sqrt(predicted)))^2)+Tau2)))^2),
        OD3LCI= multiplier*((1-(3.090232 * sqrt(((1/(2*sqrt(predicted)))^2)+Tau2)))^2),
        OD3UCI= multiplier*((1+(3.090232 * sqrt(((1/(2*sqrt(predicted)))^2)+Tau2)))^2)
      )


} else if(method=="SHMI"){

  mod_plot_agg <- mod_plot_agg %>%
    mutate(s= 1/(sqrt(predicted)),
           rrS2= s^2,
           Uzscore_SHMI= sqrt(predicted)*log(observed/predicted),
           LCI2=multiplier*(exp(-1.959964 * sqrt(rrS2))),
           UCI2=multiplier*(exp(1.959964 * sqrt(rrS2))),
           LCI3=multiplier*(exp(-3.090232 * sqrt(rrS2))),
           UCI3=multiplier*(exp(3.090232 * sqrt(rrS2)))

    )

  lz=quantile(x = mod_plot_agg$Uzscore_SHMI, Winsorize_by)
  uz=quantile(x = mod_plot_agg$Uzscore_SHMI, (1- Winsorize_by))

  mod_plot_agg<-mod_plot_agg %>%
    dplyr::mutate(Winsorised = ifelse(Uzscore_SHMI>=lz & Uzscore_SHMI<=uz, 0, 1))

  mod_plot_agg_sub<-mod_plot_agg %>%
    dplyr::filter(Winsorised==0) %>%
    mutate(Wuzscore= Uzscore_SHMI,
           Wuzscore2= Uzscore_SHMI ^2)

  phi<- mod_plot_agg_sub %>%
    dplyr::summarise(phi=(1/as.numeric(n())) * sum(Wuzscore2)) %>%
    as.numeric()

  Tau2<- mod_plot_agg_sub %>%
    dplyr::summarise(Tau2= max(0,((n()*phi) - (n()-1))/
                           (sum(predicted) -(sum(predicted^2)/sum(predicted))))) %>%
    as.numeric()


  mod_plot_agg <- mod_plot_agg %>%
    dplyr::mutate(
      Wuzscore= ifelse(Winsorised==1, NA ,Uzscore_SHMI),
      Wuzscore2= ifelse(Winsorised==1, NA ,Uzscore_SHMI ^2),
      phi=phi,
      Tau2=Tau2,
      Wazscore = log(rr) / sqrt((1/predicted)+Tau2),
      var= sqrt(rrS2 + Tau2),
      ODLCI=  multiplier*(exp(-1.959964 * sqrt((1/predicted)+Tau2))),
      ODUCI=  multiplier*(exp(1.959964 * sqrt((1/predicted)+Tau2))),
      OD3LCI= multiplier*(exp(-3.090232 * sqrt((1/predicted)+Tau2))),
      OD3UCI= multiplier*(exp(3.090232 * sqrt((1/predicted)+Tau2)))
   )

 } else {
   stop("Please specify a valid method")
 }


### Calculate funnel limits ####
  if(OD_Tau2 == FALSE){
    Poisson_limits<-TRUE
  }

  if(OD_Tau2 == TRUE & Tau2==0){
    OD_Tau2<-FALSE
    Poisson_limits<-TRUE

    message("No overdispersion detected, using Poisson limits")

    # general limits + Tau2 limits table
    set.seed(1)
    number.seq <- c(seq(0.1, 10, 0.1),seq(1, ceiling(max_preds), 1))
    dfCI<- data.frame(
      number.seq,
      ll95 = multiplier*((qchisq(0.975,2 * number.seq, lower.tail = FALSE) /2)/number.seq),
      ul95 =  multiplier*((qchisq(0.025,2 * (number.seq+1), lower.tail = FALSE) /2)/number.seq),
      ll999 = multiplier*((qchisq(0.999,2 * number.seq, lower.tail = FALSE) /2)/number.seq),
      ul999 = multiplier*((qchisq(0.001,2 * (number.seq+1), lower.tail = FALSE) /2)/number.seq)
    )

  } else if(method=="SHMI"){
  # general limits + Tau2 limits table
  set.seed(1)
  number.seq <- c(seq(0.1, 10, 0.1),seq(1, ceiling(max_preds), 1))
  dfCI<- data.frame(
    number.seq,
    ll95 = multiplier*((qchisq(0.975,2 * number.seq, lower.tail = FALSE) /2)/number.seq),
    ul95 =  multiplier*((qchisq(0.025,2 * (number.seq+1), lower.tail = FALSE) /2)/number.seq),
    ll999 = multiplier*((qchisq(0.999,2 * number.seq, lower.tail = FALSE) /2)/number.seq),
    ul999 = multiplier*((qchisq(0.001,2 * (number.seq+1), lower.tail = FALSE) /2)/number.seq),
    odll95 = multiplier*(exp(-1.959964 * sqrt((1/number.seq) +Tau2))),
    odul95 = multiplier*(exp(1.959964 * sqrt((1/number.seq) +Tau2))),
    odll999 = multiplier*(exp(-3.090232 * sqrt((1/number.seq) +Tau2))),
    odul999 = multiplier*(exp(3.090232 * sqrt((1/number.seq) +Tau2)))
    )

  } else if(method=="CQC"){
    set.seed(1)
    number.seq <- seq(1, ceiling(max_preds), 1)
    dfCI<- data.frame(
      number.seq,
      ll95 = multiplier*((qchisq(0.975,2 * number.seq, lower.tail = FALSE) /2)/number.seq),
      ul95 =  multiplier*((qchisq(0.025,2 * (number.seq+1), lower.tail = FALSE) /2)/number.seq),
      ll999 = multiplier*((qchisq(0.999,2 * number.seq, lower.tail = FALSE) /2)/number.seq),
      ul999 = multiplier*((qchisq(0.001,2 * (number.seq+1), lower.tail = FALSE) /2)/number.seq),
      odll95 = multiplier*((1-(1.959964 *  (sqrt(((1/(2*sqrt(number.seq)))^2) +Tau2))))^2),
      odul95 = multiplier*((1+(1.959964 *  (sqrt(((1/(2*sqrt(number.seq)))^2) +Tau2))))^2),
      odll999 = multiplier*((1+(-3.090232 *  (sqrt(((1/(2*sqrt(number.seq)))^2) +Tau2))))^2),
      odul999 = multiplier*((1+(3.090232 *  (sqrt(((1/(2*sqrt(number.seq)))^2) +Tau2))))^2)
    )

  } else {
    stop("Invalid method supplied")
  }

qnorm(0.025)

#base funnel plot
funnel_p<- ggplot(mod_plot_agg, aes(y=multiplier*((observed/predicted)), x=predicted))+
  geom_point(size=2, alpha=0.55, shape=21, fill = "dodgerblue2") +
  #scale_y_continuous(limits = c((min_ratio-0.1), (max_ratio+0.1)))+
  #scale_x_continuous(labels = scales::comma, limits = c(0,max_preds+1)) +
  geom_hline(aes(yintercept = multiplier), linetype=2)+
  xlab(x_label) +
  ylab(y_label) +
  ggtitle(title)+
  #theme_bw()+
  theme(plot.title = element_text(hjust = 0.5, face = "bold"),
        plot.subtitle = element_text(hjust = 0.5,face = "italic")
        #plot.background =  element_rect(fill='white', colour='white'),
        )+
  guides(colour = guide_legend(title.theme = element_text(
    size = 10,
    face = "bold",
    colour = "black",
    angle = 0)))

 if(OD_Tau2==TRUE){
    funnel_p<- funnel_p +
      scale_y_continuous(name=y_label, limits = c((multiplier*(min_ratio-0.05)), (multiplier* (max_ratio+0.05))))+
      scale_x_continuous(name=x_label, labels = scales::comma, limits = c(0,max_preds+1))
   } else {
     funnel_p<- funnel_p +
       scale_y_continuous(name=y_label, limits = c((multiplier*(min_ratio-0.05)), (multiplier* (max_ratio+0.05))))+
       scale_x_continuous(name=x_label, labels = scales::comma, limits = c(0,max_preds+1))
    }


  if(Poisson_limits==TRUE & OD_Tau2==TRUE){
    funnel_p<-funnel_p +
      geom_line(aes(x = number.seq, y = ll95, col="2σ Poisson"), size = 1, linetype=2, data = dfCI, na.rm=TRUE) +
      geom_line(aes(x = number.seq, y = ul95, col="2σ Poisson"),  size = 1, linetype=2, data = dfCI, na.rm=TRUE) +
      geom_line(aes(x = number.seq, y = ll999, col="3σ Poisson"), size = 1, data = dfCI, na.rm=TRUE) +
      geom_line(aes(x = number.seq, y = ul999, col="3σ Poisson"),  size = 1,data = dfCI, na.rm=TRUE) +
      geom_line(aes(x = number.seq, y = odll95, col="2σ Overdispersed"), size = 1, linetype=2, data = dfCI, na.rm=TRUE) +
      geom_line(aes(x = number.seq, y = odul95, col="2σ Overdispersed"),  size = 1, linetype=2, data = dfCI, na.rm=TRUE) +
      geom_line(aes(x = number.seq, y = odll999, col="3σ Overdispersed"), size = 1, data = dfCI, na.rm=TRUE) +
      geom_line(aes(x = number.seq, y = odul999, col="3σ Overdispersed"),  size = 1,data = dfCI, na.rm=TRUE) +
      scale_color_manual(values=c("3σ Poisson"="#1F77B4FF",
                                  "2σ Poisson"= "#FF7F0EFF",
                                  "3σ Overdispersed"= "#2CA02CFF",
                                  "2σ Overdispersed"= "#9467BDFF"
      ),name="Control limits")
  } else {

    if(Poisson_limits==TRUE){
      funnel_p<-funnel_p +
        geom_line(aes(x = number.seq, y = ll95, col="2σ Poisson"), size = 1, linetype=2, data = dfCI, na.rm=TRUE) +
        geom_line(aes(x = number.seq, y = ul95, col="2σ Poisson"),  size = 1, linetype=2, data = dfCI, na.rm=TRUE) +
        geom_line(aes(x = number.seq, y = ll999, col="3σ Poisson"), size = 1, data = dfCI, na.rm=TRUE) +
        geom_line(aes(x = number.seq, y = ul999, col="3σ Poisson"),  size = 1,data = dfCI, na.rm=TRUE) +
        scale_color_manual(values=c("3σ Poisson"= "#7E9C06", #"#1F77B4FF"
                                    "2σ Poisson"= "#FF7F0EFF"
                            ),name="Control limits")
    }

   if(OD_Tau2==TRUE){
    funnel_p<-funnel_p +
        geom_line(aes(x = number.seq, y = odll95, col="2σ Overdispersed"), size = 1, linetype=2, data = dfCI, na.rm=TRUE) +
        geom_line(aes(x = number.seq, y = odul95, col="2σ Overdispersed"),  size = 1, linetype=2, data = dfCI, na.rm=TRUE) +
        geom_line(aes(x = number.seq, y = odll999, col="3σ Overdispersed"), size = 1, data = dfCI, na.rm=TRUE) +
        geom_line(aes(x = number.seq, y = odul999, col="3σ Overdispersed"),  size = 1,data = dfCI, na.rm=TRUE) +
        scale_color_manual(values=c("3σ Overdispersed"= "#DEC400", #"#F7EF0A", #"#2CA02CFF",
                                    "2σ Overdispersed"= "#9467BDFF"
                                    ),name="Control limits")
  }

  }

    if (label_outliers==TRUE){
      if(OD_Tau2==FALSE){
        funnel_p<-funnel_p +
          ggrepel::geom_label_repel(aes(label=ifelse(observed/predicted>UCI3,as.character(grp),'')), size=2.7, direction="y")+
          ggrepel::geom_label_repel(aes(label=ifelse(observed/predicted<LCI3,as.character(grp),'')), size=2.7, direction="y")
      } else {
        funnel_p<-funnel_p +
          ggrepel::geom_label_repel(aes(label=ifelse(observed/predicted>OD3UCI,as.character(grp),'')), size=2.7, direction="y" )+
          ggrepel::geom_label_repel(aes(label=ifelse(observed/predicted<OD3LCI,as.character(grp),'')), size=2.7, direction="y" )
        }

    }

#ggrepel::geom_label_repel(aes(label=ifelse(observed/predicted>UCI3,as.character(grp),'')),hjust=0,vjust=0, size=2.7, nudge_y = 0.01)+
 # ggrepel::geom_label_repel(aes(label=ifelse(observed/predicted<LCI3,as.character(grp),'')),hjust=0,vjust=0, size=2.7, nudge_y = -0.05)
#} else {
#  funnel_p<-funnel_p +
#    ggrepel::geom_label_repel(aes(label=ifelse(observed/predicted>OD3UCI,as.character(grp),'')),hjust=0,vjust=0, size=2.7, nudge_y = 0.01)+
#    ggrepel::geom_label_repel(aes(label=ifelse(observed/predicted<OD3LCI,as.character(grp),'')),hjust=0,vjust=0, size=2.7, nudge_y = -0.05)


  return(list(mod_plot_agg, dfCI, funnel_p))

}



