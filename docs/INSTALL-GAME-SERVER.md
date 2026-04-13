# Установка на игровой сервер

## 1. Установить AmxxEasyHttp

Из релиза 1.4.0 взять:
- бинарный модуль под свою ОС
- include `easy_http.inc`

Разложить так:
- модуль -> `addons/amxmodx/modules/`
- include -> `addons/amxmodx/scripting/include/`

В `addons/amxmodx/configs/modules.ini` добавить строку:

```ini
easy_http
```

## 2. Установить плагин

- `HLTV_json_api_safe.sma` -> `addons/amxmodx/scripting/`
- после компиляции `HLTV_json_api_safe.amxx` -> `addons/amxmodx/plugins/`
- в `plugins.ini` добавить:

```ini
HLTV_json_api_safe.amxx
```

## 3. Настроить cvar

Пример:

```cfg
mjl_api_enabled "1"
mjl_api_url "http://172.17.0.1/api/matches/json"
mjl_api_key "CHANGE_ME"
mjl_api_timeout "30"
mjl_api_auto_send_finalize "1"
mjl_reset_after_finalize "0"
mjl_server_uid "srv1"
```

## 4. Проверка

В консоли сервера:

```text
amxx modules
amxx plugins
amx_cvar mjl_api_enabled
amx_cvar mjl_api_url
amx_cvar mjl_api_key
```

Плагин должен быть `running`, модуль `Amxx Easy Http` тоже `running`.
