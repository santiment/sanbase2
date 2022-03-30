```sql
CREATE FUNCTION filter_by_slug AS (slug) -> (asset_id = (SELECT asset_id FROM asset_metadata FINAL where name = lower(slug) LIMIT 1));
CREATE FUNCTION filter_by_metric AS (metric) -> (metric_id = (SELECT metric_id FROM metric_metadata FINAL where name = lower(metric) LIMIT 1));
CREATE FUNCTION get_asset_id AS (slug) -> (SELECT asset_id FROM asset_metadata FINAL where name = lower(slug) LIMIT 1);
CREATE FUNCTION get_metric_id AS (metric) -> (SELECT metric_id FROM metric_metadata FINAL where name = lower(metric) LIMIT 1);
CREATE FUNCTION get_metric_name(metric_id) -> (SELECT name FROM metric_metadata FINAL where metric_id = metric_id LIMIT 1);
CREATE FUNCTION get_asset_name(asset_id) -> (SELECT name FROM asset_metadata FINAL where asset_id = asset_id LIMIT 1);
```