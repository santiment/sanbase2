```sql
CREATE FUNCTION get_asset_id AS (__slug_internal_arg__) -> (SELECT asset_id FROM asset_metadata FINAL where name = lower(__slug_internal_arg__) LIMIT 1);
CREATE FUNCTION get_metric_id AS (__metric_internal_arg__) -> (SELECT metric_id FROM metric_metadata FINAL where name = lower(__metric_internal_arg__) LIMIT 1);
CREATE FUNCTION get_asset_name AS (__asset_id_internal_arg__) -> (dictGetString('asset_metadata_dict', 'name', __asset_id_internal_arg__));
CREATE FUNCTION get_metric_name AS (__metric_id_internal_arg__) -> (dictGetString('metric_metadata_dict', 'name', __metric_id_internal_arg__));
```
