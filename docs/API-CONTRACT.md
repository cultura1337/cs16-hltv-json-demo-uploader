# API Contract

## 1. JSON матч

### Endpoint
`POST /api/matches/json`

### Headers
- `X-API-Key`
- `Content-Type: application/json`
- `X-Match-Id`

### Body
Final JSON матча.

---

## 2. Demo init

### Endpoint
`POST /api/matches/demo/init`

### Headers
- `X-API-Key`
- `Content-Type: application/json`

### Body
```json
{
  "match_id": "1776086215_de_nuke_subcultura_mix",
  "filename": "match_1776086215_de_nuke.dem",
  "total_size": 18432000,
  "chunk_size": 262144,
  "chunks_total": 71,
  "provider": "HLTV"
}
```

### Response
```json
{
  "success": true,
  "upload_id": "abc123"
}
```

---

## 3. Demo chunk

### Endpoint
`POST /api/matches/demo/chunk?upload_id=abc123&chunk_index=0`

### Headers
- `X-API-Key`
- `Content-Type: application/octet-stream`

### Body
Бинарные данные чанка.

### Response
```json
{
  "success": true,
  "chunk_index": 0
}
```

---

## 4. Demo complete

### Endpoint
`POST /api/matches/demo/complete`

### Headers
- `X-API-Key`
- `Content-Type: application/json`

### Body
```json
{
  "upload_id": "abc123",
  "match_id": "1776086215_de_nuke_subcultura_mix"
}
```

### Response
```json
{
  "success": true,
  "match_id": "1776086215_de_nuke_subcultura_mix",
  "demo_attached": true
}
```
