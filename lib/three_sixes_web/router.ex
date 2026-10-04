defmodule ThreeSixesWeb.Router do
  use ThreeSixesWeb, :router

  # LiveView patches style attributes into the page, so inline styles stay allowed. The hash
  # admits the root layout's theme script, which must run before first paint.
  @content_security_policy %{
    "content-security-policy" => "default-src 'self'; \
    script-src 'self' 'sha256-hvBZbzh0mBfsdico/2s0tgvLOiL47b8vtjbN1J+RNnQ='; \
    style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; \
    font-src 'self' https://fonts.gstatic.com; img-src 'self' data:; \
    frame-ancestors 'self'; base-uri 'self'; form-action 'self'"
  }

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {ThreeSixesWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers, @content_security_policy
  end

  # The deploy proxy probes this over plain HTTP with no session or CSRF token.
  scope "/", ThreeSixesWeb do
    get "/health", HealthController, :show
  end

  scope "/", ThreeSixesWeb do
    pipe_through :browser

    live "/", LandingLive
  end

  # Enable LiveDashboard in development
  if Application.compile_env(:three_sixes, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    # LiveDashboard's layout runs an inline script its bundle depends on.
    @dev_tools_content_security_policy %{
      "content-security-policy" => "default-src 'self'; \
      script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; \
      frame-ancestors 'self'; base-uri 'self'; form-action 'self'"
    }

    pipeline :dev_tools do
      plug :put_secure_browser_headers, @dev_tools_content_security_policy
    end

    scope "/dev", ThreeSixesWeb do
      pipe_through :browser

      live "/kit", KitLive
    end

    scope "/dev" do
      pipe_through [:browser, :dev_tools]

      live_dashboard "/dashboard", metrics: ThreeSixesWeb.Telemetry
    end
  end
end
