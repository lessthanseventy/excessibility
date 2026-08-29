defmodule DemoWeb.Router do
  use DemoWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {DemoWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", DemoWeb do
    pipe_through :browser

    # The on_mount hook (opt-in) records handle_info messages for the
    # message_flooding analyzer — one line covers every route in the session.
    live_session :default, on_mount: [Excessibility.TelemetryCapture] do
      live "/", HomeLive, :index

      # Accessibility examples
      live "/accessible", AccessibleLive, :index
      live "/a11y/form", MessyFormLive, :index
      live "/a11y/widgets", MessyWidgetsLive, :index

      # Performance examples
      live "/perf/n-plus-one", NPlusOneLive, :index
      live "/perf/memory", LeakyLive, :index
      live "/perf/renders", ThrashLive, :index
      live "/perf/messages", FloodLive, :index
    end
  end

  # Other scopes may use custom stacks.
  # scope "/api", DemoWeb do
  #   pipe_through :api
  # end
end
