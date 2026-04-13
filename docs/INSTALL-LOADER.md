# Установка loader

Требования:
- PHP 8.1+
- ext-curl

## Настройка

1. Скопировать `loader/config.example.php` в `loader/config.php`
2. Заполнить URL и API key
3. Запускать loader вручную или по cron

## Одиночный запуск

```bash
php loader/uploader.php run --config=loader/config.php --json=/path/to/match.json
```

## Режим сканирования

```bash
php loader/uploader.php scan --config=loader/config.php --dir=/path/to/json/exports --limit=100
```

## Что делает loader

- читает `match_id` из уже сформированного JSON
- ищет demo по `demo.path` / `demo.filename`
- отправляет demo через `init / chunk / complete`
- создаёт marker `.demo_uploaded` рядом с JSON
