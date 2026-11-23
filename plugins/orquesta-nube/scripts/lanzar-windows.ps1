param([string]$TareaArchivo, [string]$Log, [string]$Claude = "claude")
# Windows: claude --cloud exige una consola real; nube.sh abre esta en una ventana minimizada.
# $Claude: "claude" del PATH, o la ruta del claude.exe que trae la app de escritorio.
Start-Transcript -Path $Log -Force | Out-Null
$tarea = Get-Content -Raw -Encoding UTF8 $TareaArchivo
& $Claude --cloud $tarea
"exit=$LASTEXITCODE"
Stop-Transcript | Out-Null
