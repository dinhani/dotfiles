function claude {
    $configDir = python (Join-Path $HOME 'scripts\claude.py')
    if ($LASTEXITCODE -ne 0) { return }
    $configDirPrevious = $env:CLAUDE_CONFIG_DIR
    if ($configDir) { $env:CLAUDE_CONFIG_DIR = $configDir } else { Remove-Item Env:CLAUDE_CONFIG_DIR -ErrorAction Ignore }
    try {
        claude.exe --dangerously-skip-permissions @args
    }
    finally {
        $env:CLAUDE_CONFIG_DIR = $configDirPrevious
    }
}
