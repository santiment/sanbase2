defmodule SanbaseWeb.Graphql.Schema.WidgetQueries do
  @moduledoc false
  use Absinthe.Schema.Notation

  import SanbaseWeb.Graphql.Cache, only: [cache_resolve: 1]

  alias SanbaseWeb.Graphql.Resolvers.WidgetResolver

  object :widget_queries do
    @desc ~s"""
    Show all active widgets. Widgets are not intended to be active at all times.
    An example is doing live streams - shortly before and during the live stream,
    on sanbase there is going to be shown a widget linking to the stream.
    """
    field :active_widgets, list_of(:active_widget) do
      meta(access: :free)

      cache_resolve(&WidgetResolver.active_widgets/3)
    end
  end
end
