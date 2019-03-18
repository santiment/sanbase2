defmodule Sanbase.ExAdmin.Signals.UserTrigger do
  use ExAdmin.Register

  import Ecto.Query, warn: false
  alias Sanbase.Signals.UserTrigger

  register_resource Sanbase.Signals.UserTrigger do
    update_changeset(:update_changeset)
    action_items(only: [:show, :edit])

    index do
      column(:id)
      column(:title, & &1.trigger.title)
      column(:is_featured, &is_featured(&1))
      column(:trigger, &Jason.encode!(&1.trigger |> Map.from_struct()))
      column(:user)
    end

    show _user_trigger do
      attributes_table do
        row(:id)
        row(:title, & &1.trigger.title)
        row(:user, link: true)
        row(:trigger, &Jason.encode!(&1.trigger |> Map.from_struct()))
        row(:is_featured, &is_featured(&1))
      end
    end

    form user_trigger do
      inputs do
        input(
          user_trigger,
          :is_featured,
          collection: ~w[true false]
        )
      end
    end

    controller do
      after_filter(:set_featured, only: [:update])
    end
  end

  defp is_featured(%UserTrigger{} = ut) do
    ut = Sanbase.Repo.preload(ut, [:featured_item])
    (ut.featured_item != nil) |> Atom.to_string()
  end

  def set_featured(conn, params, resource, :update) do
    is_featured = params.user_trigger.is_featured |> String.to_existing_atom()
    Sanbase.FeaturedItem.update_item(resource, is_featured)
    {conn, params, resource}
  end
end
