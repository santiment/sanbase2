defmodule Sanbase.ExAdmin.Chart.Configuration do
  use ExAdmin.Register

  alias Sanbase.Chart.Configuration

  register_resource Sanbase.Chart.Configuration do
    action_items(only: [:show, :edit, :delete])

    scope(:all, default: true)

    scope(:featured, [], fn query ->
      from(
        chart in query,
        left_join: featured_item in Sanbase.FeaturedItem,
        on: chart.id == featured_item.chart_configuration_id,
        where: not is_nil(featured_item.id)
      )
      |> distinct(true)
    end)

    scope(:not_featured, [], fn query ->
      from(
        chart in query,
        left_join: featured_item in Sanbase.FeaturedItem,
        on: chart.id == featured_item.chart_configuration_id,
        where: is_nil(featured_item.id)
      )
      |> distinct(true)
    end)

    index do
      # Don't show description on overview page as it takes too much space
      column(:id)
      column(:title)
      column(:is_public)
      column(:is_featured, &is_featured(&1))
      column(:metrics)
      column(:anomalies)
      column(:user, link: true)
      column(:project, link: true)
    end

    show configuration do
      attributes_table do
        row(:id)
        row(:title)
        row(:description)
        row(:is_public)
        row(:is_featured, &is_featured(&1))
        row(:metrics)
        row(:anomalies)
        row(:user, link: true)
        row(:project, link: true)
      end
    end

    form configuration do
      inputs do
        input(configuration, :title)
        input(configuration, :description)
        input(configuration, :is_public)

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

  defp is_featured(%Configuration{} = config) do
    config = Sanbase.Repo.preload(config, [:featured_item])
    (config.featured_item != nil) |> Atom.to_string()
  end

  def set_featured(conn, params, resource, :update) do
    is_featured = params.configuration.is_featured |> String.to_existing_atom()
    Sanbase.FeaturedItem.update_item(resource, is_featured)
    {conn, params, resource}
  end
end
