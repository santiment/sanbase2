defmodule SanbaseWeb.GenericAdmin.Webinar do
  def schema_module, do: Sanbase.Webinar

  def resource() do
    %{
      actions: [:new, :edit, :delete],
      index_fields: [
        :id,
        :title,
        :description,
        :url,
        :is_pro,
        :start_time,
        :end_time,
        :inserted_at,
        :updated_at
      ],
      new_fields: [
        :id,
        :title,
        :description,
        :url,
        :is_pro,
        :start_time,
        :end_time,
        :image_url
      ],
      edit_fields: [
        :id,
        :title,
        :description,
        :url,
        :is_pro,
        :start_time,
        :end_time,
        :image_url
      ],
      preloads: [],
      belongs_to_fields: %{}
    }
  end
end
