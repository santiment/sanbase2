defmodule SanbaseWeb.Graphql.Resolvers.WidgetResolver do
  def active_widgets(_root, _args, _resolution) do
    {:ok, Sanbase.Widget.ActiveWidget.get_active_widgets()}
  end
end
