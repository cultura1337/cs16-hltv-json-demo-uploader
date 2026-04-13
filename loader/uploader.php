#!/usr/bin/env php
<?php

declare(strict_types=1);

const EXIT_OK = 0;
const EXIT_CONFIG = 2;
const EXIT_INPUT = 3;
const EXIT_HTTP = 4;
const EXIT_RUNTIME = 5;

main($argv);

function main(array $argv): void
{
    try {
        $args = parseArgs($argv);

        if (!extension_loaded('curl')) {
            throw new RuntimeException('The cURL extension is required.');
        }

        $configPath = $args['config'] ?? __DIR__ . '/config.php';
        if (!is_file($configPath)) {
            throw new InvalidArgumentException("Config not found: {$configPath}");
        }

        /** @var array<string,mixed> $config */
        $config = require $configPath;
        validateConfig($config);

        $command = $args['command'] ?? 'run';
        switch ($command) {
            case 'run':
                $jsonPath = $args['json'] ?? null;
                if (!$jsonPath) {
                    throw new InvalidArgumentException('Use --json=/path/to/match.json');
                }
                $demoOverride = $args['demo'] ?? null;
                processOne($config, $jsonPath, $demoOverride, true);
                break;

            case 'scan':
                $dir = $args['dir'] ?? null;
                if (!$dir) {
                    throw new InvalidArgumentException('Use --dir=/path/to/json/exports');
                }
                scanDirectory($config, $dir, (int)($args['limit'] ?? 100));
                break;

            default:
                throw new InvalidArgumentException("Unknown command: {$command}");
        }
    } catch (InvalidArgumentException $e) {
        fwrite(STDERR, "[input] {$e->getMessage()}\n");
        exit(EXIT_INPUT);
    } catch (RuntimeException $e) {
        fwrite(STDERR, "[runtime] {$e->getMessage()}\n");
        exit(EXIT_RUNTIME);
    } catch (Throwable $e) {
        fwrite(STDERR, "[fatal] {$e->getMessage()}\n");
        exit(EXIT_RUNTIME);
    }

    exit(EXIT_OK);
}

/**
 * @return array<string,string>
 */
function parseArgs(array $argv): array
{
    $result = [];
    $result['command'] = $argv[1] ?? 'run';

    for ($i = 2; $i < count($argv); $i++) {
        $arg = $argv[$i];
        if (!str_starts_with($arg, '--')) {
            continue;
        }

        $parts = explode('=', substr($arg, 2), 2);
        $key = $parts[0];
        $value = $parts[1] ?? '1';
        $result[$key] = $value;
    }

    return $result;
}

/**
 * @param array<string,mixed> $config
 */
function validateConfig(array $config): void
{
    $required = ['api_base_url', 'api_key', 'chunk_size_bytes', 'connect_timeout', 'request_timeout'];
    foreach ($required as $key) {
        if (!array_key_exists($key, $config) || $config[$key] === '' || $config[$key] === null) {
            throw new RuntimeException("Missing config key: {$key}");
        }
    }

    if ((int)$config['chunk_size_bytes'] < 16 * 1024) {
        throw new RuntimeException('chunk_size_bytes is too small. Use at least 16384.');
    }
}

/**
 * @param array<string,mixed> $config
 */
function scanDirectory(array $config, string $dir, int $limit): void
{
    $dir = realpath($dir) ?: $dir;
    if (!is_dir($dir)) {
        throw new InvalidArgumentException("Directory not found: {$dir}");
    }

    $files = glob(rtrim($dir, DIRECTORY_SEPARATOR) . DIRECTORY_SEPARATOR . '*.json');
    if (!$files) {
        echo "[scan] no json files found in {$dir}\n";
        return;
    }

    sort($files, SORT_STRING);
    $processed = 0;

    foreach ($files as $jsonPath) {
        if ($processed >= $limit) {
            break;
        }

        try {
            processOne($config, $jsonPath, null, false);
            $processed++;
        } catch (Throwable $e) {
            fwrite(STDERR, "[scan] failed {$jsonPath}: {$e->getMessage()}\n");
        }
    }

    echo "[scan] processed {$processed} file(s)\n";
}

/**
 * @param array<string,mixed> $config
 */
function processOne(array $config, string $jsonPath, ?string $demoOverride, bool $strict): void
{
    $jsonPath = realpath($jsonPath) ?: $jsonPath;
    if (!is_file($jsonPath)) {
        throw new InvalidArgumentException("JSON file not found: {$jsonPath}");
    }

    $markerPath = $jsonPath . '.demo_uploaded';
    if (!empty($config['skip_if_marker_exists']) && is_file($markerPath)) {
        echo "[skip] marker exists: {$jsonPath}\n";
        return;
    }

    $payload = decodeJsonFile($jsonPath);

    $matchId = (string)($payload['match_id'] ?? '');
    if ($matchId === '') {
        throw new RuntimeException("match_id is missing in {$jsonPath}");
    }

    $completed = (bool)($payload['completed'] ?? false);
    $exportType = (string)($payload['export_type'] ?? '');
    if (!empty($config['require_final_json']) && (!$completed || $exportType !== 'final')) {
        $message = "JSON is not final: {$jsonPath}";
        if ($strict) {
            throw new RuntimeException($message);
        }
        echo "[skip] {$message}\n";
        return;
    }

    $demoPath = resolveDemoPath($payload, $jsonPath, $demoOverride, $config);
    if (!is_file($demoPath)) {
        throw new RuntimeException("Demo file not found: {$demoPath}");
    }

    $demoSize = filesize($demoPath);
    if ($demoSize === false || $demoSize <= 0) {
        throw new RuntimeException("Demo file is empty or unreadable: {$demoPath}");
    }

    $filename = basename($demoPath);
    $provider = (string)($payload['demo']['provider'] ?? 'HLTV');
    $chunkSize = (int)$config['chunk_size_bytes'];
    $chunksTotal = (int)ceil($demoSize / $chunkSize);

    echo "[run] match_id={$matchId}\n";
    echo "[run] demo={$demoPath}\n";
    echo "[run] size={$demoSize} bytes, chunks={$chunksTotal}\n";

    $apiBase = rtrim((string)$config['api_base_url'], '/');
    $headers = [
        'X-API-Key: ' . (string)$config['api_key'],
        'Accept: application/json',
    ];

    $initResponse = postMultipart(
        $apiBase . '/api/matches/demo/init',
        $headers,
        [
            'match_id' => $matchId,
            'filename' => $filename,
            'total_size' => (string)$demoSize,
            'chunks_total' => (string)$chunksTotal,
            'provider' => $provider,
        ],
        [],
        $config
    );

    $uploadId = (string)($initResponse['upload_id'] ?? '');
    if ($uploadId === '') {
        throw new RuntimeException('init response does not contain upload_id');
    }

    $fp = fopen($demoPath, 'rb');
    if ($fp === false) {
        throw new RuntimeException("Failed to open demo file: {$demoPath}");
    }

    try {
        $chunkIndex = 0;
        while (!feof($fp)) {
            $binary = fread($fp, $chunkSize);
            if ($binary === false) {
                throw new RuntimeException("Failed to read demo chunk {$chunkIndex}");
            }

            if ($binary === '') {
                break;
            }

            postRaw(
                $apiBase . '/api/matches/demo/chunk?upload_id=' . rawurlencode($uploadId) . '&chunk_index=' . $chunkIndex,
                array_merge($headers, [
                    'Content-Type: application/octet-stream',
                    'X-Match-Id: ' . $matchId,
                    'X-Chunk-Index: ' . (string)$chunkIndex,
                ]),
                $binary,
                $config
            );

            echo "[chunk] sent {$chunkIndex} / " . ($chunksTotal - 1) . "\n";
            $chunkIndex++;
        }
    } finally {
        fclose($fp);
    }

    postMultipart(
        $apiBase . '/api/matches/demo/complete',
        $headers,
        [
            'upload_id' => $uploadId,
            'match_id' => $matchId,
        ],
        [],
        $config
    );

    file_put_contents($markerPath, json_encode([
        'match_id' => $matchId,
        'demo_path' => $demoPath,
        'uploaded_at' => date(DATE_ATOM),
        'upload_id' => $uploadId,
    ], JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES));

    echo "[done] demo uploaded for {$matchId}\n";
}

/**
 * @return array<string,mixed>
 */
function decodeJsonFile(string $path): array
{
    $data = file_get_contents($path);
    if ($data === false || $data === '') {
        throw new RuntimeException("Failed to read JSON file: {$path}");
    }

    /** @var array<string,mixed>|null $decoded */
    $decoded = json_decode($data, true);
    if (!is_array($decoded)) {
        throw new RuntimeException("Invalid JSON in {$path}");
    }

    return $decoded;
}

/**
 * @param array<string,mixed> $payload
 * @param array<string,mixed> $config
 */
function resolveDemoPath(array $payload, string $jsonPath, ?string $demoOverride, array $config): string
{
    if ($demoOverride !== null && $demoOverride !== '') {
        return $demoOverride;
    }

    $fromJson = (string)($payload['demo']['path'] ?? '');
    if ($fromJson !== '' && is_file($fromJson)) {
        return $fromJson;
    }

    $filename = (string)($payload['demo']['filename'] ?? '');
    if ($filename === '') {
        throw new RuntimeException("demo.filename is missing in {$jsonPath}");
    }

    $jsonDir = dirname($jsonPath);
    $candidate = $jsonDir . DIRECTORY_SEPARATOR . $filename;
    if (is_file($candidate)) {
        return $candidate;
    }

    $searchDirs = $config['demo_search_dirs'] ?? [];
    if (is_array($searchDirs)) {
        foreach ($searchDirs as $dir) {
            if (!is_string($dir) || $dir === '') {
                continue;
            }

            $candidate = rtrim($dir, DIRECTORY_SEPARATOR) . DIRECTORY_SEPARATOR . $filename;
            if (is_file($candidate)) {
                return $candidate;
            }
        }
    }

    return $fromJson !== '' ? $fromJson : $candidate;
}

/**
 * @param array<int,string> $headers
 * @param array<string,string> $fields
 * @param array<string,CURLFile> $files
 * @param array<string,mixed> $config
 * @return array<string,mixed>
 */
function postMultipart(string $url, array $headers, array $fields, array $files, array $config): array
{
    $ch = curl_init($url);
    if ($ch === false) {
        throw new RuntimeException('Failed to initialize curl');
    }

    $postFields = $fields;
    foreach ($files as $name => $file) {
        $postFields[$name] = $file;
    }

    curl_setopt_array($ch, [
        CURLOPT_POST => true,
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_HTTPHEADER => $headers,
        CURLOPT_POSTFIELDS => $postFields,
        CURLOPT_CONNECTTIMEOUT => (int)$config['connect_timeout'],
        CURLOPT_TIMEOUT => (int)$config['request_timeout'],
    ]);

    $responseBody = curl_exec($ch);
    $httpCode = (int)curl_getinfo($ch, CURLINFO_RESPONSE_CODE);
    $error = curl_error($ch);
    curl_close($ch);

    if ($responseBody === false) {
        throw new RuntimeException('HTTP request failed: ' . $error);
    }

    if ($httpCode < 200 || $httpCode >= 300) {
        throw new RuntimeException("HTTP {$httpCode}: {$responseBody}");
    }

    $decoded = json_decode($responseBody, true);
    return is_array($decoded) ? $decoded : ['raw' => $responseBody];
}

/**
 * @param array<int,string> $headers
 * @param array<string,mixed> $config
 * @return array<string,mixed>
 */
function postRaw(string $url, array $headers, string $body, array $config): array
{
    $ch = curl_init($url);
    if ($ch === false) {
        throw new RuntimeException('Failed to initialize curl');
    }

    curl_setopt_array($ch, [
        CURLOPT_POST => true,
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_HTTPHEADER => array_merge($headers, [
            'Content-Length: ' . strlen($body),
        ]),
        CURLOPT_POSTFIELDS => $body,
        CURLOPT_CONNECTTIMEOUT => (int)$config['connect_timeout'],
        CURLOPT_TIMEOUT => (int)$config['request_timeout'],
    ]);

    $responseBody = curl_exec($ch);
    $httpCode = (int)curl_getinfo($ch, CURLINFO_RESPONSE_CODE);
    $error = curl_error($ch);
    curl_close($ch);

    if ($responseBody === false) {
        throw new RuntimeException('HTTP request failed: ' . $error);
    }

    if ($httpCode < 200 || $httpCode >= 300) {
        throw new RuntimeException("HTTP {$httpCode}: {$responseBody}");
    }

    $decoded = json_decode($responseBody, true);
    return is_array($decoded) ? $decoded : ['raw' => $responseBody];
}
