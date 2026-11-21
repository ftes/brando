defmodule E2eProject.E2e.Projects.ClientsTest do
  use E2eProject.PlaywrightCase

  defp create_client(page, name) do
    Page.get_by_role(page, :link, name: "Create new") |> Locator.click!()
    sync_lv(page)
    set_entry_status(page, "published")
    name_box = Page.get_by_role(page, :textbox, name: "Name")
    Locator.click!(name_box)
    Locator.fill!(name_box, name)
    Page.get_by_test_id(page, "submit") |> Locator.click!()
    sync_lv(page)
  end

  test "creates and edits clients", %{page: page} do
    Page.goto!(page, "/admin")
    page |> Page.locator("#nav-sections") |> Locator.get_by_role(:link, name: "Clients") |> Locator.click!()
    create_client(page, "Google")
    create_client(page, "Microsoft")
    create_client(page, "OpenAI")

    Page.get_by_role(page, :link, name: "Google", exact: true) |> Locator.click!()
    sync_lv(page)
    name_box = Page.get_by_role(page, :textbox, name: "Name")
    Locator.click!(name_box)
    Locator.press!(name_box, "ControlOrMeta+Shift+ArrowLeft")
    Locator.fill!(name_box, "Alphabet")
    Page.get_by_test_id(page, "submit") |> Locator.click!()
    sync_lv(page)

    rows = Page.locator(page, ".content-list .list-row")
    Expect.to_contain_text!(Locator.nth(rows, 0), "Alphabet")
    Expect.to_contain_text!(Locator.nth(rows, 1), "Microsoft")
    Expect.to_contain_text!(Locator.nth(rows, 2), "OpenAI")
    rows |> Locator.nth(2) |> Locator.locator(".status") |> Locator.click!()
    rows |> Locator.nth(2) |> Locator.locator(".status-dropdown button") |> Locator.nth(3) |> Locator.click!()

    Expect.to_have_class!(
      rows |> Locator.nth(2) |> Locator.locator(".status > div > svg > circle"),
      "pending"
    )
  end
end
