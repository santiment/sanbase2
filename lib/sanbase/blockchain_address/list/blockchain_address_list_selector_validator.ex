defmodule Sanbase.BlockchainAddress.ListSelector.Validator do
  @moduledoc false
  alias Sanbase.Project.ListSelector.Transform
  alias Sanbase.Utils.ListSelector.Validator

  def valid_selector?(args) do
    args = Sanbase.MapUtils.atomize_keys(args)
    filters = Transform.args_to_filters(args)
    pagination = Transform.args_to_pagination(args) || %{}

    with true <- Validator.valid_args?(args),
         true <- Validator.valid_filters_combinator?(args),
         true <- Validator.valid_base_projects?(args),
         true <- Validator.valid_filters?(filters, :blockchain_address) do
      Validator.valid_pagination?(pagination)
    end
  end
end
