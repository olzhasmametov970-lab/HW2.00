"""HTML-шаблоны писем HydroWin (алерты)."""

from __future__ import annotations

import html
from pathlib import Path


LOGO_FILENAME = "hydrowin_logo.png"
LOGO_CID = "hydrowin-logo"


def logo_path() -> Path:
    return Path(__file__).resolve().parent / "static" / LOGO_FILENAME


def build_alert_plain(*, machine_code: str, message: str) -> str:
    return (
        f"HydroWin — авария\n"
        f"Машина: {machine_code}\n"
        f"{message}\n\n"
        f"— ГидроВин / HydroWin\n"
        f"help@hydrowin.ru"
    )


def build_alert_html(*, machine_code: str, message: str) -> str:
    code = html.escape(machine_code)
    msg = html.escape(message).replace("\n", "<br>")
    return f"""\
<!DOCTYPE html>
<html lang="ru">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>HydroWin alert</title>
</head>
<body style="margin:0;padding:0;background:#f2f4f7;font-family:Arial,Helvetica,sans-serif;">
  <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background:#f2f4f7;padding:24px 12px;">
    <tr>
      <td align="center">
        <table role="presentation" width="560" cellspacing="0" cellpadding="0" style="max-width:560px;width:100%;background:#ffffff;border-radius:12px;overflow:hidden;border:1px solid #e5e7eb;">
          <tr>
            <td style="padding:20px 24px;background:#0f172a;text-align:center;">
              <img src="cid:{LOGO_CID}" alt="ГидроВин / HydroWin" width="88" height="88" style="display:inline-block;border:0;outline:none;width:88px;height:88px;">
              <div style="margin-top:10px;color:#e2e8f0;font-size:13px;letter-spacing:0.04em;">ГИДРОВИН · HYDROWIN</div>
            </td>
          </tr>
          <tr>
            <td style="padding:24px;">
              <div style="display:inline-block;padding:4px 10px;border-radius:999px;background:#fee2e2;color:#b91c1c;font-size:12px;font-weight:700;">
                АВАРИЯ
              </div>
              <h1 style="margin:14px 0 8px;font-size:20px;line-height:1.3;color:#0f172a;">
                Машина {code}
              </h1>
              <p style="margin:0;font-size:15px;line-height:1.55;color:#334155;">
                {msg}
              </p>
            </td>
          </tr>
          <tr>
            <td style="padding:16px 24px 22px;border-top:1px solid #e5e7eb;color:#64748b;font-size:12px;line-height:1.5;">
              Автоматическое оповещение HydroWin<br>
              <a href="mailto:help@hydrowin.ru" style="color:#0f766e;text-decoration:none;">help@hydrowin.ru</a>
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>
"""
