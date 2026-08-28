# HydroWin: Hyper-V Ubuntu на SRVR002 (5.165.27.141)

Публичный IP **не меняется**. Keenetic продолжает слать 80/443(/1883) на LAN-IP,
после миграции — на IP Ubuntu VM вместо Windows `192.168.1.50` (SRVR002).

## Текущее состояние (проверено)

| Компонент | Статус |
|-----------|--------|
| Hyper-V | Включён |
| VirtualMachinePlatform | Выключен (для Ubuntu VM не обязателен) |
| Docker Desktop VM | `DockerDesktopVM` Running |
| LAN Windows | `192.168.1.50` (Ethernet) |
| Switch | только `Default Switch` (Internal) — нужен **External** |
| Keenetic → SRVR002 | 80, 443, 1883, **8090** (8090 потом удалить) |

## Архитектура после миграции

```
Интернет → 5.165.27.141
 Keenetic NAT 80/443/1883 → Ubuntu VM (например 192.168.1.60)
                              Docker Engine: caddy, api, db, mosquitto
 Windows SRVR002 (192.168.1.50)
   RDP, Flutter, прошивка ESP32, Hyper-V Manager
   Docker Desktop можно остановить (чтобы не путать)
```

---

## Шаг 1. Бэкап (на Windows, пока стек Up)

PowerShell в `backend`:

```powershell
mkdir backups\pre_hyperv_ubuntu -Force
$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
docker exec backend-db-1 pg_dump -U hydrowin -d hydrowin --no-owner --no-acl `
  | Set-Content "backups\pre_hyperv_ubuntu\hydrowin_$stamp.sql" -Encoding utf8
Copy-Item .env "backups\pre_hyperv_ubuntu\.env.$stamp"
```

Проверьте, что `.sql` не пустой (десятки МБ при ~2M readings).

---

## Шаг 2. External switch (PowerShell **Администратор**)

```powershell
# Имя физического адаптера — у вас Ethernet
Get-NetAdapter | Format-Table Name, Status, MacAddress

New-VMSwitch -Name "LAN-External" -NetAdapterName "Ethernet" -AllowManagementOS $true
Get-VMSwitch
```

После создания Windows может на секунды потерять сеть — нормально.

---

## Шаг 3. Создать Ubuntu Server VM

1. Скачать ISO: https://ubuntu.com/download/server (24.04 LTS)
2. Hyper-V Manager → New → Virtual Machine:
   - Name: `hydrowin-ubuntu`
   - Generation: **2**
   - Memory: **4096 MB** (динамическая ок), ≥ 4 ГБ
   - Network: **LAN-External**
   - Disk: **40–60 GB** VHDX
   - Install from ISO Ubuntu Server
3. Settings VM:
   - Secure Boot: Microsoft UEFI Certificate Authority (или временно Off, если ISO не грузится)
   - Processors: **2–4**
4. Установка Ubuntu:
   - OpenSSH server: **Yes**
   - пользователь например `hydrowin`
5. После установки узнать IP:

```bash
ip -4 addr show
hostname -I
```

Зафиксируйте IP (пример `192.168.1.60`). В Keenetic лучше сделать **резервацию DHCP** по MAC этой VM.

---

## Шаг 4. Docker Engine на Ubuntu (внутри VM)

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo $VERSION_CODENAME) stable" \
| sudo tee /etc/apt/sources.list.d/docker.list
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
sudo usermod -aG docker $USER
# выйти и зайти по SSH снова
docker version
```

---

## Шаг 5. Скопировать проект с Windows → Ubuntu

С **Windows** (подставьте IP VM и пользователя):

```powershell
cd C:\Users\Admin2\Desktop\HW2.0\hydrowin\hydrowin
scp -r backend hydrowin@192.168.1.60:~/hydrowin-backend
```

Или через общий диск / WinSCP. Важно: файл `.env` и свежий `.sql` dump.

На Ubuntu:

```bash
cd ~/hydrowin-backend
# убедиться что .env на месте
ls -la .env docker-compose.yml
```

В `docker-compose.yml` уже **нет** `ports: 8090:8090` у api — так и оставляем.

---

## Шаг 6. Окно простоя: остановить Windows-стек

На Windows:

```powershell
cd C:\Users\Admin2\Desktop\HW2.0\hydrowin\hydrowin\backend
docker compose stop
```

(Не удаляйте volumes, пока Ubuntu не подтвердит health.)

---

## Шаг 7. Поднять стек на Ubuntu + восстановить БД

```bash
cd ~/hydrowin-backend
docker compose up -d --build
# дождаться healthy db
docker compose ps

# восстановить дамп (имя файла своё)
gunzip -c backups/... 2>/dev/null || true
docker compose exec -T db psql -U hydrowin -d hydrowin < backups/pre_hyperv_ubuntu/hydrowin_XXXX.sql
```

Если дамп в UTF-8 с BOM от PowerShell — при ошибках:

```bash
sed '1s/^\xEF\xBB\xBF//' hydrowin_XXXX.sql | docker compose exec -T db psql -U hydrowin -d hydrowin
```

Проверка локально в VM:

```bash
curl -s http://127.0.0.1:80/v1/health
# или через caddy внутри сети:
docker compose exec api wget -qO- http://127.0.0.1:8090/v1/health
```

---

## Шаг 8. Keenetic NAT (критично)

Правила для **ISP →** сейчас Destination **SRVR002**. Изменить на IP Ubuntu:

| Порт | Было | Стало |
|------|------|--------|
| http 80 | SRVR002 | `192.168.1.xx` (Ubuntu) |
| https 443 | SRVR002 | Ubuntu |
| tcp 1883 | SRVR002 | Ubuntu (если нужен MQTT с улицы) |
| **tcp 8090** | SRVR002 | **Удалить правило** (api не публикуем) |

RDP `3398 → SRVR002:3389` **не трогать** — Windows остаётся для админки.

Проверка с телефона/внешней сети:

```text
https://app.hydrowin.ru/v1/health → {"status":"ok"}
```

Caddy выпускает сертификат для `app.hydrowin.ru` при первом старте — подождите 1–2 мин.

---

## Шаг 9. После успеха на Windows

```powershell
# когда Ubuntu стабильно работает сутки:
docker compose down
# Docker Desktop можно выключить автозапуск — чтобы не жрал RAM
```

Volumes Windows пока **не удалять** 7 дней.

---

## Откат

1. Keenetic снова Destination = SRVR002 для 80/443/1883  
2. На Windows: `docker compose up -d`  
3. Health ok → работаем как раньше  

---

## Чеклист

- [ ] pg_dump + копия `.env`
- [ ] External switch `LAN-External`
- [ ] Ubuntu VM + SSH + свой LAN IP + DHCP reservation
- [ ] Docker Engine на Ubuntu
- [ ] Скопирован `backend` + `.env` + dump
- [ ] `docker compose stop` на Windows
- [ ] `compose up` + restore на Ubuntu
- [ ] Keenetic → Ubuntu; правило **8090 удалено**
- [ ] health с улицы ok
- [ ] ingest с платы / логин в приложении
