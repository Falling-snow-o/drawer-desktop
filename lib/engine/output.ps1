# engine/output.ps1 — 由 box.ps1 dot-source 加载

function Write-Head($m) {
    Write-Host ""
    Write-Host ("{0}boxrun{1} · {2}" -f $Fw.Bold, $Fw.Reset, $m)
    Write-Host ("-" * 46)
    Write-Host ""
}

function Write-Step($m) { Write-Host ("{0}▸{1} {2}" -f $Fw.Cyan,   $Fw.Reset, $m) }

function Write-Ok  ($m) { Write-Host ("  {0}✓{1} {2}" -f $Fw.Green,  $Fw.Reset, $m) }

function Write-Warn($m) { Write-Host ("  {0}!{1} {2}" -f $Fw.Yellow, $Fw.Reset, $m) }

function Write-Bad ($m) { Write-Host ("  {0}✗{1} {2}" -f $Fw.Red,    $Fw.Reset, $m) }

function Write-Dim ($m) { Write-Host ("    {0}{1}{2}"     -f $Fw.Gray,   $m, $Fw.Reset) }
