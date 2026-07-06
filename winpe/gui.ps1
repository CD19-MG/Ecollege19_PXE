<#
  gui.ps1 - Interface graphique (WinForms) pour le WinPE, sur le PARTAGE (editable sans rebuild).
  WinForms est dispo grace au composant WinPE-NetFx. Si le chargement echoue sur un WinPE donne,
  Test-Gui renvoie $false et les scripts appelants retombent sur des invites texte (Read-Host).
  Dot-source depuis menu.ps1 / deploy.ps1 / capture.ps1 :  . "$Share\gui.ps1"
  ASCII pur.

  Fonctions :
    Test-Gui                          -> $true si l'interface graphique est utilisable
    Show-MainMenu                     -> 'deploy' | 'capture' | $null (annule)
    Show-ImagePicker $items           -> index choisi (>=0) ou -1 ; $items = @(@{Label;Category}...)
    Show-CaptureDialog $default $model -> nom (string) ou $null (annule)
#>

$script:GuiOk = $false
try {
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
    Add-Type -AssemblyName System.Drawing -ErrorAction Stop
    [System.Windows.Forms.Application]::EnableVisualStyles()
    $script:GuiOk = $true
} catch { $script:GuiOk = $false }

function Test-Gui { return $script:GuiOk }

function New-Ec19Form($title, $w, $h) {
    $f = New-Object System.Windows.Forms.Form
    $f.Text = $title
    $f.Size = New-Object System.Drawing.Size($w, $h)
    $f.StartPosition = 'CenterScreen'
    $f.FormBorderStyle = 'FixedDialog'
    $f.MaximizeBox = $false
    $f.MinimizeBox = $false
    $f.BackColor = [System.Drawing.Color]::White
    $f.Font = New-Object System.Drawing.Font('Segoe UI', 11)
    return $f
}

function Add-Header($form, $text) {
    $h = New-Object System.Windows.Forms.Label
    $h.Text = $text
    $h.Font = New-Object System.Drawing.Font('Segoe UI', 15, [System.Drawing.FontStyle]::Bold)
    $h.ForeColor = [System.Drawing.Color]::FromArgb(0, 90, 158)
    $h.AutoSize = $false
    $h.TextAlign = 'MiddleCenter'
    $h.Dock = 'Top'
    $h.Height = 60
    $form.Controls.Add($h)
    return $h
}

function Show-MainMenu {
    if (-not $script:GuiOk) {
        Write-Host ''
        Write-Host '  [1] Installer Windows sur ce poste'
        Write-Host '  [2] Capturer une image de reference'
        $c = Read-Host 'Votre choix [1]'
        if ([string]::IsNullOrWhiteSpace($c)) { $c = '1' }
        if ($c.Trim() -eq '2') { return 'capture' } else { return 'deploy' }
    }
    try {
        $f = New-Ec19Form 'Deploiement eCollege19 - Atelier MARBOT' 560 380
        Add-Header $f 'Que voulez-vous faire ?' | Out-Null

        $btnDeploy = New-Object System.Windows.Forms.Button
        $btnDeploy.Text = "Installer Windows`nsur ce poste"
        $btnDeploy.Size = New-Object System.Drawing.Size(240, 130)
        $btnDeploy.Location = New-Object System.Drawing.Point(30, 100)
        $btnDeploy.Font = New-Object System.Drawing.Font('Segoe UI', 13, [System.Drawing.FontStyle]::Bold)
        $btnDeploy.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
        $btnDeploy.ForeColor = [System.Drawing.Color]::White
        $btnDeploy.FlatStyle = 'Flat'
        $btnDeploy.Add_Click({ $f.Tag = 'deploy'; $f.Close() })
        $f.Controls.Add($btnDeploy)

        $btnCapture = New-Object System.Windows.Forms.Button
        $btnCapture.Text = "Capturer une image`nde reference (avance)"
        $btnCapture.Size = New-Object System.Drawing.Size(240, 130)
        $btnCapture.Location = New-Object System.Drawing.Point(290, 100)
        $btnCapture.Font = New-Object System.Drawing.Font('Segoe UI', 13)
        $btnCapture.BackColor = [System.Drawing.Color]::FromArgb(230, 230, 230)
        $btnCapture.FlatStyle = 'Flat'
        $btnCapture.Add_Click({ $f.Tag = 'capture'; $f.Close() })
        $f.Controls.Add($btnCapture)

        $lblFoot = New-Object System.Windows.Forms.Label
        $lblFoot.Text = 'Installer = mettre Windows sur ce poste.  Capturer = creer une image modele (a faire apres sysprep).'
        $lblFoot.Location = New-Object System.Drawing.Point(30, 250)
        $lblFoot.Size = New-Object System.Drawing.Size(500, 60)
        $lblFoot.ForeColor = [System.Drawing.Color]::Gray
        $lblFoot.Font = New-Object System.Drawing.Font('Segoe UI', 9)
        $f.Controls.Add($lblFoot)

        $f.Tag = $null
        $f.ShowDialog() | Out-Null
        return $f.Tag
    } catch {
        Write-Host "Interface indisponible ($($_.Exception.Message)) -> mode texte." -ForegroundColor Yellow
        $script:GuiOk = $false
        return (Show-MainMenu)
    }
}

function Show-ImagePicker($items, $recIndex = -1) {
    # $items = tableau d'objets avec .Label et .Category ('Modele'|'Edition'). $recIndex = index
    # recommande pour ce poste (modele detecte) ou -1. Retourne l'index choisi ou -1.
    if (-not $script:GuiOk) {
        Write-Host ''
        for ($i=0; $i -lt $items.Count; $i++) {
            $mark = if ($i -eq $recIndex) { '   <-- recommande pour ce poste' } else { '' }
            Write-Host ("  [{0}] {1} ({2}){3}" -f $i, $items[$i].Label, $items[$i].Category, $mark)
        }
        $prompt = if ($recIndex -ge 0) { "Numero de l image a deployer [$recIndex]" } else { 'Numero de l image a deployer' }
        $sel = Read-Host $prompt
        if ([string]::IsNullOrWhiteSpace($sel) -and $recIndex -ge 0) { return $recIndex }
        if ($sel -match '^\d+$' -and [int]$sel -ge 0 -and [int]$sel -lt $items.Count) { return [int]$sel }
        return -1
    }
    try {
        $f = New-Ec19Form 'Installer Windows - choix de l image' 620 540
        Add-Header $f 'Choisissez l image a installer' | Out-Null
        if ($recIndex -ge 0 -and $recIndex -lt $items.Count) {
            $lblRec = New-Object System.Windows.Forms.Label
            $lblRec.Text = 'Recommande pour ce poste : ' + $items[$recIndex].Label
            $lblRec.Location = New-Object System.Drawing.Point(20, 62)
            $lblRec.Size = New-Object System.Drawing.Size(560, 22)
            $lblRec.ForeColor = [System.Drawing.Color]::FromArgb(21, 128, 61)
            $lblRec.Font = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)
            $f.Controls.Add($lblRec)
        }

        $lv = New-Object System.Windows.Forms.ListView
        $lv.Location = New-Object System.Drawing.Point(20, 90)
        $lv.Size = New-Object System.Drawing.Size(560, 285)
        $lv.View = 'Details'
        $lv.FullRowSelect = $true
        $lv.MultiSelect = $false
        $lv.HeaderStyle = 'Nonclickable'
        $lv.Font = New-Object System.Drawing.Font('Segoe UI', 11)
        $lv.Columns.Add('Image', 400) | Out-Null
        $lv.Columns.Add('Type', 140) | Out-Null
        $grpModele  = $lv.Groups.Add('m', 'Images par modele (recommande - a jour)')
        $grpEdition = $lv.Groups.Add('e', 'Installation complete (Windows nu)')
        for ($i=0; $i -lt $items.Count; $i++) {
            $it = New-Object System.Windows.Forms.ListViewItem($items[$i].Label)
            $it.SubItems.Add($(if ($items[$i].Category -eq 'Modele') {'Modele'} else {'Edition'})) | Out-Null
            $it.Group = $(if ($items[$i].Category -eq 'Modele') { $grpModele } else { $grpEdition })
            $it.Tag = $i
            $lv.Items.Add($it) | Out-Null
        }
        # Preselectionne l'image recommandee (modele detecte) si presente, sinon la premiere.
        $toSel = 0
        if ($recIndex -ge 0) { for ($k=0; $k -lt $lv.Items.Count; $k++) { if ([int]$lv.Items[$k].Tag -eq $recIndex) { $toSel = $k; break } } }
        if ($lv.Items.Count -gt 0) { $lv.Items[$toSel].Selected = $true; $lv.Items[$toSel].EnsureVisible() }
        $f.Controls.Add($lv)

        $chk = New-Object System.Windows.Forms.CheckBox
        $chk.Text = "Je confirme : ce poste va etre EFFACE et reinstalle"
        $chk.Location = New-Object System.Drawing.Point(20, 390)
        $chk.Size = New-Object System.Drawing.Size(560, 30)
        $chk.ForeColor = [System.Drawing.Color]::FromArgb(180, 0, 0)
        $f.Controls.Add($chk)

        $btnOk = New-Object System.Windows.Forms.Button
        $btnOk.Text = 'Installer'
        $btnOk.Size = New-Object System.Drawing.Size(150, 45)
        $btnOk.Location = New-Object System.Drawing.Point(300, 430)
        $btnOk.Font = New-Object System.Drawing.Font('Segoe UI', 12, [System.Drawing.FontStyle]::Bold)
        $btnOk.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
        $btnOk.ForeColor = [System.Drawing.Color]::White
        $btnOk.FlatStyle = 'Flat'
        $btnOk.Enabled = $false
        $btnOk.Add_Click({
            if ($lv.SelectedItems.Count -gt 0) { $f.Tag = [int]$lv.SelectedItems[0].Tag; $f.Close() }
        })
        $f.Controls.Add($btnOk)

        $chk.Add_CheckedChanged({ $btnOk.Enabled = $chk.Checked })

        $btnCancel = New-Object System.Windows.Forms.Button
        $btnCancel.Text = 'Annuler'
        $btnCancel.Size = New-Object System.Drawing.Size(120, 45)
        $btnCancel.Location = New-Object System.Drawing.Point(460, 430)
        $btnCancel.FlatStyle = 'Flat'
        $btnCancel.Add_Click({ $f.Tag = -1; $f.Close() })
        $f.Controls.Add($btnCancel)

        $f.Tag = -1
        $f.ShowDialog() | Out-Null
        return [int]$f.Tag
    } catch {
        Write-Host "Interface indisponible ($($_.Exception.Message)) -> mode texte." -ForegroundColor Yellow
        $script:GuiOk = $false
        return (Show-ImagePicker $items)
    }
}

function Show-CaptureDialog($default, $model) {
    if (-not $script:GuiOk) {
        if ($model) { Write-Host "Modele detecte : $model" -ForegroundColor Green }
        $n = Read-Host "Nom de l'image [$default]"
        if ([string]::IsNullOrWhiteSpace($n)) { return $default }
        return $n
    }
    try {
        $f = New-Ec19Form 'Capturer une image de reference' 540 320
        Add-Header $f 'Capturer une image' | Out-Null

        $lbl = New-Object System.Windows.Forms.Label
        $lbl.Text = $(if ($model) { "Modele detecte : $model" } else { 'Modele non detecte' })
        $lbl.Location = New-Object System.Drawing.Point(30, 80)
        $lbl.Size = New-Object System.Drawing.Size(470, 30)
        $f.Controls.Add($lbl)

        $lbl2 = New-Object System.Windows.Forms.Label
        $lbl2.Text = 'Nom de l image (gardez le nom du modele pour mettre a jour) :'
        $lbl2.Location = New-Object System.Drawing.Point(30, 120)
        $lbl2.Size = New-Object System.Drawing.Size(470, 25)
        $f.Controls.Add($lbl2)

        $txt = New-Object System.Windows.Forms.TextBox
        $txt.Text = $default
        $txt.Location = New-Object System.Drawing.Point(30, 150)
        $txt.Size = New-Object System.Drawing.Size(470, 30)
        $txt.Font = New-Object System.Drawing.Font('Segoe UI', 12)
        $f.Controls.Add($txt)

        $btnOk = New-Object System.Windows.Forms.Button
        $btnOk.Text = 'Capturer'
        $btnOk.Size = New-Object System.Drawing.Size(150, 45)
        $btnOk.Location = New-Object System.Drawing.Point(220, 210)
        $btnOk.Font = New-Object System.Drawing.Font('Segoe UI', 12, [System.Drawing.FontStyle]::Bold)
        $btnOk.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
        $btnOk.ForeColor = [System.Drawing.Color]::White
        $btnOk.FlatStyle = 'Flat'
        $btnOk.Add_Click({ $f.Tag = $txt.Text; $f.Close() })
        $f.Controls.Add($btnOk)

        $btnCancel = New-Object System.Windows.Forms.Button
        $btnCancel.Text = 'Annuler'
        $btnCancel.Size = New-Object System.Drawing.Size(120, 45)
        $btnCancel.Location = New-Object System.Drawing.Point(380, 210)
        $btnCancel.FlatStyle = 'Flat'
        $btnCancel.Add_Click({ $f.Tag = $null; $f.Close() })
        $f.Controls.Add($btnCancel)

        $f.Tag = $null
        $f.ShowDialog() | Out-Null
        return $f.Tag
    } catch {
        Write-Host "Interface indisponible ($($_.Exception.Message)) -> mode texte." -ForegroundColor Yellow
        $script:GuiOk = $false
        return (Show-CaptureDialog $default $model)
    }
}
