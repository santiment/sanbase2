defmodule SanbaseWeb.GenericAdmin.Project do
  @schema_module Sanbase.Project

  def schema_module, do: @schema_module

  def link(row) do
    if row.infrastructure do
      SanbaseWeb.GenericAdmin.Subscription.href(
        "infrastructures",
        row.infrastructure.id,
        row.infrastructure.code
      )
    end
  end
end
