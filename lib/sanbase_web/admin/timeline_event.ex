defmodule Sanbase.ExAdmin.TimelineEvent do
  use ExAdmin.Register

  register_resource Sanbase.Timeline.TimelineEvent do
    action_items(only: [:show, :edit, :delete])
  end

  defimpl ExAdmin.Render, for: Tuple do
    def to_string({_type, field}) do
      Atom.to_string(field)
    end
  end
end
