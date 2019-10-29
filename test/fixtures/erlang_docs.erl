-module(erlang_docs).
-export([foo/2]).
-export_type([t/0]).

-type t() :: number().

-spec foo(t(), t()) -> t().
foo(X, Y) ->
    X + Y.
