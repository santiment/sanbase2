defmodule SanbaseWeb.Graphql.Schema.SignalQueries do
  @moduledoc ~s"""
  Queries and mutations for working with Signals
  """
  use Absinthe.Schema.Notation

  import SanbaseWeb.Graphql.Cache, only: [cache_resolve: 1]

  alias SanbaseWeb.Graphql.Resolvers.{
    UserTriggerResolver,
    SignalsHistoricalActivityResolver
  }

  alias SanbaseWeb.Graphql.Middlewares.JWTAuth

  object :signal_queries do
    @desc "Get signal trigger by its id"
    field :get_trigger_by_id, :user_trigger do
      arg(:id, non_null(:integer))

      middleware(JWTAuth)
      resolve(&UserTriggerResolver.get_trigger_by_id/3)
    end

    @desc "Get public signal triggers by user_id"
    field :public_triggers_for_user, list_of(:user_trigger) do
      arg(:user_id, non_null(:id))

      resolve(&UserTriggerResolver.public_triggers_for_user/3)
    end

    @desc "Get all public signal triggers"
    field :all_public_triggers, list_of(:user_trigger) do
      resolve(&UserTriggerResolver.all_public_triggers/3)
    end

    @desc "Get historical trigger points"
    field :historical_trigger_points, list_of(:json) do
      arg(:cooldown, :string)
      arg(:settings, non_null(:json))

      cache_resolve(&UserTriggerResolver.historical_trigger_points/3)
    end

    @desc ~s"""
    Get current user's history of executed signals with cursor pagination.
    * `cursor` argument is an object with: type `BEFORE` or `AFTER` and `datetime`.
      - `type: BEFORE` gives those executed before certain datetime
      - `type: AFTER` gives those executed after certain datetime
    * `limit` argument defines the size of the page. Default value is 25
    """
    field :signals_historical_activity, :signal_historical_activity_paginated do
      arg(:cursor, :cursor_input)
      arg(:limit, :integer, default_value: 25)

      middleware(JWTAuth)

      resolve(&SignalsHistoricalActivityResolver.fetch_historical_activity_for/3)
    end
  end

  object :signal_mutations do
    @desc """
    Create signal trigger described by `trigger` json field.
    Returns the newly created trigger.
    """
    field :create_trigger, :user_trigger do
      arg(:title, non_null(:string))
      arg(:description, :string)
      arg(:icon_url, :string)
      arg(:is_public, :boolean)
      arg(:is_active, :boolean)
      arg(:is_repeating, :boolean)
      arg(:cooldown, :string)
      arg(:tags, list_of(:string))
      arg(:settings, non_null(:json))

      middleware(JWTAuth)
      resolve(&UserTriggerResolver.create_trigger/3)
    end

    @desc """
    Update signal trigger by its id.
    Returns the updated trigger.
    """
    field :update_trigger, :user_trigger do
      arg(:id, non_null(:integer))
      arg(:title, :string)
      arg(:description, :string)
      arg(:settings, :json)
      arg(:icon_url, :string)
      arg(:cooldown, :string)
      arg(:is_active, :boolean)
      arg(:is_public, :boolean)
      arg(:is_repeating, :boolean)
      arg(:tags, list_of(:string))

      middleware(JWTAuth)
      resolve(&UserTriggerResolver.update_trigger/3)
    end

    @desc """
    Remove signal trigger by its id.
    Returns the removed trigger on success.
    """
    field :remove_trigger, :user_trigger do
      arg(:id, non_null(:integer))

      middleware(JWTAuth)

      resolve(&UserTriggerResolver.remove_trigger/3)
    end
  end
end
