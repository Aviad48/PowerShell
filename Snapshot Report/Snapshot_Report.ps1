param (
    [string]$vCenter,
    [string]$Username,
    [string]$Password
)

# === CONNECT TO VCENTER ===
Connect-VIServer -Server $vCenter -User $Username -Password $Password | Out-Null
Write-Host "Connected to vCenter: $vCenter" -ForegroundColor Green

# === INIT REPORT LIST ===
$snapshotReport = @()

# === COLLECT SNAPSHOTS ===
$datacenters = Get-Datacenter

foreach ($dc in $datacenters) {
    $clusters = Get-Cluster -Location $dc

    foreach ($cluster in $clusters) {
        $vms = Get-VM -Location $cluster

        foreach ($vm in $vms) {
            $snapshots = Get-Snapshot -VM $vm -ErrorAction SilentlyContinue
            foreach ($snap in $snapshots) {
                $esxiHost = ($vm | Get-VMHost).Name
                $snapshotReport += [PSCustomObject]@{
                    Datacenter   = $dc.Name
                    Cluster      = $cluster.Name
                    ESXiHost     = $esxiHost
                    VMName       = $vm.Name
                    SnapshotName = $snap.Name
                    Description  = $snap.Description
                    SizeGB       = [math]::Round($snap.SizeGB, 2)
                    Created      = $snap.Created
                    AgeInDays    = (New-TimeSpan -Start $snap.Created -End (Get-Date)).Days
                }
            }
        }
    }
}

# === EXPORT TO CSV ===
$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$reportPath = "C:\jenkins\workspace\VMware_Automation\snapshot_report\vcenter_snapshot_report_$timestamp.csv"
$snapshotReport | Export-Csv -Path $reportPath -NoTypeInformation -Encoding UTF8

Write-Host "`nSnapshot report exported to: $reportPath" -ForegroundColor Cyan

# === BUILD HTML SUMMARY ===
$totalSnapshots = $snapshotReport.Count
$totalSize = ($snapshotReport | Measure-Object -Property SizeGB -Sum).Sum
$summaryHtml = @"
<html>
<head>
<style>
  body { font-family: Arial; }
  table { border-collapse: collapse; width: 50%; }
  th, td { border: 1px solid #ddd; padding: 8px; }
  th { background-color: #f2f2f2; }
</style>
</head>
<body>
  <h2>vCenter Snapshot Summary Report</h2>
  <table>
    <tr><th>Metric</th><th>Value</th></tr>
    <tr><td>Total Snapshots</td><td>$totalSnapshots</td></tr>
    <tr><td>Total Snapshot Size (GB)</td><td>$([math]::Round($totalSize, 2))</td></tr>
    <tr><tdvCenter</td><td>$vCenter</td></tr>
    <tr><td>Generated</td><td>$(Get-Date -Format "yyyy-MM-dd HH:mm:ss")</td></tr>
  </table>
</body>
</html>
"@

# === SEND EMAIL ===
$MailParams = @{
    From        = "<From Address>"
    To          = "<To Address>"
    Subject     = "vCenter Snapshot Report - $(Get-Date -Format 'yyyy-MM-dd')"
    Body        = $summaryHtml
    BodyAsHtml  = $true
    SmtpServer  = "SMTP SERVER"
    Attachments = $reportPath
}
Send-MailMessage @MailParams

Write-Host "`nEmail report sent successfully." -ForegroundColor Green

# === DISCONNECT ===
Disconnect-VIServer -Confirm:$false
Write-Host "Disconnected from vCenter." -ForegroundColor Yellow

