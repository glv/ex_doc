defmodule OTPTest do
  use ExUnit.Case, async: true

  test "otp" do
    ExDoc.generate_docs("stdlib", "3.11.2",
      source_beam: "/Users/wojtek/src/otp/lib/stdlib/ebin",
      output: "otp_docs/stdlib"
    )
  end
end
