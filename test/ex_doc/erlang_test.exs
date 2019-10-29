defmodule ExDoc.ErlangTest do
  use ExUnit.Case, async: true

  test "foo" do
    File.rm_rf!("test/tmp/erlang_docs.beam")

    options = [
      :debug_info,
      outdir: 'test/tmp/beam',
      extra_chunks: [
        {"Docs", :erlang.term_to_binary(chunk())}
      ]
    ]

    {:ok, :erlang_docs} = :compile.file('test/fixtures/erlang_docs', options)

    config = %ExDoc.Config{
      source_root: File.cwd!(),
      source_url_pattern: "http://example.com/%{path}#L%{line}"
    }

    file_nodes =
      ["erlang_docs.beam"]
      |> Enum.map(&Path.join("test/tmp/beam", &1))
      |> ExDoc.Retriever.docs_from_files(config)

    [%ExDoc.ModuleNode{} = module_node] = file_nodes
    assert module_node.doc == "Example Erlang module."
    assert module_node.source_url == "http://example.com/test/fixtures/erlang_docs.erl#L1"

    [function_node] = module_node.docs
    assert function_node.doc == "Returns sum of arguments."
    assert function_node.doc_line == 8
    assert function_node.source_url == "http://example.com/test/fixtures/erlang_docs.erl#L8"
    IO.inspect(function_node.specs, label: function_node.id)

    [type_node] = module_node.typespecs
    assert type_node.doc == "A type."
    assert type_node.doc_line == 5
    assert type_node.name == :t
    assert type_node.source_url == "http://example.com/test/fixtures/erlang_docs.erl#L5"

    IO.inspect(type_node.spec, label: type_node.id)
  end

  defp chunk() do
    entries = [
      {{:function, :foo, 2}, 8, ["foo/2"], %{"en" => "Returns sum of arguments."}, %{}},
      {{:type, :t, 0}, 5, [], %{"en" => "A type."}, %{}}
    ]

    module_doc = "Example Erlang module."
    {:docs_v1, 0, :erlang, "text/markdown", %{"en" => module_doc}, %{}, entries}
  end
end
