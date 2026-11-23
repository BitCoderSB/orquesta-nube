param([string]$TareaArchivo, [string]$Log)
# Windows: claude --cloud exige una consola real; nube.sh abre esta en una ventana minimizada.
Start-Transcript -Path $Log -Force | Out-Null
$tarea = Get-Content -Raw -Encoding UTF8 $TareaArchivo
claude --cloud $tarea
"exit=$LASTEXITCODE"
Stop-Transcript | Out-Null
