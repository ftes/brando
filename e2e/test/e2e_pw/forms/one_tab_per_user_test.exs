defmodule E2eProject.E2e.Forms.OneTabPerUserTest do
  use E2eProject.PlaywrightCase

  alias Playwright.WebSocketRoute

  # One editor with an entry open in two tabs: one tab edits at a time
  # (`BrandoAdmin.LiveView.Form.Tabs`). Every page of a context is a tab of the
  # same editor, with a sessionStorage, and so a tab id, of its own.

  defp project(page, title) do
    slug = title |> String.downcase() |> String.replace(" ", "-")

    client =
      factory(page, "E2eProject.Projects.Client", %{
        name: "#{title} client",
        slug: "#{slug}-client",
        status: "published",
        language: "en"
      })

    %{"id" => id} =
      factory(page, "E2eProject.Projects.Project", %{
        title: title,
        slug: slug,
        client_id: client["id"],
        introduction: "<p>Opened in two tabs.</p>",
        status: "draft",
        language: "en"
      })

    "/admin/projects/projects/update/#{id}"
  end

  defp notice(page), do: Page.get_by_test_id(page, "tab-notice")
  defp title(page), do: Page.get_by_label(page, "Title", exact: true)
  defp main_form(page), do: Page.locator(page, "form.main-form")

  defp open(page, url) do
    Page.goto!(page, url)
    sync_lv(page)
  end

  defp edit_here(page) do
    notice(page) |> Locator.get_by_role(:button, name: "Edit here") |> Locator.click!()
    Expect.to_be_hidden!(notice(page))
    Expect.not_to_have_attribute!(main_form(page), "inert", ~r/.*/)
  end

  # A duplicated tab, or a window a script opens, copies sessionStorage and
  # with it the tab id: it is another tab all the same.
  test "a copy of a tab is another tab", %{page: page} do
    url = project(page, "Copied tab")
    open(page, url)

    copy =
      Page.expect_popup!(page, fn ->
        Page.evaluate!(page, "href => window.open(href, '_blank')", url)
      end)

    sync_lv(copy)
    Expect.to_contain_text!(notice(copy), "You have this entry open in another tab")
    Expect.to_be_hidden!(notice(page))
    Page.close!(copy)
  end

  test "a second tab opens read-only, Edit here moves editing with the unsaved title, and the first takes it back",
       %{page: page} do
    url = project(page, "Two tabs")
    open(page, url)
    Expect.to_be_hidden!(notice(page))

    title(page) |> Locator.fill!("Two tabs, typed in the first")
    title(page) |> Locator.blur!()
    sync_lv(page)

    second = BrowserContext.new_page!(Page.context(page))
    open(second, url)
    Expect.to_contain_text!(notice(second), "You have this entry open in another tab")
    Expect.to_have_attribute!(main_form(second), "inert", ~r/.*/)
    Expect.to_have_value!(title(second), "Two tabs, typed in the first")

    edit_here(second)
    Expect.to_contain_text!(notice(page), "You are editing this entry in another tab")
    Expect.to_have_attribute!(main_form(page), "inert", ~r/.*/)
    Expect.to_have_value!(title(second), "Two tabs, typed in the first")
    # the first tab's recovery copy is the second tab's now: nothing to offer
    Expect.to_be_hidden!(Page.get_by_test_id(second, "draft-notice"))

    # The second tab edits; the first follows
    title(second) |> Locator.fill!("Two tabs, typed in the second")
    title(second) |> Locator.blur!()
    Expect.to_have_value!(title(page), "Two tabs, typed in the second")

    # Take editing back
    notice(page) |> Locator.get_by_role(:button, name: "Take editing back") |> Locator.click!()
    Expect.to_be_hidden!(notice(page))
    Expect.not_to_have_attribute!(main_form(page), "inert", ~r/.*/)
    Expect.to_contain_text!(notice(second), "You are editing this entry in another tab")
    Expect.to_have_value!(title(page), "Two tabs, typed in the second")

    Page.close!(second)
  end

  test "closing the editing tab leaves the other one waiting", %{page: page} do
    url = project(page, "Closed tab")
    first = BrowserContext.new_page!(Page.context(page))
    open(first, url)
    open(page, url)
    Expect.to_contain_text!(notice(page), "You have this entry open in another tab")

    Page.close!(first)
    Expect.to_contain_text!(notice(page), "The other tab was closed")
    # it doesn't take editing by itself
    Expect.to_have_attribute!(main_form(page), "inert", ~r/.*/)

    edit_here(page)
  end

  test "a tab that comes back with offline edits after another took over makes a recovery copy, not a save",
       %{page: page} do
    url = project(page, "Offline tab")
    first = BrowserContext.new_page!(Page.context(page))
    live = route_live_socket(first)
    open(first, url)
    open(page, url)
    Expect.to_be_visible!(notice(page))

    # The first tab loses its connection and is typed into meanwhile
    drop_connection(first, live)
    title(first) |> Locator.fill!("Typed while offline")
    Expect.to_contain_text!(notice(page), "The other tab was closed")

    edit_here(page)

    # Its old process is gone: it comes back as a tab beside the one that edits
    restore_connection(first, live)
    Expect.to_contain_text!(notice(first), "You have this entry open in another tab")
    Expect.to_have_attribute!(main_form(first), "inert", ~r/.*/)

    # The editing tab offers the copy; nothing was applied or saved
    Expect.to_be_visible!(Page.get_by_test_id(page, "draft-notice"), timeout: 15_000)
    Expect.to_have_value!(title(page), "Offline tab")
    Page.get_by_role(page, :button, name: "Review recovery copy") |> Locator.click!()
    Expect.to_contain_text!(Page.get_by_test_id(page, "draft-panel"), "Typed while offline")

    Page.close!(first)
  end

  test "an upload finishing in a tab that edits no more stays in the library", %{page: page} do
    url = project(page, "Upload elsewhere")

    # The first tab's upload frames wait until the second tab has taken over
    {:ok, state} = Agent.start_link(fn -> %{hold: true, held: []} end)

    Page.route_web_socket!(page, ~r"/live/websocket", fn ws ->
      server = WebSocketRoute.connect_to_server(ws)

      WebSocketRoute.on_message(ws, fn message ->
        upload? =
          case message do
            {:binary, bin} -> String.contains?(bin, "lvu:")
            text -> String.contains?(text, ~s("lvu:))
          end

        held? =
          Agent.get_and_update(state, fn s ->
            if s.hold and upload?,
              do: {true, %{s | held: [{server, message} | s.held]}},
              else: {false, s}
          end)

        if !held?, do: WebSocketRoute.send(server, message)
      end)
    end)

    open(page, url)
    field = Page.locator(page, ".media-field[data-asset-type=file]")
    Expect.to_be_visible!(Locator.get_by_role(field, :button, name: "Upload", exact: true))
    field |> Locator.locator("input[type=file]") |> Locator.set_input_files!(fixture_path("test.pdf"))

    second = BrowserContext.new_page!(Page.context(page))
    open(second, url)
    edit_here(second)
    Expect.to_contain_text!(notice(page), "You are editing this entry in another tab")

    # The upload goes through, and finishes in the first tab
    held = Agent.get_and_update(state, fn s -> {Enum.reverse(s.held), %{s | hold: false, held: []}} end)
    assert held != []
    for {server, message} <- held, do: WebSocketRoute.send(server, message)

    Expect.to_contain_text!(
      Page.locator(page, ".toast-stack"),
      "It is in the library, not in the entry",
      timeout: 20_000
    )

    sync_lv(second)

    second
    |> Page.locator(".media-field[data-asset-type=file]")
    |> Locator.get_by_role(:button, name: "Upload", exact: true)
    |> Expect.to_be_visible!()

    Expect.to_be_visible!(Locator.get_by_role(field, :button, name: "Upload", exact: true))

    Page.close!(second)
  end
end
