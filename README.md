
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
