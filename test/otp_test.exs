defmodule OTPTest do
  use ExUnit.Case, async: true

  test "otp" do
    ExDoc.generate_docs("stdlib", "23.0-dev",
      source_beam: "/Users/wojtek/src/otp/lib/stdlib/ebin",
      output: "doc/stdlib"
    )
  end
end
