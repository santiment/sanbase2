defmodule SanbaseWeb.Graphql.Middlewares.ApiUsage do
  @moduledoc """
  Track the API usage by logging some info to the standard output.
  These logs are analyzed with Elasticsearch
  """
  @behaviour Absinthe.Middleware
  # @behaviour Absinthe.Plugin

  alias Absinthe.Resolution

  require Logger

  def call(
        %Resolution{
          definition: definition,
          context: %{auth: %{auth_method: :apikey, api_token: token}}
        } = resolution,
        config
      ) do
    metadata = Logger.metadata()

    # Token can be safely logged to track apikey usage
    # Logging it is safe as this token cannot be used to generate the apikey
    # without having the secret key which is not logged/revealed anywhere.
    Logger.metadata(api_token: token, query: definition.name, complexity: definition.complexity)

    Logger.info(
      "Apikey usage: api token: #{token}, query: #{definition.name}, complexity: #{
        definition.complexity
      }"
    )

    Logger.reset_metadata(metadata)

    resolution
  end

  def call(
        %Resolution{
          definition: definition,
          context: %{auth: %{auth_method: :user_token, current_user: user}}
        } = resolution,
        config
      ) do
    metadata = Logger.metadata()
    Logger.metadata(user_id: user.id, query: definition.name, complexity: definition.complexity)

    Logger.info(
      "Apikey usage: user id: #{user.id}, query: #{definition.name}, complexity: #{
        definition.complexity
      }"
    )

    Logger.reset_metadata(metadata)

    resolution
  end

  def call(%{definition: definition, context: %{remote_ip: remote_ip}} = resolution, _) do
    metadata = Logger.metadata()
    remote_ip = to_string(:inet_parse.ntoa(remote_ip))

    Logger.metadata(
      remote_ip: remote_ip,
      query: definition.name,
      complexity: definition.complexity
    )

    Logger.info(
      "Apikey usage: remote ip: #{remote_ip}, query: #{definition.name}, complexity: #{
        definition.complexity
      }"
    )

    Logger.reset_metadata(metadata)
    resolution
  end
end
