```sql
DROP FUNCTION get_asset_id;
DROP FUNCTION get_asset_ref_id;
DROP FUNCTION get_asset_name;
DROP FUNCTION get_metric_id;
DROP FUNCTION get_metric_id;

CREATE FUNCTION get_asset_id AS (__slug_internal_arg__) -> (dictGetUInt64('default.assets_by_name', 'asset_id', lower(__slug_internal_arg__)));
CREATE FUNCTION get_asset_ref_id AS (__slug_internal_arg__) ->  (dictGetUInt64('default.assets_by_name', 'asset_ref_id', lower(__slug_internal_arg__)));
CREATE FUNCTION get_metric_id AS (__metric_internal_arg__) ->  (dictGetUInt64('default.metrics_by_name', 'metric_id', lower(__metric_internal_arg__)));
CREATE FUNCTION get_asset_name AS (__asset_id_internal_arg__) -> (dictGetString('default.asset_metadata_dict', 'name', __asset_id_internal_arg__));
CREATE FUNCTION get_metric_name AS (__metric_id_internal_arg__) -> (dictGetString('default.metric_metadata_dict', 'name', __metric_id_internal_arg__));
```
