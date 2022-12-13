
<!-- README.md is generated from README.Rmd. Please edit that file -->

# NewVariablesCoastalIndex

<!-- badges: start -->
<!-- badges: end -->

The goal of NewVariablesCoastalIndex is to generate new layers for the
Marine Index.

## Load Packages:

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

## Read in the polygons:

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

## Fix and export

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

## Cleaned files link to GEE and shiny explorer

In order to explore the maps, you can use the following app to open a
shiny app

``` r
shiny::runGitHub("derek-corcoran-barrios/ExploradorComunas")
```

The ingested shapefiles are in this
[link](https://code.earthengine.google.com/?asset=projects/ee-my-derekcorcoran/assets/TotalCitiesAll)
as an asset in google earth engine

# CO pollution analysis

From this we analized the CO content

## Load assets and datasets

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
value to then export it as a csv to google drive

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
