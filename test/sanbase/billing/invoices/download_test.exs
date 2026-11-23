defmodule Sanbase.Billing.Invoices.DownloadTest do
  use ExUnit.Case, async: true

  alias Sanbase.Billing.Invoices.Download

  describe "extract_filename/1" do
    test "reads the filename from a capitalized Content-Disposition header (HTTP/1.1)" do
      response = %HTTPoison.Response{
        headers: [{"Content-Disposition", ~s(attachment; filename="Invoice-1234.pdf")}]
      }

      assert Download.extract_filename(response) == "Invoice-1234.pdf"
    end

    test "reads the filename from a lowercase content-disposition header (HTTP/2)" do
      response = %HTTPoison.Response{
        headers: [{"content-disposition", ~s(attachment; filename="Invoice-1234.pdf")}]
      }

      assert Download.extract_filename(response) == "Invoice-1234.pdf"
    end
  end
end
