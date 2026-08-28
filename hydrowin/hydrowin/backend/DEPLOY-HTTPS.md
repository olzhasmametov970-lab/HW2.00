# HTTPS: кабинет + API на app.hydrowin.ru (Ubuntu Caddy)

```text
https://app.hydrowin.ru/          — Flutter Full
https://app.hydrowin.ru/v1        — FastAPI
```

Лендинг `hydrowin.ru` остаётся на BeGet.

### DNS

| Тип | Имя | Значение |
|-----|-----|----------|
| A | `app` | `5.165.27.141` |

### `.env`

```env
API_DOMAIN=app.hydrowin.ru
APP_DOMAIN=app.hydrowin.ru
CORS_ORIGINS=https://hydrowin.ru,https://www.hydrowin.ru,https://app.hydrowin.ru
```

### Запуск

```bash
cd ~/hydrowin-backend
docker compose up -d caddy api
```

Проверка: `https://app.hydrowin.ru/v1/health`
