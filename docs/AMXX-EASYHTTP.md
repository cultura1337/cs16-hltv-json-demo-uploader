# Что брать из AmxxEasyHttp

Репозиторий:
- https://github.com/Next21Team/AmxxEasyHttp

Релиз 1.4.0:
- https://github.com/Next21Team/AmxxEasyHttp/releases/tag/1.4.0

## Что нужно для этого проекта

### Обязательно
1. Бинарный модуль под свою ОС:
   - Linux: `easy_http_amxx_i386.so`
   - Windows: `easy_http_amxx.dll`

2. Include для компиляции Pawn:
   - `easy_http.inc`

## Что подключать в коде

```pawn
#include <easy_http>
```

## Что прописывать в modules.ini

```ini
easy_http
```

## Что важно по модулю

- модуль неблокирующий
- поддерживает кастомные headers
- поддерживает POST body
- использует несколько worker threads
- для последовательных запросов нужна queue
- на смене карты запросы могут отменяться, если не выставить соответствующее поведение

Для текущего проекта это важно потому, что:
- JSON матч можно слать напрямую из плагина
- demo upload лучше держать отдельным loader
- если когда-то делать `init -> chunk -> complete` прямо из AMXX, запросы должны идти строго последовательно
