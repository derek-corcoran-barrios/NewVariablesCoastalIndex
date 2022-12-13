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
