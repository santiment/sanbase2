defmodule SanbaseWeb.UserFormsComponents do
  use Phoenix.Component

  attr(:ecosystems, :list, required: true)
  attr(:ecosystem_colors_class, :string, default: "badge-info")

  def ecosystems_group(assigns) do
    ~H"""
    <div class="flex flex-wrap gap-1">
      <.ecosystem_span
        :for={ecosystem <- @ecosystems}
        ecosystem={ecosystem}
        class={@ecosystem_colors_class}
      />
    </div>
    """
  end

  attr(:ecosystem, :map, required: true)
  attr(:class, :string, required: false, default: nil)

  def ecosystem_span(assigns) do
    ~H"""
    <span class={["badge badge-soft", @class]}>
      {@ecosystem}
    </span>
    """
  end

  attr(:github_organizations, :list, required: true)
  attr(:github_organization_colors_class, :string, default: "badge-info")

  def github_organizations_group(assigns) do
    ~H"""
    <div class="flex flex-wrap gap-1">
      <.github_organization_span
        :for={github_organization <- @github_organizations}
        github_organization={github_organization}
        class={@github_organization_colors_class}
      />
    </div>
    """
  end

  attr(:github_organization, :map, required: true)
  attr(:class, :string, required: false, default: nil)

  def github_organization_span(assigns) do
    ~H"""
    <span class={["badge badge-soft", @class]}>
      {@github_organization}
    </span>
    """
  end
end
