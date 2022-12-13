library(sf)
library(terra)
library(magrittr)
library(leaflet)
library(ggplot2)
library(dplyr)

Poligonos_Ciudades <- readRDS("Poligonos_Ciudades(2).rds")

Problemas <- Poligonos_Ciudades[st_geometry_type(Poligonos_Ciudades) != "POLYGON",]

NoProblemas <- Poligonos_Ciudades[st_geometry_type(Poligonos_Ciudades) == "POLYGON",]

Solved <- list()

for(i in 1:nrow(Problemas)){
  if(st_geometry_type(Problemas[i,]) == "MULTIPOLYGON"){
    Solved[[i]] <- Problemas[i,] %>%  
      st_cast("POLYGON",do_split = T)
  }else if(st_geometry_type(Problemas[i,]) == "GEOMETRYCOLLECTION"){
    Solved[[i]] <- st_collection_extract(Problemas[i,]) 
  }
}

Solved <- Solved %>% purrr::reduce(rbind)


Total <- rbind(NoProblemas, Solved) 

Total <- Total %>% 
  dplyr::select(Ciudad) %>% 
  tibble::rowid_to_column() %>% 
  terra::vect()

Total$Area <-  terra::expanse(Total, unit = "km")

terra::writeVector(Total, "AllCities.shp", overwrite = T)

ToZip <- list.files(pattern = "AllCities")

zip(files = ToZip, zipfile = "TotalCitiesAll.zip")

TotalBuffer <- Total %>% terra::project("+proj=laea +lon_0=-74.7070313 +lat_0=-37.5056966 +datum=WGS84 +units=m +no_defs") %>% st_as_sf() %>% st_buffer(200) %>% terra::vect() %>% terra::makeValid() %>% terra::project(Total)

terra::writeVector(TotalBuffer, "TotalBuffer.shp", overwrite = T)
ToZip <- list.files(pattern = "TotalBuffer")
zip(files = ToZip, zipfile = "BufferCitiesAll.zip")

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


### Rivers

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

saveRDS(NewVariables, "NewVariables.rds")
