13/12, 2022

- <a href="#1-newvariablescoastalindex"
  id="toc-1-newvariablescoastalindex">1 NewVariablesCoastalIndex</a>
  - <a href="#11-load-packages" id="toc-11-load-packages">1.1 Load
    Packages:</a>
  - <a href="#12-read-in-the-polygons" id="toc-12-read-in-the-polygons">1.2
    Read in the polygons:</a>
  - <a href="#13-fix-and-export" id="toc-13-fix-and-export">1.3 Fix and
    export</a>
  - <a href="#14-cleaned-files-link-to-gee-and-shiny-explorer"
    id="toc-14-cleaned-files-link-to-gee-and-shiny-explorer">1.4 Cleaned
    files link to GEE and shiny explorer</a>
- <a href="#2-co-pollution-analysis" id="toc-2-co-pollution-analysis">2 CO
  pollution analysis</a>
  - <a href="#21-load-assets-and-datasets"
    id="toc-21-load-assets-and-datasets">2.1 Load assets and datasets</a>
- <a href="#3-water-bodies-persistence-analysis"
  id="toc-3-water-bodies-persistence-analysis">3 Water bodies persistence
  analysis</a>
  - <a href="#31-data-preparation" id="toc-31-data-preparation">3.1 Data
    preparation</a>
  - <a href="#32-analysis" id="toc-32-analysis">3.2 Analysis</a>
- <a href="#4-data-harmonization" id="toc-4-data-harmonization">4 Data
  harmonization</a>
- <a href="#5-final-table" id="toc-5-final-table">5 Final table</a>

<!-- README.md is generated from README.Rmd. Please edit that file -->

# 1 NewVariablesCoastalIndex

<!-- badges: start -->
<!-- badges: end -->

The goal of NewVariablesCoastalIndex is to generate new layers for the
Marine Index.

## 1.1 Load Packages:

First we load the needed packages

``` r
## sf and terra to manage shapefiles
library(sf)
library(terra)
## to use the pipe operator
library(magrittr)
## If we need to generate interactive maps
library(leaflet)
## ggplo2 and tidyterra to generate maps if needed
library(ggplot2)
library(tidyterra)
## For data wrangling
library(dplyr)
```

## 1.2 Read in the polygons:

First we read in the polygons to be used

``` r
Poligonos_Ciudades <- readRDS("Poligonos_Ciudades.rds")
```

This considers 147 locations from Chile read as SF, however we need to
make sure that they are all polygons, if not they wont be properly
ingested by google earth engine

``` r
Types <- Poligonos_Ciudades 

Types$GeomType <- st_geometry_type(Types)

Types <- Types %>% 
  as.data.frame() %>% 
  dplyr::select(GeomType) %>% 
  group_by(GeomType) %>% 
  summarise(n = n())
```

This object shows us that we actually have 11 Multipolygons and 1
geometry collection.

``` r
knitr::kable(Types)
```

| GeomType           |   n |
|:-------------------|----:|
| POLYGON            | 135 |
| MULTIPOLYGON       |  11 |
| GEOMETRYCOLLECTION |   1 |

We need to separate the geometry collections and multipolygons into
polygons to export to shapefiles and zip files in order to add them to
google earth engine but before that we will separate each feature in
what already is a polygon and what is not so that we dont try to
transform something that is not needed

``` r
Problems <- Poligonos_Ciudades[st_geometry_type(Poligonos_Ciudades) != "POLYGON",]

NoProblems <- Poligonos_Ciudades[st_geometry_type(Poligonos_Ciudades) == "POLYGON",]
```

We have 12 features to change

## 1.3 Fix and export

This code will grab all multipolygon or geometry collection and apply
the proper transformation:

``` r
Solved <- list()

for(i in 1:nrow(Problems)){
  if(st_geometry_type(Problems[i,]) == "MULTIPOLYGON"){
    Solved[[i]] <- Problems[i,] %>%  
      st_cast("POLYGON",do_split = T)
  }else if(st_geometry_type(Problems[i,]) == "GEOMETRYCOLLECTION"){
    Solved[[i]] <- st_collection_extract(Problems[i,]) 
  }
}

Solved <- Solved %>% purrr::reduce(rbind)
```

The solved geometries had to be split sometimes, that is why we go from
12 features to 20 features. Now we export them as a shapefile and zip it
to be ingested by Google Earth Engine, adding an ID and Area, so that
then cities that are covered by multiple polygons (eg. cities that are
split by a river) can be then summarized weighted by their area

``` r
Total <- rbind(NoProblems, Solved) 

Total <- Total %>% 
  dplyr::select(Ciudad) %>% 
  tibble::rowid_to_column() %>% 
  terra::vect()

Total$Area <-  terra::expanse(Total, unit = "km")

terra::writeVector(Total, "AllCities.shp", overwrite = T)

ToZip <- list.files(pattern = "AllCities")

zip(files = ToZip, zipfile = "TotalCitiesAll.zip")
```

## 1.4 Cleaned files link to GEE and shiny explorer

In order to explore the maps, you can use the following app to open a
shiny app

``` r
shiny::runGitHub("derek-corcoran-barrios/ExploradorComunas")
```

The ingested shapefiles are in this
[link](https://code.earthengine.google.com/?asset=projects/ee-my-derekcorcoran/assets/TotalCitiesAll)
as an asset in google earth engine

# 2 CO pollution analysis

From this we analized the CO content

## 2.1 Load assets and datasets

We load the cities shapefiles and also the copernicus CO concentration
from this
[link](https://developers.google.com/earth-engine/datasets/catalog/COPERNICUS_S5P_NRTI_L3_CO),
this last layer was filtered from January 1st of 2018 to December 31st
of 2019 to encompass two years

``` js
var fc = ee.FeatureCollection("projects/ee-my-derekcorcoran/assets/TotalCitiesAll");

var collection = ee.ImageCollection('COPERNICUS/S5P/NRTI/L3_CO')
  .select('CO_column_number_density')
  .filterDate('2018-01-01', '2019-12-31');
```

Then we generate a composite image where each pixel has either the
median, the 90th percentile or the 10th percentile

``` js
// Reduce the collection by taking the median.
var median = collection.median();

var p90 = collection.reduce(ee.Reducer.percentile([90]));

var p10 = collection.reduce(ee.Reducer.percentile([10]));
```

We then use reduce regions in order to get the median of all pixels for
each polygon for each variable, that is we get the median of the
medians, or the median of the 90th percentile and the median of the 10th
percentile for each variable

``` js
var cityCOMedian = median.reduceRegions({
  collection: fc,
  reducer: ee.Reducer.median(),
  scale: 1113.1949079327357 // the resolution of the GRIDMET dataset
});

var cityCOp90 = p90.reduceRegions({
  collection: fc,
  reducer: ee.Reducer.median(),
  scale: 1113.1949079327357 // the resolution of the GRIDMET dataset
});

var cityCOp10 = p10.reduceRegions({
  collection: fc,
  reducer: ee.Reducer.median(),
  scale: 1113.1949079327357 // the resolution of the GRIDMET dataset
});
```

Finally we only retain the name of the city, the area and the median
value to then export it as a csv to google drive, the link to all the
analysis is
[here](https://code.earthengine.google.com/48f728b33dbd2dade85d2d208915fb1d?noload=true)

``` js
var multiProp = cityCOMedian.select({
  propertySelectors: ['Ciudad', 'Area', 'median'],
  retainGeometry: false
});

var multiPropP90 = cityCOp90.select({
  propertySelectors: ['Ciudad', 'Area', 'median'],
  retainGeometry: false
});

var multiPropP10 = cityCOp10.select({
  propertySelectors: ['Ciudad', 'Area', 'median'],
  retainGeometry: false
});




Export.table.toDrive({
  collection: multiProp,
  description: 'medianHighRes',
  folder: 'RegulatingServicesLayers',
  fileFormat: 'csv'
});

Export.table.toDrive({
  collection: multiPropP90,
  description: 'p90COHighRes',
  folder: 'RegulatingServicesLayers',
  fileFormat: 'csv'
});

Export.table.toDrive({
  collection: multiPropP10,
  description: 'p10COHighRes',
  folder: 'RegulatingServicesLayers',
  fileFormat: 'csv'
});
```

# 3 Water bodies persistence analysis

## 3.1 Data preparation

The shapefile we used before, unfortunately crops out all water bodies,
so we have to generate a buffer, in this case we decided on 200 meter
buffers, this will go into lakes, rivers, but also the sea.
Unfortunatelly the spatvector generated by this had topological errors,
so we had to transform the SpatVector into an sf, and then project to an
equal area projection in meters to be able to do that

``` r
TotalBuffer <- Total %>% terra::project("+proj=laea +lon_0=-74.7070313 +lat_0=-37.5056966 +datum=WGS84 +units=m +no_defs") %>% st_as_sf() %>% st_buffer(200) %>% terra::vect() %>% terra::makeValid() %>% terra::project(Total)
```

And then this was exported and added to google earth engine

``` r
terra::writeVector(TotalBuffer, "TotalBuffer.shp", overwrite = T)
ToZip <- list.files(pattern = "TotalBuffer")
zip(files = ToZip, zipfile = "BufferCitiesAll.zip")
```

The asset can be seen in the following
[link](https://code.earthengine.google.com/?asset=projects/ee-my-derekcorcoran/assets/BufferCitiesAll)

## 3.2 Analysis

Just as before we wanted to get an idea of the median, 90th and 10th
percentile for this dataset, the whole analysis can be found
[here](https://code.earthengine.google.com/5dbbea7224bf7f483d125ed5bebacf7f?noload=true).

First we load the datasets

``` js
var fc = ee.FeatureCollection("projects/ee-my-derekcorcoran/assets/BufferCitiesAll");

var dataset = ee.ImageCollection('JRC/GSW1_4/MonthlyRecurrence')
.select('monthly_recurrence');
```

Just as before que calculate the median, 90th percentile and the 10th
percentile, but we also have to unmask, so that all areas that never
have water have a value of 0

``` js
var median = dataset.median();

var p90 = dataset.reduce(ee.Reducer.percentile([90]));

var p10 = dataset.reduce(ee.Reducer.percentile([10]));

var newDataMedian = median.unmask(0)

var newDataP90 = p90.unmask(0)

var newDataP10 = p10.unmask(0)
```

We then calculate the mean of the median, 90th percentile and 10th
percentile instead of the median of it as done before, because those
where always 0 for all cities

``` js
var cityRiverMedian = newDataMedian.reduceRegions({
  collection: fc,
  reducer: ee.Reducer.mean(),
  scale: 30 // the resolution of the GRIDMET dataset
});

var cityRiverp90 = newDataP90.reduceRegions({
  collection: fc,
  reducer: ee.Reducer.mean(),
  scale: 30 // the resolution of the GRIDMET dataset
});

var cityRiverp10 = newDataP10.reduceRegions({
  collection: fc,
  reducer: ee.Reducer.mean(),
  scale: 30 // the resolution of the GRIDMET dataset
});
```

Finally we select the needed variables and export them all

``` js
var multiProp = cityRiverMedian.select({
  propertySelectors: ['Ciudad', 'Area', 'mean'],
  retainGeometry: false
});

var multiPropP90 = cityRiverp90.select({
  propertySelectors: ['Ciudad', 'Area', 'mean'],
  retainGeometry: false
});

var multiPropP10 = cityRiverp10.select({
  propertySelectors: ['Ciudad', 'Area', 'mean'],
  retainGeometry: false
});




Export.table.toDrive({
  collection: multiProp,
  description: 'medianRiversHighRes',
  folder: 'RegulatingServicesLayers',
  fileFormat: 'csv'
});

Export.table.toDrive({
  collection: multiPropP90,
  description: 'p90RiversHighRes',
  folder: 'RegulatingServicesLayers',
  fileFormat: 'csv'
});

Export.table.toDrive({
  collection: multiPropP10,
  description: 'p10RiversHighRes',
  folder: 'RegulatingServicesLayers',
  fileFormat: 'csv'
});
```

# 4 Data harmonization

We now get all the datasets together, first the CO dataset

``` r
median <- readr::read_csv("medianHighRes.csv") %>% 
  janitor::clean_names() %>% 
  dplyr::select(system_index, area, ciudad, median)

p90 <- readr::read_csv("p90COHighRes.csv") %>% 
  janitor::clean_names() %>% 
  dplyr::select(system_index, area, ciudad, median) %>% 
  rename(CO_p90 = median) %>% 
  dplyr::select(system_index, area, ciudad, CO_p90)

p10 <- readr::read_csv("p10COHighRes.csv")%>% 
  janitor::clean_names() %>% 
  dplyr::select(system_index, area, ciudad, median) %>% 
  rename(CO_p10 = median) %>% 
  dplyr::select(system_index, area, ciudad, CO_p10)

NewVariables <- list(median, p90, p10) %>% 
  purrr::reduce(full_join) %>% 
  dplyr::select(-system_index) %>% 
  dplyr::group_by(ciudad) %>%
  summarise_at(c("median", "CO_p90", "CO_p10"), ~weighted.mean(.x, w = area), na.rm = TRUE) %>% 
  rename(CO_median = median)
```

Then we add the River dataset

``` r
median <- readr::read_csv("medianRiversHighRes.csv") %>% 
  janitor::clean_names() %>% 
  dplyr::select(system_index, area, ciudad, mean)

p90 <- readr::read_csv("p90RiversHighRes.csv") %>% 
  janitor::clean_names() %>% 
  dplyr::select(system_index, area, ciudad, mean) %>% 
  rename(Rivers_p90 = mean) %>% 
  dplyr::select(system_index, area, ciudad, Rivers_p90)

p10 <- readr::read_csv("p10RiversHighRes.csv")%>% 
  janitor::clean_names() %>% 
  dplyr::select(system_index, area, ciudad, mean) %>% 
  rename(Rivers_p10 = mean) %>% 
  dplyr::select(system_index, area, ciudad, Rivers_p10)

NewVariables2 <- list(median, p90, p10) %>% 
  purrr::reduce(full_join) %>% 
  dplyr::select(-system_index) %>% 
  dplyr::group_by(ciudad) %>%
  summarise_at(c("mean", "Rivers_p90", "Rivers_p10"), ~weighted.mean(.x, w = area), na.rm = TRUE) %>% 
  rename(Rivers_median = mean)


NewVariables <- full_join(NewVariables, NewVariables2)
```

And we export them as an Rds

``` r
saveRDS(NewVariables, "NewVariables.rds")
```

# 5 Final table

Here you can see the final result

| ciudad                         | CO_median |    CO_p90 |    CO_p10 | Rivers_median | Rivers_p90 | Rivers_p10 |
|:-------------------------------|----------:|----------:|----------:|--------------:|-----------:|-----------:|
| algarrobo                      | 0.0211060 | 0.0260233 | 0.0174491 |     7.3210753 |  7.9340202 |  6.3508514 |
| alto hospicio                  | 0.0238701 | 0.0284878 | 0.0202033 |     0.0009474 |  0.0015841 |  0.0007015 |
| angol                          | 0.0194760 | 0.0244446 | 0.0161963 |     0.0016972 |  0.0174240 |  0.0000000 |
| antofagasta                    | 0.0223343 | 0.0264619 | 0.0182114 |     6.2810797 |  6.6048357 |  5.5371620 |
| arica                          | 0.0256895 | 0.0305772 | 0.0215565 |     3.9564916 |  4.2410060 |  3.1722148 |
| calama                         | 0.0185084 | 0.0220480 | 0.0161706 |     0.0188870 |  0.0231587 |  0.0068554 |
| calbuco                        | 0.0193507 | 0.0241195 | 0.0159988 |    19.7031537 | 21.8646452 |  0.0000000 |
| canete                         | 0.0199206 | 0.0244745 | 0.0163002 |     0.0000000 |  0.0000000 |  0.0000000 |
| carahue                        | 0.0193214 | 0.0241416 | 0.0158459 |     4.3889445 |  5.1792723 |  3.7804511 |
| cartagena                      | 0.0213994 | 0.0258498 | 0.0174779 |     5.3742760 |  6.0059164 |  4.4809630 |
| casablanca                     | 0.0207204 | 0.0246440 | 0.0173504 |     0.0000000 |  0.0123846 |  0.0000000 |
| castro                         | 0.0189239 | 0.0233831 | 0.0160355 |     8.8806018 | 10.3462748 |  0.0000000 |
| cauquenes                      | 0.0202046 | 0.0246191 | 0.0171328 |     0.0282616 |  0.3994211 |  0.0029429 |
| cerro navia                    | 0.0224033 | 0.0263228 | 0.0184690 |     0.0188348 |  0.0452155 |  0.0022336 |
| chicureo                       | 0.0223907 | 0.0265413 | 0.0186404 |     0.1488401 |  0.1706932 |  0.1034626 |
| chillan                        | 0.0205856 | 0.0247438 | 0.0170632 |     0.0034402 |  0.0190068 |  0.0010788 |
| cochrane                       | 0.0179885 | 0.0223642 | 0.0142596 |     0.1273995 |  0.2364681 |  0.0000000 |
| colina                         | 0.0218623 | 0.0259901 | 0.0176968 |     0.0580951 |  0.0937721 |  0.0245960 |
| combarbala                     | 0.0190786 | 0.0223900 | 0.0161754 |     0.0000000 |  0.0000000 |  0.0000000 |
| concepcion                     | 0.0207347 | 0.0250962 | 0.0171471 |     3.1573005 |  3.8314815 |  2.6240100 |
| concon                         | 0.0212502 | 0.0269359 | 0.0168737 |     7.5589641 |  8.1271141 |  6.7199629 |
| constitucion                   | 0.0208646 | 0.0253088 | 0.0162532 |    13.4681004 | 14.3411034 | 12.1618829 |
| conurbacion chillan            | 0.0205881 | 0.0247398 | 0.0171298 |     0.0018891 |  0.0150407 |  0.0008308 |
| conurbacion la serena coquimbo | 0.0216728 | 0.0253516 | 0.0181288 |     4.3235199 |  4.6746098 |  3.8241706 |
| copiapo                        | 0.0205734 | 0.0238836 | 0.0178496 |     0.0202106 |  0.0294476 |  0.0000721 |
| coquimbo                       | 0.0217843 | 0.0258996 | 0.0182223 |     3.2571886 |  3.6695381 |  2.8098598 |
| coronel                        | 0.0203651 | 0.0261508 | 0.0162593 |     7.3460723 |  8.2064669 |  6.4805485 |
| coyhaique                      | 0.0176327 | 0.0217765 | 0.0140896 |     0.0377211 |  0.2528087 |  0.0000000 |
| curacavi                       | 0.0212333 | 0.0250041 | 0.0178726 |     0.0008747 |  0.0039363 |  0.0000000 |
| curanilahue                    | 0.0192897 | 0.0242991 | 0.0161843 |     0.0334418 |  0.1290081 |  0.0058663 |
| curico                         | 0.0210721 | 0.0253249 | 0.0175229 |     0.0540578 |  0.2451264 |  0.0038703 |
| donihue                        | 0.0209399 | 0.0253330 | 0.0176948 |     0.0000000 |  0.0000000 |  0.0000000 |
| el monte                       | 0.0215589 | 0.0258353 | 0.0181155 |     0.0000000 |  0.0000000 |  0.0000000 |
| el quisco                      | 0.0213403 | 0.0263311 | 0.0171982 |     6.8375817 |  7.5944590 |  5.8418663 |
| el tabo                        | 0.0212065 | 0.0260083 | 0.0172673 |     3.6929061 |  4.1681139 |  3.0494725 |
| frutillar                      | 0.0189726 | 0.0234073 | 0.0159260 |     4.5882325 |  5.1014109 |  0.0000000 |
| futrono                        | 0.0192180 | 0.0242406 | 0.0155672 |     0.0000000 |  0.0000000 |  0.0000000 |
| gorbea                         | 0.0193479 | 0.0242928 | 0.0162851 |     0.0155579 |  0.0466015 |  0.0000000 |
| gran concepcion                | 0.0206536 | 0.0255737 | 0.0167955 |     9.1877988 | 10.3996894 |  7.9334136 |
| gran santiago                  | 0.0221621 | 0.0262966 | 0.0184781 |     0.1640084 |  0.2727412 |  0.0642561 |
| gran temuco                    | 0.0196513 | 0.0242284 | 0.0165313 |     1.4488993 |  2.5165308 |  0.7933696 |
| gran valparaiso                | 0.0214805 | 0.0261350 | 0.0178772 |     3.6879339 |  3.8942553 |  3.3754913 |
| graneros                       | 0.0213014 | 0.0253240 | 0.0178997 |     0.0916071 |  0.1433946 |  0.0000000 |
| hijuelas                       | 0.0211467 | 0.0252738 | 0.0176925 |     0.0000000 |  0.0000000 |  0.0000000 |
| hualane                        | 0.0203551 | 0.0250343 | 0.0170111 |     0.6558013 |  0.9384668 |  0.3493404 |
| huasco                         | 0.0216387 | 0.0255505 | 0.0181470 |    11.0348756 | 12.2077408 |  9.7148685 |
| huechuraba                     | 0.0228888 | 0.0273887 | 0.0191705 |     0.1417477 |  0.1707572 |  0.0532632 |
| huepil                         | 0.0194590 | 0.0236023 | 0.0160718 |     0.0000000 |  0.0000000 |  0.0000000 |
| illapel                        | 0.0203328 | 0.0241219 | 0.0176472 |     0.0044197 |  0.0061875 |  0.0027991 |
| iquique                        | 0.0240778 | 0.0292123 | 0.0202233 |     9.8551891 | 10.6711647 |  8.5659551 |
| isla de maipo                  | 0.0213461 | 0.0250257 | 0.0174984 |     0.0000000 |  0.0000000 |  0.0000000 |
| la calera                      | 0.0213762 | 0.0256763 | 0.0174649 |     0.4166836 |  1.1377456 |  0.1025912 |
| la cruz                        | 0.0216327 | 0.0256023 | 0.0181359 |     0.0105729 |  0.0381797 |  0.0000000 |
| la florida                     | 0.0220305 | 0.0262223 | 0.0182116 |     0.0187783 |  0.0429603 |  0.0084578 |
| la granja                      | 0.0221807 | 0.0263837 | 0.0186202 |     0.0094277 |  0.0107828 |  0.0046706 |
| la reina                       | 0.0222753 | 0.0269881 | 0.0171786 |     0.0210723 |  0.0245561 |  0.0128869 |
| la serena                      | 0.0216054 | 0.0250717 | 0.0182514 |     1.0799670 |  1.2869798 |  0.8880267 |
| la union                       | 0.0195776 | 0.0237027 | 0.0161771 |     0.0000000 |  0.0114435 |  0.0000000 |
| lampa                          | 0.0213806 | 0.0250040 | 0.0176520 |     0.0038492 |  0.0069564 |  0.0000000 |
| laraquete                      | 0.0196547 | 0.0247952 | 0.0157620 |     2.9998119 |  5.1097291 |  1.8407250 |
| las condes                     | 0.0225078 | 0.0269353 | 0.0180659 |     0.0405150 |  0.0575447 |  0.0173487 |
| lebu                           | 0.0196932 | 0.0247227 | 0.0160333 |     5.3091601 |  5.9672056 |  4.4212211 |
| limache                        | 0.0219024 | 0.0257783 | 0.0181771 |     0.0021951 |  0.0054879 |  0.0007683 |
| linares                        | 0.0208033 | 0.0249980 | 0.0167731 |     0.0000000 |  0.0000000 |  0.0000000 |
| llanquihue                     | 0.0191060 | 0.0239910 | 0.0155667 |    12.0100600 | 13.8973847 |  0.0000000 |
| lo barnechea                   | 0.0223722 | 0.0261485 | 0.0178884 |     0.3593153 |  0.5722259 |  0.2045808 |
| lo espejo                      | 0.0220265 | 0.0262362 | 0.0188711 |     0.0000000 |  0.0011356 |  0.0000000 |
| lo miranda                     | 0.0208120 | 0.0245668 | 0.0171731 |     0.1160485 |  0.1463689 |  0.0970336 |
| lo prado                       | 0.0222304 | 0.0264417 | 0.0186172 |     0.0000000 |  0.0000000 |  0.0000000 |
| longavi                        | 0.0204246 | 0.0244571 | 0.0171909 |     0.0000000 |  0.0611364 |  0.0000000 |
| los andes                      | 0.0200186 | 0.0236362 | 0.0170184 |     0.7474496 |  1.2200557 |  0.4300124 |
| los angeles                    | 0.0197166 | 0.0244904 | 0.0165062 |     0.0292008 |  0.0390717 |  0.0135449 |
| los vilos                      | 0.0212504 | 0.0256023 | 0.0169415 |     9.6556521 | 10.4632323 |  8.0411076 |
| lota                           | 0.0198802 | 0.0252464 | 0.0153205 |    11.6890970 | 12.4584118 | 10.2764360 |
| machali                        | 0.0205783 | 0.0249434 | 0.0171227 |     0.0000000 |  0.0016141 |  0.0000000 |
| macul                          | 0.0222955 | 0.0273833 | 0.0187322 |     0.0450304 |  0.0835810 |  0.0000000 |
| maipu                          | 0.0217828 | 0.0257205 | 0.0184637 |     0.0094550 |  0.0130488 |  0.0012574 |
| mejillones                     | 0.0238202 | 0.0279300 | 0.0207242 |    14.1014091 | 14.4180804 | 12.9873487 |
| melipilla                      | 0.0212980 | 0.0251267 | 0.0182536 |     0.0000000 |  0.0000000 |  0.0000000 |
| monte aguila                   | 0.0197104 | 0.0244992 | 0.0162920 |     0.0000000 |  0.0000000 |  0.0000000 |
| monte patria                   | 0.0202078 | 0.0236656 | 0.0170485 |     0.0462686 |  0.1713353 |  0.0000000 |
| nacimiento                     | 0.0198487 | 0.0245365 | 0.0162889 |     1.2338955 |  1.5649625 |  0.9659288 |
| nueva imperial                 | 0.0198914 | 0.0245334 | 0.0165495 |     2.0921532 |  2.6018997 |  1.4710254 |
| nunoa                          | 0.0226976 | 0.0274662 | 0.0186056 |     0.0048402 |  0.0109177 |  0.0000000 |
| osorno                         | 0.0194754 | 0.0236647 | 0.0161715 |     1.0718033 |  1.6673102 |  0.0000000 |
| ovalle                         | 0.0209102 | 0.0243675 | 0.0177317 |     0.0134694 |  0.0806152 |  0.0019003 |
| padre las casas                | 0.0196513 | 0.0240465 | 0.0164589 |     2.8295042 |  4.1527112 |  1.8083617 |
| panguipulli                    | 0.0192961 | 0.0241131 | 0.0154773 |     1.9810608 |  2.4252899 |  0.0000000 |
| pedro aguirre cerda            | 0.0222845 | 0.0266625 | 0.0188947 |     0.0012681 |  0.0018493 |  0.0000000 |
| penalolen                      | 0.0220144 | 0.0264283 | 0.0175281 |     0.0076070 |  0.0188645 |  0.0042076 |
| penco                          | 0.0203374 | 0.0265821 | 0.0167092 |     7.5924229 |  8.1308738 |  6.6412113 |
| pitrufquen                     | 0.0195900 | 0.0242242 | 0.0162934 |     3.1158867 |  4.0282153 |  2.2301820 |
| porvenir                       | 0.0178889 | 0.0228883 | 0.0135978 |     9.8211259 | 11.3142239 |  0.0000000 |
| pozo almonte                   | 0.0224016 | 0.0261250 | 0.0193279 |     0.0347611 |  0.0454514 |  0.0236206 |
| providencia                    | 0.0228197 | 0.0279350 | 0.0190789 |     0.0388582 |  0.0752951 |  0.0010244 |
| pucon                          | 0.0189992 | 0.0239962 | 0.0153468 |     2.2206832 |  2.4275495 |  0.0000000 |
| pudahuel                       | 0.0220742 | 0.0261884 | 0.0184182 |     0.0047314 |  0.0099548 |  0.0000000 |
| puente alto                    | 0.0215258 | 0.0252343 | 0.0176578 |     0.1139369 |  0.2106318 |  0.0431714 |
| puerto montt                   | 0.0191158 | 0.0240259 | 0.0156972 |     3.9751908 |  5.4110006 |  0.0000000 |
| puerto natales                 | 0.0178714 | 0.0223800 | 0.0134570 |     6.6403337 |  7.8256791 |  0.0000000 |
| puerto varas                   | 0.0187140 | 0.0231178 | 0.0156641 |     6.9254447 |  7.8604018 |  0.0000000 |
| puerto williams                | 0.0166735 | 0.0223551 | 0.0130043 |    11.9553063 | 20.5114992 |  0.0000000 |
| punitaqui                      | 0.0204282 | 0.0242129 | 0.0175465 |     0.0000000 |  0.0000000 |  0.0000000 |
| punta arenas                   | 0.0177570 | 0.0232529 | 0.0132643 |     8.9013536 | 13.6648689 |  0.0000000 |
| purranque                      | 0.0189733 | 0.0234465 | 0.0159271 |     0.0000000 |  0.0000000 |  0.0000000 |
| putaendo                       | 0.0193558 | 0.0230209 | 0.0158087 |     0.0000000 |  0.0000000 |  0.0000000 |
| putre                          | 0.0171533 | 0.0220489 | 0.0143836 |     0.0000000 |  0.0000000 |  0.0000000 |
| quillota                       | 0.0218512 | 0.0259639 | 0.0181404 |     0.2035474 |  0.4720464 |  0.0442541 |
| quilpue                        | 0.0216225 | 0.0257263 | 0.0184087 |     0.0036833 |  0.0212369 |  0.0016025 |
| quinta de tilcoco              | 0.0209177 | 0.0247657 | 0.0169735 |     0.0000000 |  0.0000000 |  0.0000000 |
| quinta normal                  | 0.0226553 | 0.0269375 | 0.0187201 |     0.1707603 |  0.3043150 |  0.0666044 |
| quintero                       | 0.0213759 | 0.0275873 | 0.0173526 |    14.4618360 | 15.4676399 | 12.9805186 |
| rancagua                       | 0.0209128 | 0.0249497 | 0.0175141 |     0.0712017 |  0.1638344 |  0.0323884 |
| renaico                        | 0.0196650 | 0.0242460 | 0.0159982 |     1.1804811 |  1.8579196 |  0.7034134 |
| renca                          | 0.0227713 | 0.0267944 | 0.0186317 |     0.1484738 |  0.2741654 |  0.0480799 |
| rengo                          | 0.0210681 | 0.0250141 | 0.0171783 |     0.0078051 |  0.0116152 |  0.0042170 |
| rio bueno                      | 0.0193789 | 0.0235177 | 0.0163694 |     1.1240928 |  1.8968010 |  0.0000000 |
| rio negro                      | 0.0191468 | 0.0234876 | 0.0162640 |     0.0000000 |  0.0000000 |  0.0000000 |
| salamanca                      | 0.0195847 | 0.0232397 | 0.0167873 |     0.0686996 |  0.1187793 |  0.0232204 |
| san antonio                    | 0.0213554 | 0.0261383 | 0.0168746 |     3.8379532 |  4.6939598 |  2.9345796 |
| san bernardo                   | 0.0215366 | 0.0251892 | 0.0180643 |     0.1064481 |  0.1476609 |  0.0629096 |
| san carlos                     | 0.0203328 | 0.0243938 | 0.0171473 |     0.0124654 |  0.0310627 |  0.0075841 |
| san felipe                     | 0.0205517 | 0.0241912 | 0.0167379 |     0.4161850 |  0.7539428 |  0.2128088 |
| san fernando                   | 0.0203695 | 0.0245006 | 0.0168882 |     0.0016351 |  0.0115797 |  0.0000000 |
| san miguel                     | 0.0222798 | 0.0268219 | 0.0189608 |     0.0000000 |  0.0000000 |  0.0000000 |
| santa cruz                     | 0.0209255 | 0.0250660 | 0.0168802 |     0.3722570 |  0.8559498 |  0.1001622 |
| santa maria                    | 0.0205776 | 0.0242380 | 0.0165787 |     0.0381213 |  0.0459157 |  0.0235247 |
| santo domingo                  | 0.0213140 | 0.0262000 | 0.0174582 |     3.3870911 |  3.6032057 |  2.6243220 |
| talagante                      | 0.0216751 | 0.0255771 | 0.0182300 |     0.1284560 |  0.1736495 |  0.0955152 |
| talca                          | 0.0209286 | 0.0250995 | 0.0174395 |     0.4100492 |  0.7175822 |  0.2366561 |
| talcahuano                     | 0.0213665 | 0.0268742 | 0.0168780 |     5.2828550 |  6.3360348 |  4.3098246 |
| taltal                         | 0.0218270 | 0.0262417 | 0.0179266 |     9.3938022 |  9.8999821 |  8.4794780 |
| temuco                         | 0.0196301 | 0.0242393 | 0.0165317 |     0.9861055 |  1.6431968 |  0.5611451 |
| teno                           | 0.0207792 | 0.0246295 | 0.0171643 |     0.0726957 |  0.0972486 |  0.0458320 |
| tocopilla                      | 0.0228824 | 0.0276938 | 0.0187571 |    20.0580486 | 21.5900521 | 18.2400561 |
| tome                           | 0.0201571 | 0.0267307 | 0.0154819 |     5.5403080 |  5.8805199 |  4.9465551 |
| traiguen                       | 0.0193978 | 0.0238127 | 0.0162478 |     0.0961817 |  0.1905270 |  0.0402861 |
| valdivia                       | 0.0194003 | 0.0246837 | 0.0159266 |     8.1015729 |  9.1158731 |  0.0000000 |
| vallenar                       | 0.0205764 | 0.0238738 | 0.0175055 |     0.0000000 |  0.0000000 |  0.0000000 |
| valparaiso                     | 0.0212224 | 0.0269690 | 0.0176734 |     4.9126282 |  5.0925920 |  4.4433610 |
| victoria                       | 0.0193857 | 0.0240716 | 0.0162826 |     0.0145064 |  0.0504505 |  0.0019695 |
| vicuna                         | 0.0193564 | 0.0229572 | 0.0165184 |     0.4721712 |  0.7499587 |  0.1495338 |
| villa alegre                   | 0.0206878 | 0.0246751 | 0.0171035 |     0.0000000 |  0.0000000 |  0.0000000 |
| villa alemana                  | 0.0217177 | 0.0256116 | 0.0184403 |     0.0005131 |  0.0013779 |  0.0000000 |
| villarrica                     | 0.0190207 | 0.0239842 | 0.0152139 |     4.6535016 |  5.5753645 |  0.0000000 |
| vina del mar                   | 0.0215906 | 0.0260922 | 0.0178354 |     2.5137121 |  2.8255662 |  2.2160519 |
| vitacura                       | 0.0230841 | 0.0276137 | 0.0187128 |     0.0266993 |  0.0414411 |  0.0126023 |
