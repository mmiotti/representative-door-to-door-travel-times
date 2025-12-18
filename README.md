# Representative Door-to-Door Travel Times

A scalable approach to obtain realistic, representative door-to-door travel times for walking, cycling, e-bikes, and cars taking into account elevation profiles, typical traffic conditions, and urban characteristics. The approach is explained in detail in a research paper.

Designed to work with the Open Source Routing Machine (OSRM) by providing modified .lua profiles for different modes.

In addition to the .lua profiles, two types of rasterized maps in .asc format are required with coverage for the entire street network in question:

- Elevation maps
- Impedance maps (mode-specific, time-of-day specific for cars)

The impedance maps reflect the average impact of land use properties (such as population density) and additional network properties (such as betweenness, road types) on typical travel speeds through the corresponding area with a given mode. For example, if the combined impedance in an area is 0.22 for cars, it means that travel times through an edge in that area is slowed down by (multiplied by) a factor of 1.22. If the impedance is -0.25, travel times are multiplied by 0.75. These impedance maps are built using the coefficients in the paper.

## Setup

1. Set up rasterized elevation and impedance maps. Impedance maps for Switzerland can be found [here](https://polybox.ethz.ch/index.php/s/64YgRT6Jx9aST6s).
2. Make sure .lua scripts refer the correct impedance maps and tune parameters (e.g. intersection penalties) if needed.
3. Place custom .lua scripts and impedance maps in data folder (usually where the .pbf map files are located) and set up OSRM as usual, using the custom .lua script (see [OSRM documentation](https://github.com/Project-OSRM/osrm-backend); set up e.g. [with Docker](https://hub.docker.com/r/osrm/osrm-backend/)).

## Trip overhead

The updated OSRM outputs will be more representative for the travel time on the network, but will not yet include estimates for the trip overhead (parking search, locking a bicycle, getting from the vehicle to the final destination, etc.).

As described in the article, this overhead can be estimated using proxies.

| Mode    | Constant (always add) | At origin (based on density) | At destination (based on density) |
|---------|-----------------------|------------------------------|-----------------------------------|
| Foot    | 98 s                  | -                            | -                                 |
| Bicycle | 148 s                 | 45 s/d                       | 1 s/d                             |
| Car     | 104 s                 | 88 s/d                       | 92 s/d                            |

In the above table, `d` represents the square root of the combined population and employment density in (population+employment) per km² divided by 10,000: sqrt((p+e)/10000). For example, at a trip destination with a population density of 13,000 people/km² and a job density of 7,000 jobs/km², the additional travel time overhead for a car trip is estimated to be 92 * sqrt((13000+7000)/10000) = 130 s. At an origin with a population density of 2,000 people/km² and a job density of 1,000 jobs/km², the additional overhead for a bicycle trip (regular bicycle or e-bike) is estimated to be 24 s. Densities should be measured in a 1 km² radius. The maximum combined residential and employment density found in Switzerland at a 1 km² radius is ~21,000/km².

## Reference

```
@article{miotti-hellweg-2025,
  author  = {Miotti, Marco and Hellweg, Stefanie},
  title   = {Efficient and representative door-to-door travel time estimation for planning and policy},
  journal = {Transportation},
  year    = {2025},
  volume  = {},
  number  = {},
  pages   = {},
  url = {},
  doi = {},
}
```