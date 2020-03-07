defmodule ExDoc.Autolink do
  @moduledoc false

  defmodule Config do
    @moduledoc false
    # * `:app` - the app that the docs are being generated for. When linking modules they are
    #   checked if they are part of the app and based on that the links are relative or absolute.
    #
    # * `:current_module` - the module that the docs are being generated for. Used to link local
    #   calls and see if remote calls are in the same app.
    #
    # * `:module_id` - id of the module being documented (e.g.: `"String"`)
    #
    # * `:id` - id of the thing being documented (e.g.: `"String.upcase/2"`, `"library-guidelines"`, etc)
    #
    # * `:ext` - the extension (`".html"`, "`.xhtml"`, etc)
    #
    # * `:skip_undefined_reference_warnings_on` - list of modules to skip the warning on
    defstruct [
      :app,
      :current_module,
      :module_id,
      :id,
      ext: ".html",
      skip_undefined_reference_warnings_on: []
    ]
  end

  alias ExDoc.Formatter.HTML.Templates, as: T
  alias ExDoc.Refs

  @hexdocs "https://hexdocs.pm/"
  @otp_docs "http://www.erlang.org/doc/man/"

  def doc(ast, options \\ []) do
    config = struct!(Config, options)

    ast
    |> preprocess()
    |> postprocess(config)
  end

  defp preprocess(list) when is_list(list) do
    Enum.map(list, &preprocess/1)
  end

  defp preprocess(binary) when is_binary(binary) do
    binary
  end

  defp preprocess({:pre, _, _} = node) do
    node
  end

  defp preprocess({:code, _, [text]} = node) do
    case parse(text, :regular) do
      {:ok, link} -> {:a, [href: link], [node]}
      :error -> node
    end
  end

  defp preprocess({:a, attrs, ast} = node) do
    case custom_link(attrs) do
      {:ok, link} -> {:a, Keyword.put(attrs, :href, link), ast}
      :error -> node
    end
  end

  defp preprocess({tag, attrs, ast}) do
    {tag, attrs, preprocess(ast)}
  end

  defp custom_link(attrs) do
    with {:ok, href} <- Keyword.fetch(attrs, :href),
         [[_, text]] <- Regex.scan(~r/^`(.+)`$/, href) do
      parse(text, :custom_link)
    else
      _ -> :error
    end
  end

  defp parse("mix " <> name, _) do
    if name =~ ~r/^[a-z][a-z0-9]*(\.[a-z][a-z0-9]*)+$/ do
      mix_task(name)
    else
      :error
    end
  end

  defp parse("t:" <> text, mode) do
    case parse(text, mode) do
      {:ok, {:local, :function, name, arity}} ->
        {:ok, {:local, :type, name, arity}}

      {:ok, {:remote, :function, module, name, arity}} ->
        {:ok, {:remote, :type, module, name, arity}}

      other ->
        other
    end
  end

  defp parse("c:" <> text, mode) do
    case parse(text, mode) do
      {:ok, {:local, :function, name, arity}} ->
        {:ok, {:local, :callback, name, arity}}

      {:ok, {:remote, :function, module, name, arity}} ->
        {:ok, {:remote, :callback, module, name, arity}}

      other ->
        other
    end
  end

  defp parse(text, mode) do
    if String.contains?(text, [" ", "(", ")"]) do
      :error
    else
      case Code.string_to_quoted(text) do
        {:ok, {:__aliases__, _, _} = module} ->
          {:ok, {:module, module(module)}}

        {:ok, {:/, _, [{{:., _, [module, name]}, _, []}, arity]}}
        when is_atom(name) and is_integer(arity) ->
          {:ok, {:remote, :function, module(module), name, arity}}

        {:ok, {:/, _, [{name, _, nil}, arity]}} when is_atom(name) and is_integer(arity) ->
          {:ok, {:local, :function, name, arity}}

        # <<>>/1, {}/1 etc
        {:ok, {:/, _, [{name, _, []}, arity]}} when is_atom(name) and is_integer(arity) ->
          {:ok, {:local, :function, name, arity}}

        # "erlang" module is always ignored
        {:ok, module} when is_atom(module) ->
          if mode == :custom_link do
            {:ok, {:module, module}}
          else
            :error
          end

        _other ->
          :error
      end
    end
  end

  defp mix_task(name) do
    parts = name |> String.split(".") |> Enum.map(&Macro.camelize/1)
    {:ok, {:module, Module.concat([Mix, Tasks | parts])}}
  end

  defp module(module) when is_atom(module), do: module
  defp module({:__aliases__, _, _} = module), do: Module.concat([Macro.to_string(module)])

  defp postprocess(list, config) when is_list(list) do
    Enum.map(list, &postprocess(&1, config))
  end

  defp postprocess(binary, _config) when is_binary(binary) do
    binary
  end

  defp postprocess({:a, attrs, ast} = node, config) do
    case link(attrs[:href], config) do
      :no_ref ->
        unwrap(ast)

      :keep ->
        node

      link ->
        url = url(link, config)
        {:a, [href: url], ast}
    end
  end

  defp postprocess({tag, attrs, ast}, config) do
    {tag, attrs, postprocess(ast, config)}
  end

  defp unwrap([item]), do: item
  defp unwrap(items) when is_list(items), do: items

  @basic_types [
    any: 0,
    none: 0,
    atom: 0,
    map: 0,
    pid: 0,
    port: 0,
    reference: 0,
    struct: 0,
    tuple: 0,
    integer: 0,
    float: 0,
    neg_integer: 0,
    non_neg_integer: 0,
    pos_integer: 0,
    list: 1,
    nonempty_list: 1,
    improper_list: 2,
    maybe_improper_list: 2
  ]

  @built_in_types [
    term: 0,
    arity: 0,
    as_boolean: 1,
    binary: 0,
    bitstring: 0,
    boolean: 0,
    byte: 0,
    char: 0,
    charlist: 0,
    nonempty_charlist: 0,
    fun: 0,
    function: 0,
    identifier: 0,
    iodata: 0,
    iolist: 0,
    keyword: 0,
    keyword: 1,
    list: 0,
    nonempty_list: 0,
    maybe_improper_list: 0,
    nonempty_maybe_improper_list: 0,
    mfa: 0,
    module: 0,
    no_return: 0,
    node: 0,
    number: 0,
    struct: 0,
    timeout: 0
  ]

  defp link({:module, module} = link, _config) do
    if Refs.public?(link) do
      case module_kind(module) do
        :elixir -> link
        :otp -> {:module_otp, module}
        :erlang -> :no_ref
      end
    else
      :no_ref
    end
  end

  defp link({:local, :type, name, arity}, _config)
       when {name, arity} in @basic_types do
    {:basic_type, name, arity}
  end

  defp link({:local, :type, name, arity}, _config)
       when {name, arity} in @built_in_types do
    {:built_in_type, name, arity}
  end

  defp link({:local, kind, name, arity} = link, config) do
    if Refs.public?({kind, config.current_module, name, arity}) do
      link
    else
      try_auto_imported({kind, name, arity})
    end
  end

  defp link({:remote, kind, module, name, arity} = link, config) do
    if Refs.public?({kind, module, name, arity}) do
      case module_kind(module) do
        :elixir -> link
        :otp -> {:remote_otp, kind, module, name, arity}
        :erlang -> :no_ref
      end
    else
      if Refs.public?({:module, module}) do
        maybe_warn({kind, module, name, arity}, config)
      end

      :no_ref
    end
  end

  defp link({:mix_task, module}, config) do
    link({:module, module}, config)
  end

  defp link(text, _config) when is_binary(text) do
    :keep
  end

  defp module_kind(module) do
    name = Atom.to_string(module)

    if name == String.downcase(name) do
      case :code.which(module) do
        :preloaded ->
          :otp

        path ->
          if String.starts_with?(List.to_string(path), List.to_string(:code.lib_dir())) do
            :otp
          else
            :erlang
          end
      end
    else
      :elixir
    end
  end

  @doc """
  Converts given types/specs `ast` into HTML with links.
  """
  def typespec(ast, options) do
    config = struct!(Config, options)

    string =
      ast
      |> Macro.to_string()
      |> Code.format_string!(line_length: 80)
      |> IO.iodata_to_binary()

    name = typespec_name(ast)
    {name, rest} = split_name(string, name)
    name <> do_typespec(rest, config)
  end

  defp typespec_name({:"::", _, [{name, _, _}, _]}), do: Atom.to_string(name)
  defp typespec_name({:when, _, [left, _]}), do: typespec_name(left)
  defp typespec_name({name, _, _}) when is_atom(name), do: Atom.to_string(name)

  # extract out function name so we don't process it. This is to avoid linking it when there's
  # a type with the same name
  defp split_name(string, name) do
    if String.starts_with?(string, name) do
      {name, binary_part(string, byte_size(name), byte_size(string) - byte_size(name))}
    else
      {"", string}
    end
  end

  defp do_typespec(string, config) do
    regex =
      ~r/((?:((?:\:[a-z][_a-zA-Z0-9]*)|(?:[A-Z][_a-zA-Z0-9]*(?:\.[A-Z][_a-zA-Z0-9]*)*))\.)?(\w+))(\(.*\))/

    Regex.replace(regex, string, fn _all, call_string, module_string, name_string, rest ->
      module = string_to_module(module_string)
      name = String.to_atom(name_string)
      arity = count_args(rest, 0, 0)

      link =
        if module do
          {:remote, :type, module, name, arity}
        else
          {:local, :type, name, arity}
        end

      case link(link, config) do
        :no_ref ->
          call_string

        link ->
          url = url(link, config)
          ~s[<a href="#{url}">#{T.h(call_string)}</a>]
      end <> do_typespec(rest, config)
    end)
  end

  defp string_to_module(""), do: nil

  defp string_to_module(string) do
    if String.starts_with?(string, ":") do
      string |> String.trim_leading(":") |> String.to_atom()
    else
      Module.concat([string])
    end
  end

  defp count_args("()" <> _, 0, 0), do: 0
  defp count_args("(" <> rest, counter, acc), do: count_args(rest, counter + 1, acc)
  defp count_args("[" <> rest, counter, acc), do: count_args(rest, counter + 1, acc)
  defp count_args("{" <> rest, counter, acc), do: count_args(rest, counter + 1, acc)
  defp count_args(")" <> _, 1, acc), do: acc + 1
  defp count_args(")" <> rest, counter, acc), do: count_args(rest, counter - 1, acc)
  defp count_args("]" <> rest, counter, acc), do: count_args(rest, counter - 1, acc)
  defp count_args("}" <> rest, counter, acc), do: count_args(rest, counter - 1, acc)
  defp count_args("," <> rest, 1, acc), do: count_args(rest, 1, acc + 1)
  defp count_args(<<_>> <> rest, counter, acc), do: count_args(rest, counter, acc)
  defp count_args("", _counter, acc), do: acc

  ## Internals

  defp maybe_warn({kind, module, name, arity}, config) do
    skipped = config.skip_undefined_reference_warnings_on

    if config.module_id not in skipped and config.id not in skipped do
      warn({kind, module, name, arity}, config.id)
    end
  end

  defp warn({kind, module, name, arity}, id) do
    ref = ref_prefix(kind) <> inspect(module) <> ".#{name}/#{arity}"

    message =
      "documentation references #{ref} but it doesn't exist or isn't public" <>
        " (parsing #{id} docs)"

    IO.warn(message, [])
  end

  defp url({:module, module}, %{current_module: module}) do
    "#content"
  end

  defp url({:module, module}, config) do
    app_prefix(config.app, module) <> "#{inspect(module)}#{config.ext}"
  end

  defp url({:module_otp, module}, _config) do
    @otp_docs <> "#{module}.html"
  end

  defp url({:local, kind, name, arity}, _config) do
    "#" <> ref_prefix(kind) <> T.enc(to_string(name)) <> "/#{arity}"
  end

  defp url({:remote, kind, module, name, arity}, config) do
    app_prefix(config.app, module) <>
      inspect(module) <> config.ext <> url({:local, kind, name, arity}, config)
  end

  defp url({:remote_otp, kind, module, name, arity}, _config) do
    fragment =
      case kind do
        :type -> "type-#{name}"
        :function -> "#{name}-#{arity}"
        :callback -> "Module:#{name}-#{arity}"
      end

    @otp_docs <> "#{module}.html#" <> fragment
  end

  defp url({:basic_type, _name, _arity}, config) do
    app_prefix(config.app, Kernel) <> "typespecs" <> config.ext <> "#basic-types"
  end

  defp url({:built_in_type, _name, _arity}, config) do
    app_prefix(config.app, Kernel) <> "typespecs" <> config.ext <> "#built-in-types"
  end

  defp app_prefix(app, module) do
    case :application.get_application(module) do
      {:ok, ^app} -> ""
      {:ok, app} -> @hexdocs <> "#{app}/"
      :undefined -> ""
    end
  end

  defp try_auto_imported({kind, name, arity}) do
    if Refs.public?({kind, Kernel, name, arity}) do
      {:remote, kind, Kernel, name, arity}
    else
      if Refs.public?({kind, Kernel.SpecialForms, name, arity}) do
        {:remote, kind, Kernel.SpecialForms, name, arity}
      else
        :no_ref
      end
    end
  end

  defp ref_prefix(:function), do: ""
  defp ref_prefix(:macro), do: ""
  defp ref_prefix(:callback), do: "c:"
  defp ref_prefix(:macrocallback), do: "c:"
  defp ref_prefix(:type), do: "t:"
end
