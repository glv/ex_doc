defmodule ExDoc.Autolink do
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

  alias ExDoc.Formatter.HTML.Templates, as: T
  alias ExDoc.Refs

  @hexdocs "https://hexdocs.pm/"
  @otpdocs "http://www.erlang.org/doc/man/"

  def doc(ast, options \\ []) do
    config = struct!(__MODULE__, options)
    walk(ast, config)
  end

  defp walk(list, config) when is_list(list) do
    Enum.map(list, &walk(&1, config))
  end

  defp walk(binary, _) when is_binary(binary) do
    binary
  end

  defp walk({:pre, _, _} = ast, _config) do
    ast
  end

  defp walk({:a, attrs, _} = ast, config) do
    if url = custom_link(attrs, config) do
      {:a, Keyword.put(attrs, :href, url), ast}
    else
      ast
    end
  end

  defp walk({:code, _, [text]} = ast, config) do
    case text_to_ref(text, :regular, config) do
      :no_ref ->
        ast

      ref ->
        if url = url(ref, config) do
          {:a, [href: url], [ast]}
        else
          ast
        end
    end
  end

  defp walk({tag, attrs, ast}, config) do
    {tag, attrs, walk(ast, config)}
  end

  defp custom_link(attrs, config) do
    with {:ok, href} <- Keyword.fetch(attrs, :href),
         [[_, text]] <- Regex.scan(~r/^`(.+)`$/, href) do
      case text_to_ref(text, :custom_link, config) do
        :no_ref ->
          nil

        ref ->
          url(ref, config)
      end
    else
      _ -> nil
    end
  end

  defp text_to_ref("c:" <> text, mode, config) do
    with {call, {:function, module, name, arity}} <- text_to_ref(text, mode, config) do
      {call, {:callback, module, name, arity}}
    end
  end

  defp text_to_ref("t:" <> text, mode, config) do
    with {call, {:function, module, name, arity}} <- text_to_ref(text, mode, config) do
      {call, {:type, module, name, arity}}
    end
  end

  defp text_to_ref("mix help " <> name, _mode, _config), do: mix_task(name)
  defp text_to_ref("mix " <> name, _mode, _config), do: mix_task(name)

  defp text_to_ref(text, mode, config) do
    if not String.contains?(text, [" ", "(", ")"]) do
      case Code.string_to_quoted(text) do
        {:ok, {:__aliases__, _, _} = module} ->
          {:module, module(module)}

        {:ok, {:/, _, [{{:., _, [module, name]}, _, []}, arity]}}
        when is_atom(name) and is_integer(arity) ->
          {:remote, {:function, module(module), name, arity}}

        {:ok, {:/, _, [{name, _, _}, arity]}}
        when is_atom(name) and is_integer(arity) ->
          {:local, {:function, config.current_module, name, arity}}

        {:ok, erlang_module} when is_atom(erlang_module) and mode == :custom_link ->
          {:module, erlang_module}

        _ ->
          :no_ref
      end
    else
      :no_ref
    end
  end

  defp module({:__aliases__, _, _} = module), do: Module.concat([Macro.to_string(module)])
  defp module(module) when is_atom(module), do: module

  defp mix_task(name) do
    if name =~ ~r/^[a-z][a-z0-9]*(\.[a-z][a-z0-9]*)*$/ do
      parts = name |> String.split(".") |> Enum.map(&Macro.camelize/1)
      {:module, Module.concat([Mix, Tasks | parts])}
    else
      :no_ref
    end
  end

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

  @doc """
  Converts given types/specs `ast` into HTML with links.
  """
  def typespec(ast, options) do
    config = struct!(__MODULE__, options)

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

      ref =
        if module do
          {:remote, {:type, module, name, arity}}
        else
          {:local, {:type, config.current_module, name, arity}}
        end

      if url = url(ref, config) do
        ~s[<a href="#{url}">#{T.h(call_string)}</a>]
      else
        call_string
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

  defp url({:module, module}, %{current_module: module}) do
    case tool(module) do
      :ex_doc -> "#content"
      _ -> ""
    end
  end

  defp url({:module, module} = ref, config) do
    if Refs.public?(ref) do
      module_url(tool(module), module, config)
    end
  end

  defp url({:local, {:type, _, name, arity}}, config) when {name, arity} in @basic_types do
    ex_doc_app_url(Kernel, config) <> "typespecs" <> config.ext <> "#basic-types"
  end

  defp url({:local, {:type, _, name, arity}}, config) when {name, arity} in @built_in_types do
    ex_doc_app_url(Kernel, config) <> "typespecs" <> config.ext <> "#built-in-types"
  end

  defp url({:local, {kind, module, name, arity} = ref}, _config) do
    if Refs.public?(ref) do
      fragment(tool(module), kind, name, arity)
    end
  end

  defp url({:remote, {kind, module, name, arity} = ref}, config) do
    if Refs.public?(ref) do
      case tool(module) do
        :no_tool ->
          nil

        tool ->
          if module == config.current_module do
            fragment(tool, kind, name, arity)
          else
            module_url(tool, module, config) <> fragment(tool, kind, name, arity)
          end
      end
    else
      if Refs.public?({:module, module}) do
        maybe_warn({kind, module, name, arity}, config)
      end

      nil
    end
  end

  defp ex_doc_app_url(module, config) do
    app = config.app

    case :application.get_application(module) do
      {:ok, ^app} -> ""
      {:ok, app} -> @hexdocs <> "#{app}/"
      _ -> ""
    end
  end

  defp module_url(:ex_doc, module, config) do
    ex_doc_app_url(module, config) <> inspect(module) <> config.ext
  end

  defp module_url(:otp, module, _config) do
    @otpdocs <> "#{module}.html"
  end

  defp fragment(:ex_doc, kind, name, arity) do
    prefix =
      case kind do
        :function -> ""
        :callback -> "c:"
        :type -> "t:"
      end

    "#" <> prefix <> "#{T.enc(Atom.to_string(name))}/#{arity}"
  end

  defp fragment(:otp, kind, name, arity) do
    case kind do
      :function -> "##{name}-#{arity}"
      :callback -> "#Module:#{name}-#{arity}"
      :type -> "#type-#{name}"
    end
  end

  defp tool(module) do
    name = Atom.to_string(module)

    if name == String.downcase(name) do
      case :code.which(module) do
        :preloaded ->
          :otp

        :non_existing ->
          :no_tool

        path ->
          if String.starts_with?(List.to_string(path), List.to_string(:code.lib_dir())) do
            :otp
          else
            :no_tool
          end
      end
    else
      :ex_doc
    end
  end

  defp maybe_warn({kind, module, name, arity}, config) do
    skipped = config.skip_undefined_reference_warnings_on

    if config.module_id not in skipped and config.id not in skipped do
      warn({kind, module, name, arity}, config.id)
    end
  end

  defp warn({kind, module, name, arity}, id) do
    message =
      "documentation references #{kind} #{inspect(module)}.#{name}/#{arity}" <>
        " but it doesn't exist or isn't public (parsing #{id} docs)"

    IO.warn(message, [])
  end
end
