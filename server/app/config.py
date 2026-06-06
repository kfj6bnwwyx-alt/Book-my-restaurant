import os
from functools import lru_cache


class Settings:
    # Shared key the iOS app sends in X-App-Key. Generate a random one and put it
    # in both the server .env and the app's Constants.swift.
    app_key: str = os.environ.get("APP_KEY", "")

    # Resy. RESY_API_KEY is the long-standing public web client key; verify it
    # against the current resy.com web app if calls start 400ing.
    resy_api_key: str = os.environ.get(
        "RESY_API_KEY", "VbWk7s3L4KiK5fzlO7JD3Q5EYolJI7n5"
    )
    # Auth token grabbed from a logged-in resy.com session, or minted via login().
    resy_auth_token: str = os.environ.get("RESY_AUTH_TOKEN", "")
    # Resy account email/password, used to refresh the auth token when it 401s.
    resy_email: str = os.environ.get("RESY_EMAIL", "")
    resy_password: str = os.environ.get("RESY_PASSWORD", "")
    # Payment method id from /2/user, required to actually book.
    # `or "0"` guards the present-but-empty case (RESY_PAYMENT_METHOD_ID=).
    resy_payment_method_id: int = int(os.environ.get("RESY_PAYMENT_METHOD_ID") or "0")

    db_url: str = os.environ.get("DB_URL", "sqlite:///./resybooker.db")

    def require(self):
        missing = [k for k in ("app_key",) if not getattr(self, k)]
        if missing:
            raise RuntimeError(f"Missing required env: {', '.join(missing)}")


@lru_cache
def get_settings() -> Settings:
    s = Settings()
    s.require()
    return s
