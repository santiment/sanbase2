defmodule Sanbase.Project.ListSelector.Validator do
  alias Sanbase.Utils.ListSelector.Validator
  alias Sanbase.Project.ListSelector.Transform

  def valid_selector?(args) do
    args = Sanbase.MapUtils.atomize_keys(args)
    filters = Transform.args_to_filters(args)

    order_by = Transform.args_to_order_by(args) || %{}
    pagination = Transform.args_to_pagination(args) || %{}

    with true <- Validator.valid_args?(args),
         true <- Validator.valid_filters_combinator?(args),
         true <- Validator.valid_base_projects?(args),
         true <- Validator.valid_filters?(filters, :project),
         true <- Validator.valid_order_by?(order_by),
         true <- Validator.valid_pagination?(pagination) do
      true
    end
  end
end
