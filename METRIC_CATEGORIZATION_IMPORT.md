# Metric Categorization Import Guide

This guide explains how to import metric categories and groups from production.

## Quick Start

Run the following command in an IEx console:

```elixir
# Connect to your development database
iex -S mix

# Import and create categories/groups in one step
Sanbase.Metric.Category.Scripts.import_and_fill()
```

## What It Does

The script performs the following operations:

1. **Queries Production GraphQL API**: Fetches the `getOrderedMetrics` query from `https://app.santiment.net/graphql`
2. **Extracts Categories and Groups**: Analyzes the metrics to identify unique categories and groups
3. **Calculates Display Order**: Determines the display order based on the minimum `displayOrder` of metrics within each category/group
4. **Creates/Updates Database Records**: Inserts new categories/groups or updates existing ones

## Usage Options

### Option 1: Import and Fill (Recommended)

```elixir
# Use production API (default)
Sanbase.Metric.Category.Scripts.import_and_fill()

# Use staging API
Sanbase.Metric.Category.Scripts.import_and_fill("https://app-stage.santiment.net/graphql")
```

### Option 2: Two-Step Process

```elixir
# Step 1: Fetch and save data to /tmp/ordered_metrics.json
Sanbase.Metric.Category.Scripts.import_ui_order_from_prod()

# Step 2: Process the saved data and create DB records
Sanbase.Metric.Category.Scripts.fill_categories_from_ui_order()
```

### Option 3: Use Saved Data

```elixir
# If you already have the JSON file
Sanbase.Metric.Category.Scripts.fill_categories_from_ui_order("/path/to/ordered_metrics.json")
```

## Features

- **Idempotent**: Running multiple times won't create duplicates
- **Updates Existing Records**: Updates `display_order` if category/group already exists
- **Transactional**: All changes happen in a single database transaction
- **Error Handling**: Detailed error messages if the API call fails

## Troubleshooting

### API Connection Issues

If you get connection errors:

```elixir
# Check if the API is accessible
Req.get!("https://app.santiment.net/graphql")
```

### Missing Categories/Groups

Ensure the production API returns the expected data structure:

```elixir
{:ok, data} = Sanbase.Metric.Category.Scripts.import_ui_order_from_prod()
IO.inspect(data)
```

### Database Errors

Check if the tables exist:

```elixir
Sanbase.Repo.all(Sanbase.Metric.Category.MetricCategory)
Sanbase.Repo.all(Sanbase.Metric.Category.MetricGroup)
```