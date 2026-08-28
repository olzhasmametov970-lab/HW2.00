# ГидроВин

Мониторинг гидравлического оборудования (BLE + облако).

## Структура репозитория

| Путь | Описание |
|------|----------|
| `docs/TZ-3.1-HydroWin.md` | Техническое задание 3.1 |
| `docs/ROADMAP-STEPS.md` | Этапы разработки (чеклист) |
| `docs/backlog/mvp-a.csv` | User stories MVP-A |
| `docs/backlog/mvp-b.csv` | User stories MVP-B |
| `docs/protocol/BLE-packet-v1.md` | Спека BLE-пакета |
| `api/openapi.yaml` | REST API (MVP-B) |
| `backend/` | **REST API сервер** (FastAPI + PostgreSQL, Docker) |
| `deploy/nginx/` | Конфиг nginx для VPS |
| `scripts/` | Сборка Android / Windows / Web |
| `website/` | **Лендинг** продукта (HTML/CSS) |
| `mobile/hydrowin/` | Flutter-приложение (Android, Windows, Web) |

## Полное развёртывание на сервере

| Уровень | Инструкция |
|---------|------------|
| **Начинающим — начните здесь** | **[`docs/DEPLOY-PROSTO.md`](docs/DEPLOY-PROSTO.md)** |
| **Домен на REG.RU** | **[`docs/DEPLOY-REGRU.md`](docs/DEPLOY-REGRU.md)** |
| **Сервер Windows 11 (не VPS)** | **[`docs/DEPLOY-WINDOWS-SERVER.md`](docs/DEPLOY-WINDOWS-SERVER.md)** |
| **Хостинг NetAngels** | **[`docs/DEPLOY-NETANGELS.md`](docs/DEPLOY-NETANGELS.md)** |
| **NetAngels — только виртуальный хостинг** | **[`docs/DEPLOY-NETANGELS-HOSTING.md`](docs/DEPLOY-NETANGELS-HOSTING.md)** ← **ваш случай** |
| **Без сайта: блок → сервер → приложение** | **[`docs/DEPLOY-DATA-ONLY.md`](docs/DEPLOY-DATA-ONLY.md)** |
| **Сборка .apk / .exe / web (release/)** | **[`docs/BUILD-RELEASE.md`](docs/BUILD-RELEASE.md)** |
| Подробно для опытных | [`docs/DEPLOY-SYSTEM.md`](docs/DEPLOY-SYSTEM.md) |

## Запуск приложения

```bash
cd mobile/hydrowin
flutter pub get
flutter run
```

**Облачный режим (MVP-B):** «Полный режим» → демо или логин → парк → машина → датчик → **график за сутки** (с полуночи, `GET /machines/.../readings`).

## Сайт (лендинг)

```powershell
cd website
python -m http.server 8080
```

Браузер: http://localhost:8080 — подробнее в `website/README.md`.

**Размещение в интернете:** пошагово в [`website/DEPLOY.md`](website/DEPLOY.md) (GitHub Pages, Netlify, Vercel, хостинг, VPS).

## Тесты

```bash
cd mobile/hydrowin
flutter test
```

## Текущий прогресс

См. `docs/ROADMAP-STEPS.md`.
