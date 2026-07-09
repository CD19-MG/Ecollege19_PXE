@echo off
title Preparer la capture - eCollege19
color 0B
echo(
echo   ============================================================
echo     PREPARATION DE CE POSTE POUR LA CAPTURE (image de reference)
echo   ============================================================
echo(
echo   Ce poste va etre GENERALISE (sysprep) puis ETEINT automatiquement.
echo(
echo   ENSUITE :
echo     1) Rallumez le poste
echo     2) Demarrez sur le reseau (touche F12 / F9 selon le modele)
echo     3) Dans le menu, choisissez : [2] Capturer une image de reference
echo(
echo   ATTENTION : a faire UNIQUEMENT sur un poste MODELE
echo   (Windows + logiciels installes), jamais sur un poste en service.
echo(

rem --- Doit etre lance en administrateur ---
net session >nul 2>&1
if %errorlevel% neq 0 (
  echo   [ERREUR] Faites un CLIC DROIT sur ce fichier puis
  echo            "Executer en tant qu'administrateur".
  echo(
  pause
  exit /b 1
)

choice /c ON /n /m "   Lancer la preparation maintenant ? (O = oui / N = non) : "
if errorlevel 2 exit /b 0

echo(
echo   Nettoyage avant capture (WinSxS, cache Windows Update, temp, corbeille)...
echo   (peut prendre quelques minutes, patientez)
if exist "%~dp0Clean-BeforeCapture.ps1" (
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Clean-BeforeCapture.ps1"
) else (
  echo   [INFO] Clean-BeforeCapture.ps1 absent -> nettoyage saute.
)

echo(
echo   Generalisation en cours... le poste va s'eteindre tout seul.
echo   (ne rien faire, patientez)
echo(
rem generalize.xml (SkipRearm) a cote -> on ne consomme pas le compteur de rearm
rem (on peut re-syspreper un master autant de fois qu'on veut).
set "GEN=%~dp0generalize.xml"
if exist "%GEN%" (
  "%WINDIR%\System32\Sysprep\sysprep.exe" /generalize /oobe /shutdown /unattend:"%GEN%"
) else (
  "%WINDIR%\System32\Sysprep\sysprep.exe" /generalize /oobe /shutdown
)

rem Si sysprep echoue, il n'eteint pas : on laisse la fenetre ouverte pour lire l'erreur.
echo(
echo   Si le poste ne s'eteint PAS, une erreur est survenue. Consultez :
echo     %WINDIR%\System32\Sysprep\Panther\setuperr.log
echo   (cause frequente : une application du Microsoft Store bloque sysprep).
echo(
pause
