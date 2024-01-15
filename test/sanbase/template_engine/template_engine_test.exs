defmodule Sanbase.TemplateEngineTest do
  use ExUnit.Case, async: true

  doctest Sanbase.TemplateEngine, import: true

  describe "captures" do
    test "get captures, default lang=san:1.0" do
      template = """
      Tempalte {{key1}}
      some code {% 1 + 2 %}
      another key {{key2}} and more code {% pow(10,18) %}

      This is not a template { getMetric("price_usd") }

      {{}} is an empty template.
      """

      captures = Sanbase.TemplateEngine.Captures.get(template)

      assert captures ==
               {:ok,
                [
                  %Sanbase.TemplateEngine.Captures.CaptureMap{
                    code?: false,
                    id: 0,
                    inner_content: "key1",
                    key: "{{key1}}",
                    lang: nil,
                    lang_version: nil
                  },
                  %Sanbase.TemplateEngine.Captures.CaptureMap{
                    code?: true,
                    id: 1,
                    inner_content: "1 + 2",
                    key: "{% 1 + 2 %}",
                    lang: "san",
                    lang_version: "1.0"
                  },
                  %Sanbase.TemplateEngine.Captures.CaptureMap{
                    code?: false,
                    id: 2,
                    inner_content: "key2",
                    key: "{{key2}}",
                    lang: nil,
                    lang_version: nil
                  },
                  %Sanbase.TemplateEngine.Captures.CaptureMap{
                    code?: true,
                    id: 3,
                    inner_content: "pow(10,18)",
                    key: "{% pow(10,18) %}",
                    lang: "san",
                    lang_version: "1.0"
                  },
                  %Sanbase.TemplateEngine.Captures.CaptureMap{
                    code?: false,
                    id: 4,
                    inner_content: "",
                    key: "{{}}",
                    lang: nil,
                    lang_version: nil
                  }
                ]}
    end

    test "get captures, specify lang=san:3.14" do
      template = """
      {% lang=san:3.14 %}

      Code: {% 1 + 2 %}
      Simple key: {{key}}
      """

      captures = Sanbase.TemplateEngine.Captures.get(template)

      assert captures ==
               {:ok,
                [
                  %Sanbase.TemplateEngine.Captures.CaptureMap{
                    code?: true,
                    key: "{% lang=san:3.14 %}",
                    id: 0,
                    lang: "san",
                    lang_version: "3.14",
                    # TODO: The inner content here has been "cleaned" so it's replaced with just the empty string
                    inner_content: ""
                  },
                  %Sanbase.TemplateEngine.Captures.CaptureMap{
                    code?: true,
                    key: "{% 1 + 2 %}",
                    id: 1,
                    lang: "san",
                    lang_version: "3.14",
                    inner_content: "1 + 2"
                  },
                  %Sanbase.TemplateEngine.Captures.CaptureMap{
                    code?: false,
                    key: "{{key}}",
                    id: 2,
                    lang: nil,
                    lang_version: nil,
                    inner_content: "key"
                  }
                ]}
    end
  end

  describe "run" do
    test "Replace simple keys" do
      template = """
      Ground control to Major {{name}},
      Ground control to Major {{name}}!
      """

      assert Sanbase.TemplateEngine.run!(template, params: %{name: "Tom"}) ==
               """
               Ground control to Major Tom,
               Ground control to Major Tom!
               """
    end

    test "Run code without access to env" do
      template = """
      2 to the 10 is {% pow(2, 10) %}
      2 + 5 * 10 = {% 2 + 5 * 10 %}
      """

      assert Sanbase.TemplateEngine.run!(template) == """
             2 to the 10 is 1024
             2 + 5 * 10 = 52
             """
    end

    test "Run code accessing the env" do
      env = Sanbase.SanLang.Environment.new()

      env =
        Sanbase.SanLang.Environment.put_env_bindings(env, %{"a" => 1, "b" => "some string value"})

      template = """
      1 + @a = {% 1 + @a %}
      The value of @b is {% @b %}
      """

      assert Sanbase.TemplateEngine.run!(template, env: env) == """
             1 + @a = 2
             The value of @b is some string value
             """
    end
  end
end
