from pathlib import Path

from pydantic import Field, SecretStr
from pydantic_settings import BaseSettings, SettingsConfigDict
from sqlalchemy import URL


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    app_access_token: SecretStr
    deepseek_api_key: SecretStr = SecretStr("")
    deepseek_base_url: str = "https://api.deepseek.com"
    deepseek_vision_model: str = "deepseek-flash"
    deepseek_text_model: str = "deepseek-flash"
    mysql_host: str = "mysql"
    mysql_port: int = 3306
    mysql_database: str = "qingji"
    mysql_user: str = "qingji"
    mysql_password: SecretStr = SecretStr("")
    mysql_ssl_ca: str | None = None
    photo_directory: Path = Path("data/photos")
    request_timeout_seconds: float = Field(default=120, ge=0.01, le=180)
    rate_limit_per_hour: int = Field(default=60, ge=1, le=1000)
    max_concurrent_requests: int = Field(default=3, ge=1, le=20)
    # This private service owns ONE account. Rotating the token does not change its data.
    owner_id: str = Field(default="owner", pattern=r"^[a-zA-Z0-9_-]{1,40}$")

    def connection_url(self) -> URL:
        return URL.create("mysql+pymysql", username=self.mysql_user,
                          password=self.mysql_password.get_secret_value(),
                          host=self.mysql_host, port=self.mysql_port,
                          database=self.mysql_database, query={"charset": "utf8mb4"})

    def check_secrets(self) -> None:
        token = self.app_access_token.get_secret_value()
        if len(token) < 32 or token.startswith("replace-"):
            raise ValueError("APP_ACCESS_TOKEN must be a random value of at least 32 characters")
        if not self.deepseek_base_url.startswith("https://"):
            raise ValueError("DEEPSEEK_BASE_URL must use HTTPS")
