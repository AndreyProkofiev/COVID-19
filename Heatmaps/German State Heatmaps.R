rm(list=ls())

library(tidyverse)
library(curl)
library(forcats)
library(readxl)
library(RcppRoll)
library(zoo)
library(cowplot)

#Read in data
temp <- tempfile()
source <- "https://raw.githubusercontent.com/jgehrcke/covid-19-germany-gae/master/data.csv"
temp <- curl_download(url=source, destfile=temp, quiet=FALSE, mode="wb")

data <- read.csv(temp)

data_long <- pivot_longer(data, c(3:34), names_to=c("State", "measure"), names_sep="_", values_to="count")[,-c(2:4)]

data_long$date <- as.Date(substr(data_long$time_iso8601, 1, 10))

#Tidy up state names
data_long$State <- case_when(
  data_long$State=="DE.BW" ~ "Baden-Württemberg",
  data_long$State=="DE.BY" ~ "Bayern",
  data_long$State=="DE.BE" ~ "Brandenburg",
  data_long$State=="DE.BB" ~ "Berlin",
  data_long$State=="DE.HB" ~ "Bremen",
  data_long$State=="DE.HH" ~ "Hamburg",
  data_long$State=="DE.HE" ~ "Hessen",
  data_long$State=="DE.MV" ~ "Mecklenburg-Vorpommern",
  data_long$State=="DE.NI" ~ "Niedersachsen",
  data_long$State=="DE.NW" ~ "Nordrhein-Westfalen",
  data_long$State=="DE.RP" ~ "Rheinland-Pfalz",
  data_long$State=="DE.SL" ~ "Saarland",
  data_long$State=="DE.SN" ~ "Sachsen-Anhalt",
  data_long$State=="DE.SH" ~ "Sachsen",
  data_long$State=="DE.ST" ~ "Schleswig-Holstein",
  data_long$State=="DE.TH" ~ "Thüringen")

#Some dates are missing, so set up skeleton dataset with all dates
#Set up skeleton dataframe with dates
States <- unique(data_long$State)
min <- min(data_long$date)
max <- max(data_long$date)

skeleton <- data.frame(State=rep(States, each=(max-min+1), times=2), 
                       date=rep(seq.Date(from=min, to=max, by="day"), each=1, times=length(States)*2),
                       measure=rep(c("cases", "deaths"), each=length(States)*(max-min+1)))

#Map data onto skeleton
fulldata <- merge(skeleton, data_long[,-c(1)], by=c("State", "date", "measure"), all.x=TRUE, all.y=TRUE)

#Interpolate missing dates
fulldata <- fulldata %>%
  group_by(State, measure) %>%
  mutate(count=na.spline(count))

#Calculate daily figures
fulldata <- fulldata %>%
  arrange(measure, State, date) %>%
  group_by(State, measure) %>%
  mutate(daycount=count-lag(count,1))

#Ignore days when cases go *down*, probably due to reallocation
fulldata$daycount <- ifelse(is.na(fulldata$daycount), 0, fulldata$daycount)
fulldata$daycount <- ifelse(fulldata$daycount<0, 0, fulldata$daycount)

heatmap <- fulldata %>%
  group_by(State, measure) %>%
  mutate(casesroll_avg=roll_mean(daycount, 7, align="right", fill=0)) %>%
  mutate(maxcaserate=max(casesroll_avg), maxcaseday=date[which(casesroll_avg==maxcaserate)][1],
         totalcases=max(count))

heatmap$maxcaseprop <- heatmap$casesroll_avg/heatmap$maxcaserate

#Enter dates to plot from and to
plotfrom <- "2020-03-21"
plotto <- max

#Plot case trajectories
casetiles <- ggplot(subset(heatmap, measure=="cases"), aes(x=date, y=fct_reorder(State, maxcaseday), fill=maxcaseprop))+
  geom_tile(colour="White", show.legend=FALSE)+
  theme_classic()+
  scale_fill_distiller(palette="Spectral")+
  scale_y_discrete(name="", expand=c(0,0))+
  scale_x_date(name="Date", limits=as.Date(c(plotfrom, plotto)), expand=c(0,0))+
  labs(title="Timelines for COVID-19 cases in German Bundesländer",
       subtitle=paste0("The heatmap represents the 7-day rolling average of the number of new confirmed cases, normalised to the maximum value within the State.\nStates are ordered by the date at which they reached their peak number of new cases. Bars on the right represent the absolute number of cases in each State.\nData updated to ", plotto,". Data for most recent days is provisional and may be revised upwards as additional tests are processed."),
       caption="Data from Jan-Philip Gehrcke (https://covid19-germany.appspot.com/) | Plot by @VictimOfMaths")+
  theme(axis.line.y=element_blank(), plot.subtitle=element_text(size=rel(0.78)), plot.title.position="plot",
        axis.text.y=element_text(colour="Black"))

casebars <- ggplot(subset(heatmap, date==maxcaseday & measure=="cases"), 
                   aes(x=totalcases, y=fct_reorder(State, maxcaseday), fill=totalcases))+
  geom_col(show.legend=FALSE)+
  theme_classic()+
  scale_fill_distiller(palette="Spectral")+
  scale_x_continuous(name="Total confirmed cases", breaks=c(0,20000,40000))+
  theme(axis.title.y=element_blank(), axis.line.y=element_blank(), axis.text.y=element_blank(),
        axis.ticks.y=element_blank(), axis.text.x=element_text(colour="Black"))

tiff("Outputs/COVIDGermanStateCasesHeatmap.tiff", units="in", width=11, height=6, res=500)
plot_grid(casetiles, casebars, align="h", rel_widths=c(1,0.2))
dev.off()

#Plot death trajectories
deathtiles <- ggplot(subset(heatmap, measure=="deaths"), aes(x=date, y=fct_reorder(State, maxcaseday), fill=maxcaseprop))+
  geom_tile(colour="White", show.legend=FALSE)+
  theme_classic()+
  scale_fill_distiller(palette="Spectral")+
  scale_y_discrete(name="", expand=c(0,0))+
  scale_x_date(name="Date", limits=as.Date(c(plotfrom, plotto)), expand=c(0,0))+
  labs(title="Timelines for COVID-19 deaths in German Bundesländer",
       subtitle=paste0("The heatmap represents the 7-day rolling average of the number of confirmed deaths, normalised to the maximum value within the State.\nStates are ordered by the date at which they reached their peak number of deaths. Bars on the right represent the absolute number of deaths in each State.\nData updated to ", plotto,". Data for most recent days is provisional and may be revised upwards as additional tests are processed."),
       caption="Data from Jan-Philip Gehrcke (https://covid19-germany.appspot.com/) | Plot by @VictimOfMaths")+
  theme(axis.line.y=element_blank(), plot.subtitle=element_text(size=rel(0.78)), plot.title.position="plot",
        axis.text.y=element_text(colour="Black"))

deathbars <- ggplot(subset(heatmap, date==maxcaseday & measure=="deaths"), 
                   aes(x=totalcases, y=fct_reorder(State, maxcaseday), fill=totalcases))+
  geom_col(show.legend=FALSE)+
  theme_classic()+
  scale_fill_distiller(palette="Spectral")+
  scale_x_continuous(name="Total confirmed deaths", breaks=c(0,1000,2000))+
  theme(axis.title.y=element_blank(), axis.line.y=element_blank(), axis.text.y=element_blank(),
        axis.ticks.y=element_blank(), axis.text.x=element_text(colour="Black"))

tiff("Outputs/COVIDGermanStateDeathsHeatmap.tiff", units="in", width=11, height=6, res=500)
plot_grid(deathtiles, deathbars, align="h", rel_widths=c(1,0.2))
dev.off()

#Try them as ridgeplots
library(ggridges)

tiff("Outputs/COVIDGermanStateCaseRidges.tiff", units="in", width=11, height=6, res=500)
ggplot(subset(heatmap, measure=="cases"), aes(x=date, y=fct_reorder(State, totalcases), height=casesroll_avg, fill=casesroll_avg))+
  geom_density_ridges_gradient(stat="identity", rel_min_height=0.01)+
  theme_classic()+
  scale_fill_distiller(palette="Spectral", name="Cases per day\n7-day rolling avg.")+
  scale_x_date(name="Date", limits=as.Date(c(plotfrom, plotto)), expand=c(0,0))+
  scale_y_discrete(name="")+
  labs(title="Timelines of confirmed COVID-19 cases in German Bundesländer",
       caption="Data from Jan-Philip Gehrcke (https://covid19-germany.appspot.com/) | Plot by @VictimOfMaths")
dev.off()

tiff("Outputs/COVIDGermanStateDeathsRidges.tiff", units="in", width=11, height=6, res=500)
ggplot(subset(heatmap, measure=="deaths"), aes(x=date, y=fct_reorder(State, totalcases), height=casesroll_avg, fill=casesroll_avg))+
  geom_density_ridges_gradient(stat="identity", rel_min_height=0.01)+
  theme_classic()+
  scale_fill_distiller(palette="Spectral", name="Deaths per day\n7-day rolling avg.")+
  scale_x_date(name="Date", limits=as.Date(c(plotfrom, plotto)), expand=c(0,0))+
  scale_y_discrete(name="")+
  labs(title="Timelines of confirmed COVID-19 deaths in German Bundesländer",
       caption="Data from Jan-Philip Gehrcke (https://covid19-germany.appspot.com/) | Plot by @VictimOfMaths")
dev.off()
