# Inicia o registro do Transcript no arquivo build.log
Start-Transcript -Path "build.log" -Force

try {
    # Executa a task Test do seu projeto
    Invoke-Build Test
}
finally {
    # Garante o fechamento do Transcript para liberar o arquivo
    Stop-Transcript

    # Remove os códigos de cor ANSI do arquivo final
    if (Test-Path "build.log") {
        $logContent = Get-Content "build.log" -Raw
        
        # Expressão regular para capturar o caractere de Escape + padrões de cor
        $ansiRegex = "$([char]27)\[[0-9;]*[a-zA-Z]"
        $cleanContent = $logContent -replace $ansiRegex, ''
        
        # Reescreve o arquivo sem as marcações coloridas
        Set-Content -Path "build.log" -Value $cleanContent
    }
}