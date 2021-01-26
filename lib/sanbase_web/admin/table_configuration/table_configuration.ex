defmodule SanbaseWeb.ExAdmin.TableConfiguration do
  use ExAdmin.Register

  alias Sanbase.TableConfiguration

  register_resource Sanbase.TableConfiguration do
    scope(:all, default: true)

    scope(:featured, [], fn query ->
      from(
        table_config in query,
        left_join: featured_item in Sanbase.FeaturedItem,
        on: table_config.id == featured_item.table_configuration_id,
        where: not is_nil(featured_item.id)
      )
      |> distinct(true)
    end)

    scope(:not_featured, [], fn query ->
      from(
        table_config in query,
        left_join: featured_item in Sanbase.FeaturedItem,
        on: table_config.id == featured_item.table_configuration_id,
        where: is_nil(featured_item.id)
      )
      |> distinct(true)
    end)

    index do
      # Don't show description on overview page as it takes too much space
      column(:id)
      column(:title)
      column(:description)
      column(:page_size)
      column(:is_public)
      column(:is_featured, &is_featured(&1))
      column(:columns)
      column(:user, link: true)
    end

    show configuration do
      attributes_table do
        row(:id)
        row(:title)
        row(:description)
        row(:page_size)
        row(:is_public)
        row(:is_featured, &is_featured(&1))
        row(:columns)
        row(:user, link: true)
      end
    end

    form configuration do
      inputs do
        input(configuration, :title)
        input(configuration, :description)
        input(configuration, :is_public)
        input(configuration, :page_size)
        input(configuration, :user_id)

        input(
          configuration,
          :is_featured,
          collection: ~w[true false],
          selected: true
        )
      end
    end

    controller do
      after_filter(:set_featured, only: [:update])
    end
  end

  defp is_featured(%TableConfiguration{} = table_config) do
    table_config = Sanbase.Repo.preload(table_config, [:featured_item])
    (table_config.featured_item != nil) |> Atom.to_string()
  end

  def set_featured(conn, params, resource, :update) do
    is_featured = params.table_configuration.is_featured |> String.to_existing_atom()
    Sanbase.FeaturedItem.update_item(resource, is_featured)
    {conn, params, resource}
  end
end
