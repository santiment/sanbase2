defmodule Sanbase.ExAdmin.TimelineEvent do
  use ExAdmin.Register

  register_resource Sanbase.Timeline.TimelineEvent do
    action_items(only: [:show, :delete])

    index do
      selectable_column()

      column(:id, link: true)
      column(:event_type)
      column(:user, link: true)
      column(:post, link: true)
      column(:user_list, link: true)
      column(:user_trigger, link: true)
      column(:inserted_at)
      column(:payload)
      column(:data)
      # display the default actions column
      actions()
    end

    show event do
      attributes_table(all: true)
    end
  end

  defimpl ExAdmin.Render, for: Tuple do
    def to_string({_type, field}) do
      Atom.to_string(field)
    end
  end
end
