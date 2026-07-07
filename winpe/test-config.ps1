<#
  test-config.ps1 - Diagnostic WinPE : que renvoie /api/pxe/config ?
  A poser sur le partage. Lancer depuis le WinPE :  & \\srv-pxe.ecollege19.lan\Deploy$\test-config.ps1
  (le partage doit etre monte ; sinon copier ce fichier sur X:\ et lancer  powershell -File X:\test-config.ps1)
  Ne touche PAS au disque. Token en dur (interne). ASCII pur.
#>
$ErrorActionPreference = 'Continue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
[System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }

$url = 'https://stats.ecollege19.lan/pc/api/pxe/config'
$tok = '3OjFft26Wdk4JxhBNUd90aRnS8c888m1jQPiuxF1E76iNTsArFnQJHGPRyUjUYcd'

Write-Host "GET $url" -ForegroundColor Cyan
try {
    $c = Invoke-RestMethod -Uri $url -Headers @{ 'X-PXE-Token' = $tok } -TimeoutSec 10
    Write-Host ("models   = " + @($c.models).Count) -ForegroundColor Green
    Write-Host ("ous      = " + @($c.ous).Count)    -ForegroundColor Green
    Write-Host ("settings = disk " + $c.settings.disk + " / unattend " + $c.settings.unattend)
    if (@($c.ous).Count) {
        Write-Host "--- OU ---" -ForegroundColor Cyan
        $c.ous | ForEach-Object { Write-Host ("  " + $_.label + "  ->  " + $_.ou_dn) }
    } else {
        Write-Host "Aucune OU dans la reponse (cote serveur)." -ForegroundColor Yellow
    }
} catch {
    Write-Host ("ERREUR : " + $_.Exception.Message) -ForegroundColor Red
    if ($_.Exception.Response) {
        try { $sr = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream()); Write-Host ("Corps : " + $sr.ReadToEnd()) -ForegroundColor Yellow } catch {}
    }
}
Read-Host "`nEntree pour fermer"
