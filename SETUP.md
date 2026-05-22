# Setup Rápido do GitMe

## 1. Desbloquear o script de build (única vez)

O Windows marca scripts baixados da Internet como bloqueados. Execute:

```powershell
Unblock-File -Path "C:\Users\mvale\Projetinhos\GitMe\gitme.build.ps1"
Unblock-File -Path "C:\Users\mvale\Projetinhos\GitMe\.build\*.ps1"
```

## 2. Instalar dependências de build (única vez)

```powershell
.\.build\dependencies.ps1
```

Este script instala automaticamente:
- InvokeBuild
- Pester 5
- PSScriptAnalyzer
- PowerShellGet
- PackageManagement

## 3. Executar o build completo

```powershell
Invoke-Build
```

Ou, se preferir ver cada etapa separadamente:

```powershell
Invoke-Build Clean
Invoke-Build Format
Invoke-Build Analyze
Invoke-Build Security
Invoke-Build Test
Invoke-Build Build
Invoke-Build Package
```

## 4. Instalar o módulo localmente para testar

```powershell
Import-Module .\src\GitMe.psd1 -Force
gitme -Version
```

## 5. Publicar no PSGallery (requer API key)

```powershell
Invoke-Build Publish -NuGetApiKey "sua-chave-aqui"
```

---

**Nota sobre segurança:** O aviso de execução de scripts é uma proteção do Windows. O `Unblock-File` remove a flag de "Internet" dos arquivos após você verificar manualmente que confia neles. Nunca execute `Unblock-File` em scripts de fontes não confiáveis.
