defmodule Sanbase.Repo.Migrations.RenameUserSettingsSignals do
  @moduledoc false
  use Ecto.Migration

  @mapping_up %{
    "alert_notify_email" => "alert_notify_email",
    "alert_notify_telegram" => "alert_notify_telegram",
    "signals_per_day_limit" => "alerts_per_day_limit",
    "signals_fired" => "alerts_fired"
  }

  @mapping_down Map.new(@mapping_up, fn {k, v} -> {v, k} end)

  def up do
    execute("""
    CREATE OR REPLACE FUNCTION jsonb_rename_keys(
      jdata JSONB,
      keys TEXT[]
    )
    RETURNS JSONB AS $$
    DECLARE
      result JSONB;
      len INT;
      newkey TEXT;
      oldkey TEXT;
    BEGIN
      len = array_length(keys, 1);

      IF len < 1 OR (len % 2) != 0 THEN
        RAISE EXCEPTION 'The length of keys must be even, such as {old1,new1,old2,new2,...}';
      END IF;

      result = jdata;

      FOR i IN 1..len BY 2 LOOP
        oldkey = keys[i];
        IF (jdata ? oldkey) THEN
          newkey = keys[i+1];
          result = (result - oldkey) || jsonb_build_object(newkey, result->oldkey);
        END IF;
      END LOOP;

      RETURN result;
    END;
    $$ LANGUAGE plpgsql;

    """)

    execute("""
    UPDATE user_settings
    SET settings = jsonb_rename_keys(settings, #{mapping_to_array(@mapping_up)})
    """)
  end

  def down do
    execute("""
    UPDATE user_settings
    SET settings = jsonb_rename_keys(settings, #{mapping_to_array(@mapping_down)})
    """)
  end

  defp mapping_to_array(map) do
    values =
      map |> Enum.flat_map(fn {k, v} -> [k, v] end) |> Enum.map_join(", ", &"'#{&1}'")

    "ARRAY[" <> values <> "]"
  end
end
