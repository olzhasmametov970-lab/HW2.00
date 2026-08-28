# Как разместить сайт ГидроВин в интернете

> **Домен уже куплен?** Пошаговый запуск с привязкой домена: **[LAUNCH.md](LAUNCH.md)**

Лендинг с админкой: контент в `data/content.json`, страница собирается через `js/render.js`.

---

## 0. Что именно публикуется

На хостинг загружается **только содержимое папки `website/`**:

```
website/
├── index.html
├── data/content.json     ← тексты (редактируются в /admin/)
├── css/style.css
├── js/render.js
├── js/main.js
├── admin/                ← админ-панель
├── assets/favicon.svg
└── server/               ← только для VPS (не заливать node_modules)
```

**Не загружайте** всю папку репозитория — иначе сайт откроется как `site.ru/website/index.html`.

**Не загружайте** `website/server/node_modules/` — тяжёлая папка, на статике не нужна.

Документация проекта (`docs/`, `api/`) на лендинге **не линкуется** наружу — только текст в блоке «Разработчикам».

---

## 1. Подготовка перед публикацией

### 1.1 Проверка локально

```powershell
cd "ПУТЬ\К\ПРОЕКТУ\website"
python -m http.server 8080
```

Откройте http://localhost:8080 — проверьте все секции, меню на телефоне (уменьшите окно браузера).

### 1.2 Замените контакты

Через админку (`/admin/`) или в файле `data/content.json` — поле `contact.email`.

### 1.3 Домен

См. **[LAUNCH.md](LAUNCH.md)** — пошаговая привязка к Netlify, REG.RU, Timeweb.

---

## 2. GitHub Pages (бесплатно, удобно с Git)

Подходит, если проект уже в GitHub или вы готовы его туда залить.

### Шаг 1 — Репозиторий на GitHub

1. Зарегистрируйтесь на https://github.com  
2. **New repository** → имя, например `hydrowin` → Create  
3. На компьютере (из **корня** репозитория, не только website):

```powershell
cd "ПУТЬ\К\ПРОЕКТУ"
git init
git add .
git commit -m "Initial: HydroWin app, docs, website"
git branch -M main
git remote add origin https://github.com/ВАШ_ЛОГИН/hydrowin.git
git push -u origin main
```

### Шаг 2 — Включить Pages только для `website/`

1. GitHub → репозиторий → **Settings** → **Pages**  
2. **Build and deployment** → Source: **Deploy from a branch**  
3. Branch: `main`, folder: **`/website`** (если есть в списке)  

Если папки `/website` нет в выпадающем списке:

**Альтернатива — отдельная ветка `gh-pages` только с сайтом:**

```powershell
cd website
git init
git add .
git commit -m "Website"
git branch -M gh-pages
git remote add origin https://github.com/ВАШ_ЛОГИН/hydrowin.git
git push -u origin gh-pages --force
```

В Settings → Pages выберите branch `gh-pages`, folder `/ (root)`.

### Шаг 3 — Адрес сайта

Через 1–3 минуты сайт будет доступен:

- `https://ВАШ_ЛОГИН.github.io/hydrowin/` (если репозиторий не `username.github.io`)

### Шаг 4 — Свой домен на GitHub Pages

1. Settings → Pages → **Custom domain** → `www.hydrowin.ru`  
2. У регистратора домена добавьте DNS-записи (GitHub покажет что именно):
   - обычно **A** на IP GitHub Pages **или** **CNAME** `www` → `ВАШ_ЛОГИН.github.io`  
3. Включите **Enforce HTTPS** после проверки DNS (до 24 ч).

---

## 3. Netlify (бесплатно, без Git — drag & drop)

Самый простой способ «залить папку и получить ссылку».

### Шаг 1

1. https://app.netlify.com → Sign up (можно через GitHub)  
2. На главной: **Add new site** → **Deploy manually**  
3. Перетащите папку **`website`** в окно браузера (не весь репозиторий)

### Шаг 2

Netlify выдаст адрес вида `https://random-name-123.netlify.app`

**Site configuration** → **Change site name** → например `hydrowin` →  
итог: `https://hydrowin.netlify.app`

### Шаг 3 — Свой домен

**Domain management** → **Add custom domain** → `hydrowin.ru`  
Netlify подскажет DNS (CNAME или nameservers). После проверки включится HTTPS автоматически.

### Обновление сайта

Снова перетащите папку `website` в **Deploys** → **Drag and drop**,  
или подключите Git: **Add new site** → **Import from Git** → выберите репозиторий,  
**Base directory:** `website`, **Publish directory:** `website` (или `.` если base уже website).

---

## 4. Vercel (бесплатно, через Git)

1. https://vercel.com → Sign up  
2. **Add New Project** → Import Git Repository  
3. Root Directory: **`website`**  
4. Framework Preset: **Other** (статика)  
5. Deploy  

Домен: `проект.vercel.app` или свой в **Settings → Domains**.

---

## 5. REG.RU / Timeweb / Beget (обычный хостинг)

Типичный «виртуальный хостинг» с панелью (cPanel, ISPmanager).

### Шаг 1

Купите хостинг + домен (или привяжите已有 домен).

### Шаг 2 — Загрузка файлов

**Через файловый менеджер панели:**

1. Откройте каталог сайта — часто `public_html` или `www`  
2. Загрузите **содержимое** `website/` прямо в корень `public_html`:
   - `index.html` лежит в `public_html/index.html`, не в `public_html/website/index.html`

**Через FTP (FileZilla):**

| Поле | Значение |
|------|----------|
| Хост | ftp.ваш-домен.ru (из письма хостинга) |
| Логин / пароль | из панели хостинга |
| Порт | 21 |

Подключитесь → `public_html` → загрузите файлы из `website/`.

### Шаг 3

Откройте `https://ваш-домен.ru` — должен открыться лендинг.

SSL: в панели хостинга включите **Let's Encrypt** для домена (бесплатно).

---

## 6. VPS + nginx (для продвинутых)

Если есть сервер (Ubuntu) и домен указывает на IP сервера.

### На сервере

```bash
sudo apt update
sudo apt install nginx
sudo mkdir -p /var/www/hydrowin
```

Скопируйте файлы с ПК (PowerShell):

```powershell
scp -r "ПУТЬ\website\*" user@IP_СЕРВЕРА:/var/www/hydrowin/
```

Конфиг nginx `/etc/nginx/sites-available/hydrowin`:

```nginx
server {
    listen 80;
    server_name hydrowin.ru www.hydrowin.ru;
    root /var/www/hydrowin;
    index index.html;

    location / {
        try_files $uri $uri/ =404;
    }
}
```

```bash
sudo ln -s /etc/nginx/sites-available/hydrowin /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx
sudo apt install certbot python3-certbot-nginx
sudo certbot --nginx -d hydrowin.ru -d www.hydrowin.ru
```

---

## 7. Сравнение способов

| Способ | Сложность | Цена | Свой домен | HTTPS |
|--------|-----------|------|------------|-------|
| Netlify drag & drop | ★☆☆ | Бесплатно | Да | Авто |
| GitHub Pages | ★★☆ | Бесплатно | Да | Авто |
| Vercel + Git | ★★☆ | Бесплатно | Да | Авто |
| REG.RU / Timeweb | ★★☆ | от ~200 ₽/мес | Да | Let's Encrypt |
| VPS + nginx | ★★★ | от ~300 ₽/мес | Да | Certbot |

**Рекомендация для старта:** Netlify (быстро) или GitHub Pages (если код уже в Git).

---

## 8. Исправить ссылки на документацию (после публикации)

Если репозиторий на GitHub `https://github.com/USER/hydrowin`, в `index.html` замените, например:

```html
<!-- было -->
<a href="../docs/TZ-3.1-HydroWin.md">ТЗ 3.1</a>

<!-- стало -->
<a href="https://github.com/USER/hydrowin/blob/main/docs/TZ-3.1-HydroWin.md" target="_blank" rel="noopener">ТЗ 3.1</a>
```

Аналогично для `api/openapi.yaml`, `docs/protocol/BLE-packet-v1.md`, `README.md`.

После правки — повторный deploy (git push или drag & drop).

---

## 9. Чеклист перед «боевым» запуском

- [ ] Сайт открывается по `https://` (замок в браузере)
- [ ] Мобильная версия: меню ☰ работает
- [ ] Email в блоке «Связаться» — ваш реальный
- [ ] Ссылки на документацию ведут куда нужно (GitHub или `/docs` на сервере)
- [ ] Favicon отображается во вкладке
- [ ] Домен `www` и без `www` — один вариант редиректит на другой (настройка в Netlify/GitHub/хостинге)

---

## 10. Как обновлять сайт потом

| Хостинг | Действие |
|---------|----------|
| Netlify manual | Снова загрузить папку `website` |
| Netlify / Vercel + Git | `git push` в `main` — деплой сам |
| GitHub Pages | `git push` в ветку с Pages |
| FTP-хостинг | Заменить изменённые файлы в `public_html` |
| VPS | `scp` новых файлов в `/var/www/hydrowin` |

---

## 11. Частые проблемы

**«404» на главной**  
`index.html` не в корне публикации. Поднимите его на уровень `public_html` или укажите в настройках хостинга папку `website` как корень.

**Стили не применяются**  
Проверьте, что папка `css/` загружена и путь в HTML: `href="css/style.css"` (регистр букв на Linux важен).

**Документация по ссылке «не найдена»**  
Локальные пути `../docs/` на статике не работают — см. §8.

**Долго не открывается домен**  
DNS обновляется от 15 минут до 48 часов после смены записей.

---

## 12. Связь сайта с мобильным приложением

Лендинг и Flutter-приложение — **разные вещи**:

| Продукт | Где живёт | Как «выложить» |
|---------|-----------|----------------|
| Сайт | `website/` | Эта инструкция |
| Android APK | `mobile/hydrowin/` | Google Play или раздача APK |
| Web-версия приложения | `flutter build web` | Отдельный поддомен, напр. `app.hydrowin.ru` |

На лендинге можно добавить кнопку «Открыть демо» со ссылкой на `https://app.hydrowin.ru` после сборки Flutter Web.

Сборка web-приложения (отдельно от лендинга):

```powershell
cd mobile\hydrowin
flutter build web
```

Результат в `build/web/` — его можно выложить на **другой** сайт/поддомен теми же способами (Netlify, Pages и т.д.).

---

Вопросы по конкретному хостингу (REG.RU, Timeweb, GitHub) — уточните провайдера, можно расписать только его сценарий.
