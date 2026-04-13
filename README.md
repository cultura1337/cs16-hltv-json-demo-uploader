# CS 1.6 HLTV JSON + Demo Uploader

- AMXX-плагин формирует final JSON матча
- AMXX-плагин отправляет JSON в CMS API
- отдельный PHP CLI loader догружает demo
- CMS связывает JSON и demo по `match_id`

## Что внутри

### `plugin/`
- `scripting/HLTV_easyhttp.sma` — JSON-only версия плагина
- `include/easy_http.inc` — include для компиляции плагина
- `configs/server.cfg.example` — пример cvar
- `configs/modules.ini.example` — пример подключения модулей
- `install/plugins.ini.example` — пример подключения плагина

### `loader/`
- `uploader.php` — PHP CLI loader для demo upload
- `config.example.php` — пример конфига loader

### `docs/`
- `INSTALL-GAME-SERVER.md`
- `INSTALL-LOADER.md`
- `API-CONTRACT.md`
- `AMXX-EASYHTTP.md`

## Как это работает

1. HLTV пишет `.dem`
2. Плагин формирует final JSON матча
3. Плагин отправляет JSON в endpoint CMS
4. Loader отдельно отправляет demo в endpoint CMS
5. CMS связывает всё по `match_id`

Важно:
- веб ничего сам не забирает
- веб только принимает данные
- URL и API key берутся из конфига
- JSON и demo могут приезжать отдельно

## Что нужно скачать отдельно

Из релиза `AmxxEasyHttp 1.4.0` нужно взять бинарный модуль под свою ОС и положить его в:

- Linux: `addons/amxmodx/modules/easy_http_amxx_i386.so`
- Windows: `addons/amxmodx/modules/easy_http_amxx.dll`

Include `easy_http.inc` уже лежит в этом архиве.

Ссылка на релиз:
- `https://github.com/Next21Team/AmxxEasyHttp/releases/tag/1.4.0`

## Минимальная установка

1. Положить модуль `easy_http` в `addons/amxmodx/modules/`
2. Положить `easy_http.inc` в `addons/amxmodx/scripting/include/`
3. Положить `HLTV_easyhttp.sma` в `addons/amxmodx/scripting/`
4. Скомпилировать плагин локально или на сервере
5. Положить `HLTV_easyhttp.amxx` в `addons/amxmodx/plugins/`
6. В `modules.ini` добавить `easy_http`
7. В `plugins.ini` добавить `HLTV_easyhttp.amxx`
8. В `server.cfg` прописать API cvar

## Быстрый тест JSON API

Для локальной проверки можно поднять простой PHP endpoint и направить плагин в него. На практике уже проверено, что:
- запрос уходит именно из игрового контейнера
- `easy_http` работает
- JSON приходит валидный
- `match_id` доезжает в header и в body

## Loader

Одиночная загрузка demo:

```bash
php loader/uploader.php run --config=loader/config.php --json=/path/to/match.json
```

Сканирование папки:

```bash
php loader/uploader.php scan --config=loader/config.php --dir=/path/to/json/exports --limit=100
```

## Примечание по сборке

В архиве лежит исходник `.sma`. Готовый `.amxx` для этой безопасной версии не приложен, потому что он должен быть скомпилирован под твою текущую среду AMXX.
