defmodule SanbaseWeb.GenericAdmin.UserTrigger do
  @behaviour SanbaseWeb.GenericAdmin
  import Ecto.Query

  def schema_module, do: Sanbase.Alert.UserTrigger
  def resource_name, do: "user_triggers"
  def singular_resource_name, do: "user_trigger"

  def resource do
    %{
      actions: [:edit],
      preloads: [:user],
      index_fields: [:id, :user_id, :trigger],
      edit_fields: [:user, :is_public, :is_featured],
      belongs_to_fields: %{
        user: SanbaseWeb.GenericAdmin.belongs_to_user()
      },
      fields_override: %{
        user_id: %{
          value_modifier: &SanbaseWeb.GenericAdmin.User.user_link/1
        },
        trigger: %{
          value_modifier: fn trigger ->
            Map.from_struct(trigger) |> Jason.encode!(pretty: true)
          end
        },
        is_featured: %{
          type: :boolean,
          search_query:
            from(
              ut in Sanbase.Alert.UserTrigger,
              left_join: featured_item in Sanbase.FeaturedItem,
              on: ut.id == featured_item.user_trigger_id,
              where: not is_nil(featured_item.id),
              preload: [:user]
            )
            |> distinct(true)
        }
      }
    }
  end

  def before_filter(trigger) do
    trigger = Sanbase.Repo.preload(trigger, [:featured_item])
    is_featured = if trigger.featured_item, do: true, else: false

    %{
      trigger
      | is_featured: is_featured,
        is_public: Sanbase.Alert.UserTrigger.public?(trigger)
    }
  end

  # TODO propagate errors from before/after filters to users
  def after_filter(trigger, _changeset, params) do
    trigger =
      Sanbase.Alert.UserTrigger.update_changeset(trigger, %{
        trigger: %{is_public: params["is_public"] |> String.to_existing_atom()}
      })
      |> Sanbase.Repo.update!()

    is_featured = params["is_featured"] |> String.to_existing_atom()
    Sanbase.FeaturedItem.update_item(trigger, is_featured)
  end
end
