# Table of contents

- [Table of contents](#table-of-contents)
  - [Overview](#overview)
    - [Implementation notes](#implementation-notes)
    - [Example Usage](#example-usage)
    - [Top ERC20 Projects](#top-erc20-projects)
    - [Top all Projects](#top-all-projects)
    - [Trending Projects](#trending-projects)
    - [Market Segment](#market-segment)
    - [Min Volume](#min-volume)
    - [Slugs](#slugs)

## Overview

There are some cases where a list of projects can nicely be expressed
programatically:
- `Top 50 ERC20 Projects` and not having to update it manually hourly/daily.
- List of projects that are currently trending - this list could change many
  times throughout the day.
- List of projects that match conditions like `trading volume over $1M and daily
  active addresses over 10,000`

On sanbase we call these watchlists screeners.

### Implementation notes

The screener and the watchlist are implemented with the same GraphQL type and
use the same APIs. The difference is how they are used. The watchlist type
(represents both screener and the normal watchlist) has two distinct ways to add
projects to it:
- via the `listItems` argument in the request. All projects added via the
  listItems are "hardcoded" to the list and they will always be a part of it.
- via the `function` argument in the request. All projects that match the
  conditions of the function at the moment of the request will be included. The
  projects that matched the request 1 hour ago but no longer do are not
  included. This allows to have only projects that match a condition at a given
  time without needing constant manual curation.

Both arguments can be used at the same time. The effect is that the result of
both of them is combined - the list of all hardcoded project is extended by the
list of all function-defined projects. This can lead to some confusing (at first
glance) behavior. If `top_all_projects` function is used with `size: 10000` then
all projects will be returned no matter what the `listItems` are.

The `listItems` in the request should not be confused with the `listItems` in
the response. In the request the meaning of `listItems` is to change the list of
hardcoded projects, while in the response the field is just holding **all**
projects, both hardcoded and dynamically chosen via the function. When working
with screeners the `listItems` argument can be omitted from the request.

In some cases adding a hardcoded project to a screener could be the desired
behavior. For example, a user can define a screener "Interesting projects" that
includes projects with high trading volume and active addresses, but at the same
time the user has a favourite project that needs to also be part of it - then it
can be hardcoded.

Note that `listItems` manipulates the full list of hardcoded projects. If you
need to just add/remove a few list items at a time the following 2 APIs can be
used instead: `addWatchlistItems` and `removeWatchlistItems`.

By default the projects that match a given condition are chosen from the pool of
all projetcts. If you want to get all the ERC20 projects with the condition
`active addresses over 10,000` the `baseProjects` argument can be used. It
controls the pool of projects the function can choose from. For example:
`baseProjects: [{watchlistSlug: "stablecoins"}]` will change it so the function
applies only to the stablecoins.

### Example Usage

Example usage of creatig a dynamic watchlist via the GraphQL API:

```gql
mutation {
  createWatchlist(
    name: "Top 50 ERC20 Projects"
    color: BLACK
    isPublic: true
    function: "{\"name\":\"top_erc20_projects\", \"args\":{\"size\":50}}"
  ) {
    listItems {
      project {
        slug
      }
    }
  }
}
```

There's also the posibility of manually changing the function through the ExAdmin.
Editing a watchlist through the panel opens this panel:
![edit watchlist exAdmin board](edit-watchlist-admin-board.png)

The function can also be edited through it.

### Top ERC20 Projects

A function that returns the top `size` ERC20 projects. The function is identified with by the name `top_erc20_projects` and accepts two arugments:

- size (required) - The number of projects in the list, sorted by marketcap. Applied after the `ignored_projects` filter.
- ignored_projects (optional) - A list of projects that are going to be excluded.

```json
{
  "name": "top_erc20_projects",
  "args": {
    "size": 50,
    "ignored_projects": ["tron", "eos"]
  }
}
```

### Top all Projects

A function that returns the top `size` projects. The function is identified with by the name `top_all_projects` and accepts one arugment:

- size (required) - The number of projects in the list, sorted by marketcap. Applied after the `ignored_projects` filter.

```json
{
  "name": "top_all_projects",
  "args": {
    "size": 100
  }
}
```

### Trending Projects

A function that returns projects that are currently trending. A project is trending if at least one of its name, ticker or slug is in the trending words.

```json
{
  "name": "trending_projects"
}
```

### Market Segment

A function that returns all projects with a given market segment. The function is identified with by the name `market_segments` and accepts one arugment:

- market_segment (required) - A string or list of strings representing market segments. If list is provided, the list will contain all projects that have at least one of the provided market segments.

```json
{
  "name": "market_segment",
  "args": {
    "market_segment": "stablecoin"
  }
}
```

```json
{
  "name": "market_segment",
  "args": {
    "market_segment": ["exchannge", "stablecoin"]
  }
}
```

### Min Volume

A function that returns all projects with trading volume over a given threshold. The function is identified with by the name `min_volume` and accepts one arugment:

- min_volume (required) - A number representing the minimal trading threhsold.

```json
{
  "name": "min_volume",
  "args": {
    "min_volume": 100000000
  }
}
```

### Slugs

A function that returns all projects with a given slug. The function is identified with by the name `slugs` and accepts one arugment:

- slugs (required) - A list of slugs

```json
{
  "name": "slugs",
  "args": {
    "slugs": ["bitcoin", "ethereum", "ripple", "santiment", "maker"]
  }
}
```
