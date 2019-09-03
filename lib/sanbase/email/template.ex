defmodule Sanbase.Email.Template do
  @sanbase_login_templates %{login: "sanbase-sign-in", register: "sanbase-sign-up"}
  @neuro_login_templates %{login: "neuro-sign-in", register: "neuro-sign-up"}
  @sheets_login_templates %{login: "sheets-sign-in", register: "sheets-sign-up"}
  @verification_email_template "verify email"

  def verification_email_template(), do: @verification_email_template

  def choose_login_template(origin_url, first_login?: true) when is_binary(origin_url) do
    template_by_product(origin_url, :register)
  end

  def choose_login_template(origin_url, first_login?: false) when is_binary(origin_url) do
    template_by_product(origin_url, :login)
  end

  def choose_login_template(_, first_login?: true), do: @sanbase_login_templates[:register]
  def choose_login_template(_, first_login?: false), do: @sanbase_login_templates[:login]

  defp template_by_product(origin_url, template) do
    cond do
      String.contains?(origin_url, "neuro") -> @neuro_login_templates[template]
      String.contains?(origin_url, "sheets") -> @sheets_login_templates[template]
      true -> @sanbase_login_templates[template]
    end
  end
end
