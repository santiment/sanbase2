defmodule SanbaseWeb.Graphql.Schema.DashboardQueries do
  @moduledoc ~s"""
  Queries and mutations for authentication related intercations
  """
  use Absinthe.Schema.Notation

  alias SanbaseWeb.Graphql.Resolvers.DashboardResolver

  alias SanbaseWeb.Graphql.Middlewares.JWTAuth

  object :dashboard_queries do
    @desc ~s"""
    TODO: Write me before merging
    """
    field :get_dashboard_schema, :dashboard_schema do
      meta(access: :free)
      arg(:dashboard_id, non_null(:integer))

      resolve(&DashboardResolver.get_dashboard_schema/3)
    end

    @desc ~s"""
    TODO: Write me before merging
    """
    field :get_dashboard_cache, :dashboard_cache do
      meta(access: :free)
      arg(:dashboard_id, non_null(:integer))

      resolve(&DashboardResolver.get_dashboard_cache/3)
    end
  end

  object :dashboard_mutations do
    @desc ~s"""
    TODO: Write me before merging
    """
    field :create_dashboard, :dashboard_schema do
      arg(:name, non_null(:string))
      arg(:description, :string)
      arg(:is_public, :boolean)

      middleware(JWTAuth)

      resolve(&DashboardResolver.create_dashboard/3)
    end

    field :remove_dashboard, :dashboard_schema do
      arg(:dashboard_id, non_null(:integer))

      middleware(JWTAuth)

      resolve(&DashboardResolver.delete_dashboard/3)
    end

    @desc ~s"""
    TODO: Write me before merging
    """
    field :add_dashboard_panel, :dashboard_schema do
      arg(:dashboard_id, non_null(:integer))
      arg(:panel, non_null(:panel_input_object))

      middleware(JWTAuth)

      resolve(&DashboardResolver.add_dashboard_panel/3)
    end

    @desc ~s"""
    TODO: Write me before merging
    """
    field :remove_dashboard_panel, :dashboard_schema do
      arg(:dashboard_id, non_null(:integer))
      arg(:panel_id, non_null(:string))

      middleware(JWTAuth)

      resolve(&DashboardResolver.remove_dashboard_panel/3)
    end

    @desc ~s"""
    TODO: Write me before merging
    """
    field :update_dashboard_panel, :dashboard_schema do
      arg(:dashboard_id, non_null(:integer))
      arg(:panel_id, non_null(:string))
      arg(:panel, non_null(:panel_input_object))

      middleware(JWTAuth)

      resolve(&DashboardResolver.update_dashboard_panel/3)
    end

    @desc ~s"""
    TODO: Write me before merging
    """
    field :compute_dashboard_panel, :panel_cache do
      arg(:dashboard_id, non_null(:integer))
      arg(:panel_id, non_null(:string))

      middleware(JWTAuth)

      resolve(&DashboardResolver.compute_dashboard_panel/3)
    end

    @desc ~s"""
    TODO: Write me before merging
    """
    field :compute_and_store_dashboard_panel, :panel_cache do
      arg(:dashboard_id, non_null(:integer))
      arg(:panel_id, non_null(:string))

      middleware(JWTAuth)

      resolve(&DashboardResolver.compute_and_store_dashboard_panel/3)
    end
  end
end
