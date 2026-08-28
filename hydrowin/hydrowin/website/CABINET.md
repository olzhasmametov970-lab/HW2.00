# Кабинет + API на Ubuntu (`app.hydrowin.ru`)

## Схема

| Хост | Где | Что |
|------|-----|-----|
| `https://hydrowin.ru` | BeGet | лендинг |
| `https://app.hydrowin.ru` | **Ubuntu + Caddy** | Flutter Full + API `/v1` |

`api.hydrowin.ru` **не используем**.

## DNS (обязательно)

Сейчас `app` часто смотрит на BeGet → там 404 на `/v1`. Нужно:

| Тип | Имя | Значение |
|-----|-----|----------|
| A | **`app`** | **`5.165.27.141`** (Ubuntu) |

После смены DNS перезапустите Caddy и проверьте отключение sslip:

```bash
cd ~/hydrowin-backend
docker compose up -d --force-recreate caddy
curl -sI https://5-165-27-141.sslip.io/   # ожидается HTTP 410
curl -sI https://app.hydrowin.ru/v1/health # 200 ok
```

Старый `*.sslip.io` в DNS удалить нельзя (чужой сервис) — отключаем на **Caddy** (410 + catch-all 403).

Если на BeGet был сайт `app` — кабинет переезжает на Ubuntu (`backend/web` у Caddy). На BeGet оставляете только `hydrowin.ru`.

## Ubuntu

В `~/hydrowin-backend/.env`:

```env
API_DOMAIN=app.hydrowin.ru
APP_DOMAIN=app.hydrowin.ru
CORS_ORIGINS=https://hydrowin.ru,https://www.hydrowin.ru,https://app.hydrowin.ru
```

Скопировать `Caddyfile`, собрать web, залить статику:

```powershell
.\scripts\build-web.ps1 -ApiUrl "https://app.hydrowin.ru/v1"
# затем scp backend\web → Ubuntu ~/hydrowin-backend/web
```

```bash
cd ~/hydrowin-backend
docker compose up -d caddy api
docker compose logs -f caddy
```

Проверка: **`https://app.hydrowin.ru/v1/health`** → `{"status":"ok"}`  
(не `http://` — только HTTPS)

## Платы

```text
API app.hydrowin.ru|443
```
