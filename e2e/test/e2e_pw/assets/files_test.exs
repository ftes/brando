defmodule E2eProject.E2e.Assets.FilesTest do
  use E2eProject.PlaywrightCase

  defp upload_file(page) do
    filename = "annual-report-#{:crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)}.pdf"
    original = File.read!(fixture_path("test.pdf"))
    Page.goto!(page, "/admin/assets/files")
    sync_lv(page)
    initial_count = Page.locator(page, ".list-row") |> Locator.count!()

    page
    |> Page.locator(~s|#assets-file-browser-main input[type="file"]|)
    |> Locator.set_input_files!(%{name: filename, mimeType: "application/pdf", buffer: original})

    row = Page.locator(page, ".list-row") |> Locator.filter(has_text: filename)
    Expect.to_be_visible!(row)
    id = Locator.get_attribute!(row, "data-id")
    url = row |> Locator.locator(".library-file-action a") |> Locator.get_attribute!("href")
    row |> Locator.get_by_test_id("circle-dropdown-button") |> Locator.click!()
    Page.get_by_role(page, :button, name: "Replace file", exact: true) |> Locator.click!()
    dialog = Page.get_by_role(page, :dialog, name: "Replace file", exact: true)
    Expect.to_be_visible!(dialog)
    Expect.to_contain_text!(Locator.locator(dialog, ".replacement-current .name"), filename)
    Expect.to_have_text!(Locator.locator(dialog, ".replacement-current .updated"), url)
    %{row: row, id: id, url: url, dialog: dialog, original: original, expected_count: initial_count + 1}
  end

  defp body(page, url), do: Playwright.APIResponse.body!(Playwright.APIRequestContext.get!(Page.request(page), url))

  test "replaces a resource file while keeping its ID and download URL", %{page: page} do
    Page.set_viewport_size!(page, %{width: 1440, height: 1000})
    %{row: row, id: id, url: url, dialog: dialog, original: original, expected_count: expected_count} = upload_file(page)
    Expect.to_have_count!(Page.locator(page, ".progress-popup"), 0)
    Page.screenshot!(page, path: Playwright.Test.output_path("replace-file-dialog.png"))
    replacement = original <> "\n% Revised annual report\n"

    dialog
    |> Locator.get_by_label("Replacement file")
    |> Locator.set_input_files!(%{name: "revised-annual-report.pdf", mimeType: "application/pdf", buffer: replacement})

    Expect.not_to_be_visible!(dialog)
    Expect.to_have_attribute!(row, "data-id", id)
    Expect.to_have_attribute!(Locator.locator(row, ".library-file-action a"), "href", url)
    download = Playwright.APIRequestContext.get!(Page.request(page), url)
    assert Playwright.APIResponse.status(download) == 200
    assert Playwright.APIResponse.body!(download) == replacement
    Expect.to_have_count!(Page.locator(page, ".list-row"), expected_count)

    Expect.to_be_visible!(
      Page.get_by_text(page, "#{expected_count} #{if expected_count == 1, do: "file", else: "files"}", exact: true)
    )

    Expect.to_contain_text!(row, "#{byte_size(replacement)} B")
    Expect.to_have_count!(Page.locator(page, ".progress-popup"), 0)
    Page.screenshot!(page, path: Playwright.Test.output_path("replaced-file-listing.png"))
    Page.reload!(page)
    Expect.to_have_attribute!(row, "data-id", id)
    assert body(page, url) == replacement
  end

  test "closing or rejecting a replacement keeps the original file", %{page: page} do
    %{row: row, url: url, dialog: dialog, original: original} = upload_file(page)
    dialog |> Locator.get_by_role(:button, name: "Close", exact: true) |> Locator.click!()
    Expect.not_to_be_visible!(dialog)
    assert body(page, url) == original

    row |> Locator.get_by_test_id("circle-dropdown-button") |> Locator.click!()
    Page.get_by_role(page, :button, name: "Replace file", exact: true) |> Locator.click!()

    dialog
    |> Locator.get_by_label("Replacement file")
    |> Locator.set_input_files!(%{
      name: "wrong-extension.txt",
      mimeType: "text/plain",
      buffer: "This must not replace the PDF"
    })

    Expect.to_contain_text!(
      Page.locator(page, "#brando-upload-manager"),
      "Choose a file with the same extension"
    )

    assert body(page, url) == original
    Expect.to_be_visible!(dialog)
  end
end
