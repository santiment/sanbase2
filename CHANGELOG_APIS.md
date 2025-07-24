# Changelog GraphQL APIs

This document describes the new GraphQL APIs for displaying changelog data for metrics and assets (projects). These APIs provide the same functionality as the live views but can be consumed by frontend applications.

## APIs Overview

Two new GraphQL APIs have been created:

1. **`metricsChangelog`** - For displaying metrics creation and deprecation events
2. **`assetsChangelog`** - For displaying asset (project) creation and hiding events

## API Details

### 1. Metrics Changelog API

**Query:** `metricsChangelog`

**Description:** Returns a paginated list of dates with metrics creation and deprecation events.

**Parameters:**
- `page` (optional, default: 1) - Page number (starts from 1)
- `pageSize` (optional, default: 20) - Number of date entries per page  
- `searchTerm` (optional) - Search term to filter metrics by name or technical identifier

**Returns:** `MetricsChangelogResult`
- `entries` - List of `MetricsChangelogDateEntry` containing:
  - `date` - Date as GraphQL Date type
  - `createdMetrics` - List of `MetricChangelogEvent` for metrics created on this date
  - `deprecatedMetrics` - List of `MetricDeprecationEvent` for metrics deprecated on this date
- `pagination` - Pagination information including `hasMore`, `totalDates`, `currentPage`, `totalPages`

**Example Query:**
```graphql
query {
  metricsChangelog(page: 1, pageSize: 20, searchTerm: "price") {
    entries {
      date
      createdMetrics {
        metric {
          humanReadableName
          metric
          docs {
            link
          }
        }
        eventTimestamp
      }
      deprecatedMetrics {
        metric {
          humanReadableName
          metric
        }
        eventTimestamp
        deprecationNote
      }
    }
    pagination {
      hasMore
      currentPage
      totalDates
      totalPages
    }
  }
}
```

### 2. Assets Changelog API

**Query:** `assetsChangelog`

**Description:** Returns a paginated list of dates with asset (project) creation and hiding events.

**Parameters:**
- `page` (optional, default: 1) - Page number (starts from 1)
- `pageSize` (optional, default: 10) - Number of date entries per page
- `searchTerm` (optional) - Search term to filter assets by name or ticker

**Returns:** `AssetsChangelogResult`
- `entries` - List of `AssetsChangelogDateEntry` containing:
  - `date` - Date as GraphQL Date type
  - `createdAssets` - List of `AssetChangelogEvent` for assets created on this date
  - `hiddenAssets` - List of `AssetHidingEvent` for assets hidden on this date
- `pagination` - Pagination information including `hasMore`, `totalDates`, `currentPage`, `totalPages`

**Example Query:**
```graphql
query {
  assetsChangelog(page: 1, pageSize: 10, searchTerm: "bitcoin") {
    entries {
      date
      createdAssets {
        asset {
          name
          ticker
          slug
          logoUrl
          description
          link
                   }
           eventTimestamp
         }
         hiddenAssets {
           asset {
             name
             ticker
             slug
           }
           eventTimestamp
           hidingReason
      }
    }
    pagination {
      hasMore
      totalDates
      currentPage
      totalPages
    }
  }
}
```

## Data Types

### Metric Information
- `humanReadableName` - Human-readable name of the metric
- `metric` - Technical metric identifier
- `docs` - List of documentation links

### Asset Information
- `name` - Name of the asset
- `ticker` - Trading ticker symbol
- `slug` - URL-safe identifier
- `logoUrl` - URL to the asset logo
- `description` - Description of the asset
- `link` - Link to the asset page on Santiment

### Event Information
- `eventTimestamp` - When the event occurred
- `deprecationNote` - Optional note for metric deprecation
- `hidingReason` - Reason for hiding an asset


## Usage Notes

1. **Pagination:** Both APIs use consistent `page`/`pageSize` parameters that support:
   - **Infinite Scroll:** Frontend increments `page` and appends results
   - **Traditional Pagination:** Frontend shows page numbers and jumps to specific pages
2. **Search:** Both APIs support filtering by relevant terms (metric names vs asset names/tickers)

## Testing

Run the tests with:
```bash
mix test test/sanbase_web/graphql/changelog/changelog_api_test.exs
```