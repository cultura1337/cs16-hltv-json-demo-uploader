<?php

declare(strict_types=1);

return [
    // Base CMS URL without trailing slash.
    'api_base_url' => 'https://example.com',

    // API key expected by the CMS module.
    'api_key' => 'CHANGE_ME',

    // Demo upload chunk size.
    'chunk_size_bytes' => 262144, // 256 KB

    // cURL timeouts.
    'connect_timeout' => 10,
    'request_timeout' => 60,

    // Only upload final JSON exports.
    'require_final_json' => true,

    // Skip files that already have a success marker next to them.
    'skip_if_marker_exists' => true,

    // Optional fallback search paths if demo.path from JSON is missing or invalid.
    'demo_search_dirs' => [
        '/home/container/hltv',
        '/home/container/cstrike',
    ],
];
