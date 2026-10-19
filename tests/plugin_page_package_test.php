<?php
// Usage: php plugin_page_package_test.php CHIM/lib/plugin_discovery.php chim-plugin.tar.gz SHARMAT.zip
if (PHP_SAPI !== 'cli' || $argc !== 4) {
    fwrite(STDERR, "Provide CHIM discovery code, the server archive, and the full mod ZIP.\n");
    exit(1);
}
require $argv[1];
$checks = 0;
function pagePackageAssert($condition, $message) {
    global $checks;
    $checks++;
    if (!$condition) throw new RuntimeException($message);
}
$stage = sys_get_temp_dir() . '/sharmat-page-test-' . bin2hex(random_bytes(8));
mkdir($stage, 0700);
try {
    $tar = new PharData($argv[2]);
    $outer = new ZipArchive();
    pagePackageAssert($outer->open($argv[3]) === true, 'Cannot open full mod ZIP');
    $version = trim($outer->getFromName('version.txt'));
    $embedded = $outer->getFromName('CHIM/server-plugins/aiagent_nsfw/' . $version . '.dwpkg');
    pagePackageAssert($embedded !== false, 'Matching embedded server package is missing');
    file_put_contents($stage . '/embedded.zip', $embedded);
    $inner = new ZipArchive();
    pagePackageAssert($inner->open($stage . '/embedded.zip') === true, 'Cannot open embedded package');
    $source = ['repo' => 'Wondernuttz/Sharmat-Alpha', 'repo_id' => 1,
        'display_name' => 'SHARMAT', 'description' => '', 'tag' => 'v' . $version,
        'asset' => 'chim-plugin.tar.gz', 'url' => 'https://github.com/Wondernuttz/Sharmat-Alpha/releases/download/v' . $version . '/chim-plugin.tar.gz',
        'channel' => 'main', 'channel_label' => 'Live'];
    foreach (['discovery', 'embedded'] as $format) {
        foreach (['manifest.json', 'config_manager.php', 'index.php'] as $file) {
            pagePackageAssert(isset($tar[$file]), 'Server archive missing ' . $file);
            $serverBytes = $tar[$file]->getContent();
            $embeddedBytes = $inner->getFromName('server/' . $file);
            pagePackageAssert($embeddedBytes === $serverBytes, 'Package formats differ for ' . $file);
            pagePackageAssert($serverBytes === file_get_contents(dirname(__DIR__) . '/' . $file), 'Package differs from source: ' . $file);
            file_put_contents($stage . '/' . $file, $format === 'discovery' ? $serverBytes : $embeddedBytes);
        }
        // Reproduce the prior installer behavior: config_manager.php alone is not discovered.
        rename($stage . '/index.php', $stage . '/index.pending');
        $before = chimPluginGeneratedManifest($stage, 'aiagent_nsfw', $source, '/HerikaServer');
        pagePackageAssert(!isset($before['config_url']), 'Missing-index failure was not reproduced');
        rename($stage . '/index.pending', $stage . '/index.php');
        $after = chimPluginGeneratedManifest($stage, 'aiagent_nsfw', $source, '/HerikaServer');
        pagePackageAssert(($after['config_url'] ?? '') === '/HerikaServer/ext/aiagent_nsfw/index.php', 'Installer did not generate Plugin Page link');
        pagePackageAssert(($after['config_url_target'] ?? '') === '_blank', 'Plugin Page target changed');
        $customRoot = chimPluginGeneratedManifest($stage, 'aiagent_nsfw', $source, '/custom/server');
        pagePackageAssert(($customRoot['config_url'] ?? '') === '/custom/server/ext/aiagent_nsfw/index.php', 'Custom server root is not supported');
        echo $format . ": CHIM discovers Plugin Page from the packaged entry point.\n";
    }
    $inner->close();
    $outer->close();
} finally {
    foreach (['manifest.json', 'config_manager.php', 'index.php', 'index.pending', 'embedded.zip'] as $file) {
        if (is_file($stage . '/' . $file)) unlink($stage . '/' . $file);
    }
    rmdir($stage);
}
echo "Plugin Page package checks passed ({$checks} assertions).\n";
