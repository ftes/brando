defmodule E2eProject.E2e.Assets.ImagesTest do
  use E2eProject.PlaywrightCase

  test "browses folders, uploads and searches images without exposing folder filters", %{page: page} do
    Page.set_viewport_size!(page, %{width: 1440, height: 1000})
    request = Page.request(page)
    fixture = nil

    {:ok, agent} = Agent.start_link(fn -> fixture end)

    try do
      Page.goto!(page, "/admin/assets/images")
      sync_lv(page)
      Page.get_by_role(page, :button, name: "New folder", exact: true) |> Locator.click!()
      Page.get_by_placeholder(page, "Folder name", exact: true) |> Locator.fill!("design-review")
      Page.get_by_role(page, :button, name: "Create folder", exact: true) |> Locator.click!()
      path = Page.get_by_role(page, :navigation, name: "Folder path")
      Expect.to_contain_text!(path, "design-review")
      Expect.to_have_url!(page, ~r/filter(%3A|:)folder_id=/)
      Expect.to_have_count!(Page.locator(page, ".active-filters"), 0)
      Expect.to_be_visible!(Page.get_by_role(page, :heading, name: "No images in this view"))
      sync_lv(page)
      Expect.to_be_hidden!(Page.locator(page, "body > canvas"))

      Page.screenshot!(page,
        path: Playwright.Test.output_path("images-empty-desktop.png"),
        full_page: true
      )

      Page.get_by_label(page, "Upload images", exact: true) |> Locator.set_input_files!(fixture_path("image.jpg"))
      rows = Page.locator(page, ".content-list .list-row")
      Expect.to_have_count!(rows, 1)
      Expect.to_be_visible!(rows |> Locator.first() |> Locator.locator(".library-thumbnail img"), timeout: 30_000)
      Expect.to_contain_text!(Locator.first(rows), "No alt text")

      Expect.to_contain_text!(
        rows |> Locator.first() |> Locator.get_by_role(:group, name: "Formats"),
        "JPG"
      )

      Expect.to_contain_text!(
        rows |> Locator.first() |> Locator.locator(".library-size-count"),
        ~r/\d+ sizes?/
      )

      Expect.to_be_visible!(Page.get_by_text(page, "1 image", exact: true))
      filename = rows |> Locator.first() |> Locator.get_by_role(:link) |> Locator.inner_text!()

      search = Page.get_by_role(page, :textbox, name: "Filter by Path", exact: true)
      Locator.fill!(search, "does-not-exist")
      Expect.to_have_count!(rows, 0)
      Expect.not_to_contain_text!(Page.locator(page, ".active-filters"), "folder_id")
      Locator.fill!(search, "")
      Expect.to_have_count!(rows, 1)
      Page.get_by_role(page, :button, name: "Root", exact: true) |> Locator.click!()
      Expect.not_to_contain_text!(path, "design-review")
      Expect.to_have_count!(Locator.filter(rows, has_text: filename), 0)
      # The library opens where uploads land (`site/default`), so that is where
      # the folder was created; "Root" is the real root above it.
      folders = Page.get_by_role(page, :complementary)

      for folder <- ["site", "default", "design-review"] do
        folders |> Locator.get_by_role(:button, name: folder, exact: true) |> Locator.click!()
        sync_lv(page)
      end

      Expect.to_have_count!(rows, 1)
      Expect.to_contain_text!(Locator.first(rows), filename)
      image_id = rows |> Locator.first() |> Locator.get_attribute!("id") |> String.replace("list-row-", "")
      fixture_response = Playwright.APIRequestContext.post!(request, "/e2e/image-creator/#{image_id}")
      assert Playwright.APIResponse.ok(fixture_response)
      Agent.update(agent, fn _ -> Playwright.APIResponse.json!(fixture_response) end)
      Page.reload!(page)
      sync_lv(page)
      Expect.to_contain_text!(Locator.first(rows), filename)
      avatar = rows |> Locator.first() |> Locator.locator(".item-meta .avatar img")
      Expect.to_be_visible!(avatar)
      Expect.poll!(fn -> Locator.evaluate!(avatar, "img => img.naturalWidth") end, &assert(&1 > 0))
      Expect.to_contain_text!(Locator.first(rows), "Image contributor")
      Expect.to_be_hidden!(Page.locator(page, "body > canvas"))
      Page.screenshot!(page, path: Playwright.Test.output_path("images-desktop.png"), full_page: true)
      Page.set_viewport_size!(page, %{width: 390, height: 844})
      # The page settles in the frames after a resize, so poll the measurement
      Expect.poll!(
        fn -> Page.evaluate!(page, "document.documentElement.scrollWidth <= innerWidth") end,
        &assert(&1 == true)
      )

      Expect.to_be_visible!(avatar)
      Expect.poll!(fn -> Locator.bounding_box!(avatar).width end, &assert(&1 == 30))
      Page.screenshot!(page, path: Playwright.Test.output_path("images-mobile.png"), full_page: true)
    after
      if fixture = Agent.get(agent, & &1) do
        Playwright.APIRequestContext.post!(request, "/e2e/user-directory/cleanup", data: fixture)
      end
    end
  end
end
