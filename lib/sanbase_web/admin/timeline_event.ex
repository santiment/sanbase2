defmodule Sanbase.ExAdmin.TimelineEvent do
  use ExAdmin.Register

  register_resource Sanbase.Timeline.TimelineEvent do
    action_items(only: [:show, :edit, :delete])
  end
end
