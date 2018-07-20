defmodule Sanbase.Discourse.Config do
  require Sanbase.Utils.Config
  alias Sanbase.Utils.Config

  @config_module Sanbase.Discourse

  def category(), do: Config.module_get(@config_module, :insights_category)

  def discourse_url(), do: Config.module_get(@config_module, :url)

  def api_key(), do: Config.module_get(@config_module, :api_key)
end
