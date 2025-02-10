defmodule SanbaseWeb.GenericAdmin.FeaturedItem do
  @moduledoc false
  import Ecto.Query

  def schema_module, do: Sanbase.FeaturedItem

  def resource do
    %{
      actions: [:edit],
      preloads: preloads(),
      index_fields: index_fields(),
      edit_fields: edit_fields(),
      belongs_to_fields: belongs_to(),
      fields_override: %{
        post_id: %{
          value_modifier: &SanbaseWeb.GenericAdmin.Post.post_link/1
        },
        user_list_id: %{
          value_modifier: &SanbaseWeb.GenericAdmin.UserList.user_list_link/1
        }
      }
    }
  end

  defp preloads do
    [
      :post,
      :user_list,
      :user_trigger,
      :chart_configuration,
      :table_configuration,
      :dashboard,
      :query
    ]
  end

  defp index_fields do
    [
      :id,
      :post_id,
      :user_list_id,
      :user_trigger_id,
      :chart_configuration_id,
      :table_configuration_id,
      :dashboard_id,
      :query_id
    ]
  end

  defp edit_fields do
    [
      :post_id,
      :user_list_id,
      :user_trigger_id,
      :chart_configuration_id,
      :table_configuration_id,
      :dashboard_id
    ]
  end

  defp belongs_to do
    %{
      user_list_id: %{
        query: from(ul in Sanbase.UserList, order_by: [desc: ul.id]),
        transform: fn rows -> Enum.map(rows, &{&1.name, &1.id}) end,
        resource: "user_lists",
        search_fields: [:name]
      },
      post_id: %{
        query: from(p in Sanbase.Insight.Post, order_by: [desc: p.id]),
        transform: fn rows -> Enum.map(rows, &{&1.title, &1.id}) end,
        resource: "posts",
        search_fields: [:title]
      },
      user_trigger_id: %{
        query: from(ut in Sanbase.Alert.UserTrigger, order_by: [desc: ut.id]),
        transform: fn rows -> Enum.map(rows, &{&1.id, &1.id}) end,
        resource: "user_triggers",
        search_fields: []
      },
      chart_configuration_id: %{
        query: from(cc in Sanbase.Chart.Configuration, order_by: [desc: cc.id]),
        transform: fn rows -> Enum.map(rows, &{&1.name, &1.id}) end,
        resource: "chart_configurations",
        search_fields: [:name]
      },
      table_configuration_id: %{
        query: from(tc in Sanbase.TableConfiguration, order_by: [desc: tc.id]),
        transform: fn rows -> Enum.map(rows, &{&1.name, &1.id}) end,
        resource: "table_configurations",
        search_fields: [:name]
      },
      dashboard_id: %{
        query: from(d in Sanbase.Dashboards.Dashboard, order_by: [desc: d.id]),
        transform: fn rows -> Enum.map(rows, &{&1.name, &1.id}) end,
        resource: "dashboards",
        search_fields: [:name]
      },
      query_id: %{
        query: from(d in Sanbase.Queries.Query, order_by: [desc: d.id]),
        transform: fn rows -> Enum.map(rows, &{&1.name, &1.id}) end,
        resource: "queries",
        search_fields: [:name]
      }
    }
  end
end
