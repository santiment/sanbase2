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

      captures = Sanbase.TemplateEngine.Captures.extract_captures(template)

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

      captures = Sanbase.TemplateEngine.Captures.extract_captures(template)

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

    test "Run generate clickhouse params -- success" do
      params = %{a: 1, b: 2}
      opts = [params: params]

      template = """
      a is {{a}}, b is {{b}}
      """

      {:ok, {sql, args}} = Sanbase.TemplateEngine.run_generate_clickhouse_params(template, opts)

      assert sql == "a is {a:Int32}, b is {b:Int32}\n"
      assert args == %{"a" => 1, "b" => 2}
    end

    test "Run generate clickhouse params -- missing keys" do
      params = %{a: 1, b: 2}
      opts = [params: params]

      template = """
      a is {{a}}, b is {{b}}, c is {{c}}, d is {{d}}, a is again {{a}}
      """

      {:error, error_msg} = Sanbase.TemplateEngine.run_generate_clickhouse_params(template, opts)

      assert error_msg =~
               "One or more of the {{<key>}} templates in the query text do not correspond to any of the parameters."

      assert error_msg =~ "Template keys missing from the parameters: {{d}}, {{c}}"
      assert error_msg =~ "Parameters' keys defined: a, b"
    end

    test "Run generate clickhouse params -- inline substitution" do
      params = %{table: "my_table", slug: "bitcoin"}
      opts = [params: params]

      template = "SELECT * FROM {{table:inline}} WHERE slug = {{slug}}"

      {:ok, {sql, args}} = Sanbase.TemplateEngine.run_generate_clickhouse_params(template, opts)

      assert sql == "SELECT * FROM my_table WHERE slug = {slug:String}"
      assert args == %{"slug" => "bitcoin"}
    end

    test "Run generate clickhouse params -- type override" do
      params = %{num: 42}
      opts = [params: params]

      template = "SELECT {{num:UInt8}}"

      {:ok, {sql, args}} = Sanbase.TemplateEngine.run_generate_clickhouse_params(template, opts)

      assert sql == "SELECT {num:UInt8}"
      assert args == %{"num" => 42}
    end

    test "Run generate clickhouse params -- deduplication" do
      params = %{name: "Tom"}
      opts = [params: params]

      template = "{{name}} and {{name}} and {{name}}"

      {:ok, {sql, args}} = Sanbase.TemplateEngine.run_generate_clickhouse_params(template, opts)

      assert sql == "{name:String} and {name:String} and {name:String}"
      assert args == %{"name" => "Tom"}
    end

    test "Run generate clickhouse params -- mixed inline and parameterized" do
      params = %{table: "balances", slug: "bitcoin", limit: 10}
      opts = [params: params]

      template = "SELECT * FROM {{table:inline}} WHERE slug = {{slug}} LIMIT {{limit}}"

      {:ok, {sql, args}} = Sanbase.TemplateEngine.run_generate_clickhouse_params(template, opts)

      assert sql == "SELECT * FROM balances WHERE slug = {slug:String} LIMIT {limit:Int32}"
      assert args == %{"slug" => "bitcoin", "limit" => 10}
    end

    test "Run generate clickhouse params -- inline validation rejects bad characters" do
      params = %{table: "DROP TABLE; --"}
      opts = [params: params]

      template = "SELECT * FROM {{table:inline}}"

      assert_raise Sanbase.TemplateEngine.TemplateEngineError, ~r/invalid characters/, fn ->
        Sanbase.TemplateEngine.run_generate_clickhouse_params(template, opts)
      end
    end

    test "Run generate clickhouse params -- different type overrides keep separate placeholders" do
      params = %{num: 42}
      opts = [params: params]

      template = "SELECT {{num:UInt8}}, {{num:UInt64}}"

      {:ok, {sql, args}} = Sanbase.TemplateEngine.run_generate_clickhouse_params(template, opts)

      assert sql == "SELECT {num:UInt8}, {num_1:UInt64}"
      assert args == %{"num" => 42, "num_1" => 42}
    end

    test "Run generate clickhouse params -- inferred and explicit types keep separate placeholders" do
      params = %{num: 42}
      opts = [params: params]

      template = "SELECT {{num}}, {{num:UInt8}}"

      {:ok, {sql, args}} = Sanbase.TemplateEngine.run_generate_clickhouse_params(template, opts)

      assert sql == "SELECT {num:Int32}, {num_1:UInt8}"
      assert args == %{"num" => 42, "num_1" => 42}
    end

    test "Run generate clickhouse params -- same type override deduplicates" do
      params = %{num: 42}
      opts = [params: params]

      template = "SELECT {{num:UInt8}}, {{num:UInt8}}"

      {:ok, {sql, args}} = Sanbase.TemplateEngine.run_generate_clickhouse_params(template, opts)

      assert sql == "SELECT {num:UInt8}, {num:UInt8}"
      assert args == %{"num" => 42}
    end

    test "Run generate clickhouse params -- inferred and explicit matching type deduplicate" do
      params = %{num: 42}
      opts = [params: params]

      template = "SELECT {{num}}, {{num:Int32}}"

      {:ok, {sql, args}} = Sanbase.TemplateEngine.run_generate_clickhouse_params(template, opts)

      assert sql == "SELECT {num:Int32}, {num:Int32}"
      assert args == %{"num" => 42}
    end
  end
end
