defmodule Excessibility.MCP.Prompts.AccessiblePatternsTest do
  use ExUnit.Case, async: true

  alias Excessibility.MCP.Prompts.AccessibleForm
  alias Excessibility.MCP.Prompts.AccessibleModal
  alias Excessibility.MCP.Prompts.AccessibleNavigation
  alias Excessibility.MCP.Prompts.AccessibleTable

  describe "AccessibleForm" do
    test "returns correct name" do
      assert AccessibleForm.name() == "accessible-form"
    end

    test "has required fields argument" do
      args = AccessibleForm.arguments()
      fields_arg = Enum.find(args, &(&1["name"] == "fields"))

      assert fields_arg["required"] == true
    end

    test "generates form prompt with fields" do
      {:ok, result} = AccessibleForm.get(%{"fields" => "name, email, password"})

      assert %{"messages" => [%{"content" => %{"text" => text}}]} = result

      assert text =~ "name, email, password"
      assert text =~ "label"
      assert text =~ "aria"
      assert text =~ "phx-submit"
    end

    test "includes error handling when has_errors is true" do
      {:ok, result} = AccessibleForm.get(%{"fields" => "email", "has_errors" => "true"})
      text = get_prompt_text(result)

      assert text =~ "aria-describedby"
      assert text =~ "aria-invalid"
      assert text =~ "role=\"alert\""
    end

    test "handles different form types" do
      {:ok, create} = AccessibleForm.get(%{"fields" => "name", "form_type" => "create"})
      {:ok, login} = AccessibleForm.get(%{"fields" => "name", "form_type" => "login"})

      assert get_prompt_text(create) =~ "Create"
      assert get_prompt_text(login) =~ "Sign In"
    end
  end

  describe "AccessibleTable" do
    test "returns correct name" do
      assert AccessibleTable.name() == "accessible-table"
    end

    test "has required columns argument" do
      args = AccessibleTable.arguments()
      columns_arg = Enum.find(args, &(&1["name"] == "columns"))

      assert columns_arg["required"] == true
    end

    test "generates table prompt with columns" do
      {:ok, result} = AccessibleTable.get(%{"columns" => "Name, Email, Role"})
      text = get_prompt_text(result)

      assert text =~ "Name, Email, Role"
      assert text =~ "<table>"
      assert text =~ "<thead>"
      assert text =~ "scope=\"col\""
      assert text =~ "<caption>"
    end

    test "includes sort controls when sortable" do
      {:ok, result} = AccessibleTable.get(%{"columns" => "Name", "sortable" => "true"})
      text = get_prompt_text(result)

      assert text =~ "aria-sort"
      assert text =~ "Sort by"
    end

    test "includes action handling when has_actions" do
      {:ok, result} = AccessibleTable.get(%{"columns" => "Name", "has_actions" => "true"})
      text = get_prompt_text(result)

      assert text =~ "aria-label"
      assert text =~ "action"
    end
  end

  describe "AccessibleModal" do
    test "returns correct name" do
      assert AccessibleModal.name() == "accessible-modal"
    end

    test "generates modal prompt with dialog role" do
      {:ok, result} = AccessibleModal.get(%{})
      text = get_prompt_text(result)

      assert text =~ "role=\"dialog\""
      assert text =~ "aria-modal=\"true\""
      assert text =~ "aria-labelledby"
    end

    test "includes focus trap requirements" do
      {:ok, result} = AccessibleModal.get(%{})
      text = get_prompt_text(result)

      assert text =~ "Focus must move INTO the modal"
      assert text =~ "Focus Trap"
      assert text =~ "Escape"
    end

    test "includes form handling when has_form" do
      {:ok, result} = AccessibleModal.get(%{"has_form" => "true"})
      text = get_prompt_text(result)

      assert text =~ "form"
      assert text =~ "unsaved changes"
      assert text =~ "Submit"
    end

    test "respects dismissable setting" do
      {:ok, dismissable} = AccessibleModal.get(%{"dismissable" => "true"})
      {:ok, not_dismissable} = AccessibleModal.get(%{"dismissable" => "false"})

      assert get_prompt_text(dismissable) =~ "Click on backdrop closes modal"
      assert get_prompt_text(not_dismissable) =~ "does NOT close"
    end
  end

  describe "AccessibleNavigation" do
    test "returns correct name" do
      assert AccessibleNavigation.name() == "accessible-navigation"
    end

    test "has required items argument" do
      args = AccessibleNavigation.arguments()
      items_arg = Enum.find(args, &(&1["name"] == "items"))

      assert items_arg["required"] == true
    end

    test "generates navigation prompt with skip link" do
      {:ok, result} = AccessibleNavigation.get(%{"items" => "Home, About"})
      text = get_prompt_text(result)

      assert text =~ "Skip to main content"
      assert text =~ "sr-only"
    end

    test "includes landmark roles" do
      {:ok, result} = AccessibleNavigation.get(%{"items" => "Home"})
      text = get_prompt_text(result)

      assert text =~ "<nav>"
      assert text =~ "aria-label"
      assert text =~ "aria-current=\"page\""
    end

    test "includes mobile menu when has_mobile" do
      {:ok, result} = AccessibleNavigation.get(%{"items" => "Home", "has_mobile" => "true"})
      text = get_prompt_text(result)

      assert text =~ "aria-expanded"
      assert text =~ "hamburger"
      assert text =~ "toggle"
    end

    test "includes dropdown support when has_dropdown" do
      {:ok, result} = AccessibleNavigation.get(%{"items" => "Home", "has_dropdown" => "true"})
      text = get_prompt_text(result)

      assert text =~ "aria-haspopup"
      assert text =~ "role=\"menu\""
      assert text =~ "Arrow keys"
    end

    test "handles different positions" do
      {:ok, header} = AccessibleNavigation.get(%{"items" => "Home", "position" => "header"})
      {:ok, footer} = AccessibleNavigation.get(%{"items" => "Home", "position" => "footer"})

      assert get_prompt_text(header) =~ "Main navigation"
      assert get_prompt_text(footer) =~ "Footer navigation"
    end
  end

  # Helper to extract prompt text from result
  defp get_prompt_text(%{"messages" => [%{"content" => %{"text" => text}}]}), do: text
end
