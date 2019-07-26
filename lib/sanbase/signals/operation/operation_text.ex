defmodule Sanbase.Signal.OperationText do
  def to_text(value, operation, opts \\ [])

  def to_text(value, %{above: above}, opts) do
    form = Keyword.get(opts, :form, :singular)
    "#{form_to_text(form)} above #{above} and #{form_to_text(form)} now #{value}"
  end

  def to_text(value, %{below: below}, opts) do
    form = Keyword.get(opts, :form, :singular)

    "#{form_to_text(form)} below #{below} and #{form_to_text(form)} now #{value}"
  end

  def to_text(value, %{inside_channel: [lower, upper]}, opts) do
    form = Keyword.get(opts, :form, :singular)

    "#{form_to_text(form)} inside the [#{lower}, #{upper}] interval and #{form_to_text(form)} now #{
      value
    }"
  end

  def to_text(value, %{outside_channel: [lower, upper]}, opts) do
    form = Keyword.get(opts, :form, :singular)

    "#{form_to_text(form)} outside the [#{lower}, #{upper}] interval and #{form_to_text(form)} now #{
      value
    }"
  end

  def to_text(percent_change, %{percent_up: _percent}, _opts) do
    "increased by #{percent_change}%"
  end

  def to_text(percent_change, %{percent_down: _percent}, _opts) do
    "decreased by #{percent_change}%"
  end

  def to_text(amount_changed, %{amount_up: _amount}, _opts) do
    "increased by #{amount_changed}"
  end

  def to_text(amount_changed, %{amount_down: _amount}, _opts) do
    "decreased by #{amount_changed}"
  end

  defp form_to_text(:singular), do: "is"
  defp form_to_text(:plural), do: "are"
end
