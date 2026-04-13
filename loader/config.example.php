<?php

declare(strict_types=1);

return [
    'api_base_url' => 'https://example.com',
    'api_key' => 'CHANGE_ME',

    'chunk_size_bytes' => 262144,

    'connect_timeout' => 10,
    'request_timeout' => 60,

    'require_final_json' => true,
    'skip_if_marker_exists' => true,

    'demo_search_dirs' => [
        '/home/container/hltv',
        '/home/container/cstrike',
    ],

    'match_time_window_seconds' => 3600,
    'min_demo_size_bytes' => 10240,
];
