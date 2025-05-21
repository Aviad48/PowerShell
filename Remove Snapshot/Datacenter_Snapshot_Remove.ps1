
# === PARAMS ===
param (
    [string]$vCenter,
    [string]$Username,
    [string]$Password
)



# === CONFIG ===
$logPath = "C:\Logs\Remove Snapshot\vcenter_snapshot_cleanup_$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').log"
$elasticHost = "elastik URI"
$Datastream = "DataStream Name "
$ApiKey = "API KEY"
$SnapshotsToDeleteBatch = @()
$BatchLimit = 5
$TotalDeletedSnapshots = 0
$TotalDeletedSizeGB = 0


function Write-Log {
    param(
        [string]$message,
        [string]$level = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$level] $message"
    $logEntry | Out-File -FilePath $logPath -Append -Encoding utf8

    switch ($level.ToUpper()) {
        "ERROR"   { Write-Host $logEntry -ForegroundColor Red }
        "WARNING" { Write-Host $logEntry -ForegroundColor Yellow }
        "INFO"    { Write-Host $logEntry -ForegroundColor Gray }
        "SECTION" { Write-Host $logEntry -ForegroundColor Cyan }
        default   { Write-Host $logEntry }
    }
}

function Get-ElasticStorageStats {
    param (
        [string]$ElasticHost,
        [string]$Datastream,
        [string]$ApiKey
    )

    function Convert-Size {
        param ([double]$Bytes)
        $TB = [math]::Round($Bytes / 1TB, 2)
        $GB = [math]::Round($Bytes / 1GB, 2)
        if ($TB -lt 1) { return "$GB GB" }
        else { return "$TB TB" }
    }

    $headers = @{
        "Authorization" = "ApiKey $ApiKey"
        "Content-Type"  = "application/json"
    }

    #  Latest logical volume stats
    $volumeQuery = @'
{
  "size": 1000,
  "_source": [
    "storage.name", "storage.type", "storage.ip", "volume.name",
    "logical_used", "logical_free", "logical_provisioned",
    "used_prcnt", "@timestamp"
  ],
  "query": {
    "exists": { "field": "volume.name" }
  },
  "sort": [{ "@timestamp": { "order": "desc" } }]
}
'@

    $volumeResponse = Invoke-RestMethod -Uri "$ElasticHost/$Datastream/_search" -Headers $headers -Method POST -Body $volumeQuery

    $seenVolumes = @{}
    $storages = @{}

    foreach ($hit in $volumeResponse.hits.hits) {
        $src = $hit._source
        $volName = $src.volume.name
        if (-not $volName -or $seenVolumes.ContainsKey($volName)) { continue }
        $seenVolumes[$volName] = $true

        $storageName = $src.storage.name
        if (-not $storages.ContainsKey($storageName)) {
            $storages[$storageName] = [PSCustomObject]@{
                Name                    = $storageName
                Type                    = $src.storage.type
                IP                      = $src.storage.ip
                Volumes                 = @()
                LogicalFreeBytes        = 0
                LogicalUsedBytes        = 0
                LogicalProvisionedBytes = 0
                PhysicalFreeBytes       = 0
                PhysicalUsedBytes       = 0
                PhysicalTotalBytes      = 0
            }
        }

        $storage = $storages[$storageName]
        $storage.Volumes += $volName

        if ($src.logical_free) { $storage.LogicalFreeBytes += $src.logical_free }
        if ($src.logical_used) { $storage.LogicalUsedBytes += $src.logical_used }
        if ($src.logical_provisioned) { $storage.LogicalProvisionedBytes += $src.logical_provisioned }
    }

    #  Add physical stats
    $physicalQuery = @'
{
  "size": 1000,
  "_source": [
    "storage.name", "storage.ip",
    "physical_total", "physical_used", "physical_free", "@timestamp"
  ],
  "query": {
    "bool": {
      "must": [
        { "exists": { "field": "storage.name" } },
        { "exists": { "field": "physical_total" } }
      ]
    }
  },
  "sort": [{ "@timestamp": { "order": "desc" } }]
}
'@

    $physicalResponse = Invoke-RestMethod -Uri "$ElasticHost/$Datastream/_search" -Headers $headers -Method POST -Body $physicalQuery
    $seenStoragePhys = @{}

    foreach ($hit in $physicalResponse.hits.hits) {
        $src = $hit._source
        $storageName = $src.storage.name
        if (-not $storageName -or $seenStoragePhys.ContainsKey($storageName)) { continue }
        $seenStoragePhys[$storageName] = $true

        if (-not $storages.ContainsKey($storageName)) {
            $storages[$storageName] = [PSCustomObject]@{
                Name                    = $storageName
                Type                    = ""
                IP                      = $src.storage.ip
                Volumes                 = @()
                LogicalFreeBytes        = 0
                LogicalUsedBytes        = 0
                LogicalProvisionedBytes = 0
                PhysicalFreeBytes       = 0
                PhysicalUsedBytes       = 0
                PhysicalTotalBytes      = 0
            }
        }

        $storage = $storages[$storageName]
        if ($src.physical_free) { $storage.PhysicalFreeBytes = $src.physical_free }
        if ($src.physical_used) { $storage.PhysicalUsedBytes = $src.physical_used }
        if ($src.physical_total) { $storage.PhysicalTotalBytes = $src.physical_total }
    }

    # Finalize and format output
    $results = @()

  
    foreach ($storage in $storages.Values) {
        $physFree = $storage.PhysicalFreeBytes
        $physUsed = $storage.PhysicalUsedBytes
        $physTotal = $storage.PhysicalTotalBytes

        $usedPercent = if (($physUsed + $physFree) -ne 0) {
            [math]::Round(($physUsed / ($physUsed + $physFree)) * 100, 2)
        }
        else {
            0
        }

        $logicalUsedPercent = if ($storage.LogicalProvisionedBytes -ne 0) {
            [math]::Round(($storage.LogicalUsedBytes / $storage.LogicalProvisionedBytes) * 100, 2)
        }
        else {
            0
        }

        $results += [PSCustomObject]@{
            Name                = $storage.Name
            Type                = $storage.Type
            IP                  = $storage.IP
            Volumes             = ($storage.Volumes | ForEach-Object { "• $_" }) -join "`n"
            LogicalFree         = Convert-Size $storage.LogicalFreeBytes
            LogicalUsed         = Convert-Size $storage.LogicalUsedBytes
            LogicalProvisioned  = Convert-Size $storage.LogicalProvisionedBytes
            LogicalUsedPercent  = "$logicalUsedPercent%"
            PhysicalFree        = Convert-Size $physFree
            PhysicalUsed        = Convert-Size $physUsed
            PhysicalTotal       = Convert-Size $physTotal
            PhysicalUsedPercent = "$usedPercent%"
        }
    }

    return $results

}




Write-Log "=== Snapshot Cleanup Script Started ==="

# === CONNECT TO VCENTER ===
$VCenter = Connect-VIServer -Server $vCenter -User $Username -Password $Password -WarningAction SilentlyContinue | Out-Null
Write-Log "Connected to vCenter."

# === COLLECT ALL CLUSTERS ===
$snapshotGroups = @()
$clusters = Get-Cluster   
$snapshots = @()
foreach ($cluster in $clusters) {
    Write-Log "Processing cluster: $($cluster.Name)" -level "SECTION"

    $vms = Get-VM -Location $cluster 
    Write-Log "Found $($vms.Count) VMs in cluster '$($cluster.Name)'" -level INFO

    $vms = Get-VM -Location $cluster -ErrorAction SilentlyContinue
    if (-not $vms -or $vms.Count -eq 0) {
        Write-Log "SKIPPED: No VMs found in cluster '$($cluster.Name)'" -level WARNING
        continue
    }

    Write-Log "Found $($vms.Count) VMs in cluster '$($cluster.Name)'" -level INFO

    $snapshots = Get-Snapshot -VM $vms -WarningAction SilentlyContinue

    if ($snapshots.Count -eq 0) {
        Write-Log "No snapshots found in cluster '$($cluster.Name)'" -level "INFO"
        continue
    } else {
        Write-Log "Found $($snapshots.Count) snapshots in cluster '$($cluster.Name)'"
    }
    $DatastoreInfonList = @()
    $DeletionCount = 0
    $elasticStats = Get-ElasticStorageStats -ElasticHost $elasticHost -Datastream $Datastream -ApiKey $ApiKey 
    foreach ($snapshot in $snapshots) {
        try {
            Start-Sleep 3
            $vm = $snapshot.VM
            $vmView = Get-View -Id $vm.Id

            # === SNAPSHOT FILES ===
            $snapshotFiles = $vmView.LayoutEx.File | Where-Object {
                $_.Name -match "\.vmsn$|\.delta\.vmdk$"
            }

            if (-not $snapshotFiles) {
                Write-Log "WARNING: No snapshot files found for '$($snapshot.Name)' on VM '$($vm.Name)'" -level "WARNING"
                continue
            }


        
            # === PARSE DATASTORE FROM FILE PATH ===
            $match = [regex]::Match($snapshotFiles[0].Name, '^\[(.*?)\]')
            if ($match.Success) {
                $dsName = $match.Groups[1].Value
            } else {
                Write-Log "ERROR: Failed to extract datastore name from snapshot path '$($snapshotFiles[0].Name)'" -level "ERROR"
                continue
            }

            # === GET DATASTORE INFO IN VC ===
            $dsObj = Get-Datastore | Where-Object { $_.Name -eq $dsName }

            if (-not $dsObj) {
                Write-Log "ERROR: Datastore '$dsName' not found in Get-Datastore" -level "ERROR"
                continue
            }

            
            
            # Convert to TB and GB
            $freeTB = [math]::Round($dsObj.FreeSpaceGB / 1024, 2)
            $capacityTB = [math]::Round($dsObj.CapacityGB / 1024, 2)
            $usedGB = $dsObj.CapacityGB - $dsObj.FreeSpaceGB
            $usedTB = [math]::Round($usedGB / 1024, 2)

            if ($capacityTB -lt 1) {
                $freeDisplay = "$([math]::Round($dsObj.FreeSpaceGB, 2)) GB"
                $usedDisplay = "$([math]::Round($usedGB, 2)) GB"
            }
            else {
                $freeDisplay = "$freeTB TB"
                $usedDisplay = "$usedTB TB"
            }

            $percentFree = [math]::Round(($dsObj.FreeSpaceGB / $dsObj.CapacityGB) * 100, 2)
            Write-Log "Snapshot '$($snapshot.Name)' on VM '$($vm.Name)' is on datastore '$dsName' | Free: $freeDisplay / $capacityDisplay ($percentFree%)"

            $DatastoreInfo = [PSCustomObject]@{
                Snapshot    = $snapshot.Name
                VM          = $vm.Name
                Datastore   = $dsObj.Name
                FreeSpace   = $freeDisplay
                UsedSpace   = $usedDisplay
                PercentFree = "$percentFree%"
            }
            $DatastoreInfonList += $DatastoreInfo   

        } 
        catch{
            #Write-Log "ERROR deleting snapshot '$($snapshot.Name)' on VM '$($vm.Name)': $_" -level "ERROR"
             }

         # === MAP DATASTORE TO ELASTIC VOLUME & STORAGE ===

        $matchedElasticStorage = $elasticStats | Where-Object { $_.Volumes -like "*• $dsName*" }

        if (-not $matchedElasticStorage) {
            Write-Log "WARNING: Datastore '$dsName' not found in Elastic volumes, Probebly a local Datastpre. Snapshot '$($snapshot.Name)'." -level "WARNING"
            if ($dsObj) {
                $capacityGB = [math]::Round($dsObj.CapacityGB, 2)
                $freeGB = [math]::Round($dsObj.FreeSpaceGB, 2)
                $usedGB = [math]::Round($capacityGB - $freeGB, 2)
                $percentFree = [math]::Round(($freeGB / $capacityGB) * 100, 2)
                $capacityTB = [math]::Round($capacityGB / 1024, 2)
                $freeTB = [math]::Round($freeGB / 1024, 2)
                $usedTB = [math]::Round($usedGB / 1024, 2)

                $matchedElasticStorage = [PSCustomObject]@{
                    Name         = "$dsName (local)"
                    Type         = "local"
                    IP           = ""
                    PhysicalFree = $freeTB
                  
                }
                Write-Log "Datastore '$dsName' is a local datastore. Using local free space ($freeTB TB) for evaluation." -level INFO

            }
        }
        else {
            
         Write-Log "Datastore '$dsName' maps to Elastic Storage '$($matchedElasticStorage.Name)' (Type: $($matchedElasticStorage.Type), IP: $($matchedElasticStorage.IP))"
            
        }
    
        
        Write-Log "===Checking Snapshot $($snapshot.Name) Size====" -level INFO 
         #$SnapShotSizeDisplay = Get-VM -Name $vm  | Sort | Get-Snapshot | Select-Object @{n = "VCenter"; e = { $VCenter } }, VM, @{n = "SnapshotState"; e = { $_.PowerState } }, Name, Description, @{Name = "SizeGB"; Expression = { [math]::Round($_.SizeGB, 2) } }, Created, @{Name = "DaysOld"; Expression = { (New-TimeSpan -End (Get-Date) -Start $_.Created).Days } }
         # === VM NAME CHECK CONDITION ===
        if ($vm.Name -notmatch 'Alcon|AW') {
            Write-Log "SKIPPED: VM '$($vm.Name)' is not eligible, VM is not Alcon or AW." -level WARNING
            continue
        }
          # === SAFETY CHECK BEFORE DELETION === 
          Write-Log " === Starting Safety Check Before Delete === " -level SECTION 
         $SnapshotDaysOld = (New-TimeSpan -End (Get-Date) -Start $snapshot.Created).Days
         $SnapshotSizGB = [math]::Round($snapshot.SizeGB, 2)
         Write-Log "Snapshot '$($snapshot.Name)' size is $SnapshotSizGB GB "
         $PhysicalFree = $matchedElasticStorage.PhysicalFree 
         $DsFree = $freeDisplay
         $Max_Limit = 10 #max threshold in TB to keep in storage and not remove a snapshot if the size will be below  
         $Max_Day = 1 #max day to keep snapshot
         $PhysicalFreeTB = [double]($PhysicalFree -replace '[^\d.]', '')
         $SnapshotSizeTB = [math]::Round($SnapshotSizGB / 1024, 4)
       

        if ($SnapshotDaysOld -gt $Max_Day) {
            $ProjectedFree = $PhysicalFreeTB - $SnapshotSizeTB

            if ($matchedElasticStorage.Type -ne "local") {
                if ($SnapshotSizeTB -gt ($PhysicalFreeTB - $Max_Limit)) {
                    Write-Log "SKIPPED: Deleting snapshot '$($snapshot.Name)' would drop storage below safety limit ($Max_Limit TB). Current: $PhysicalFreeTB TB, Needed: $SnapshotSizeTB TB" -level WARNING
                    continue
                }
            }
            else {
                
            
            # === Delete Snapshot  === 
                Write-Log "Snapshot '$($snapshot.Name)' is eligible for deletion. Age: $SnapshotDaysOld days, Size: $SnapshotSizeTB TB, Free After Delete: $ProjectedFree TB" -level INFO
                
                try {

                    Write-Log "Deleting snapshot '$($snapshot.Name)' on VM '$($vm.Name)'... waiting for completion." -level INFO
                    Remove-Snapshot -Snapshot $snapshot -Confirm:$false -RunAsync:$false -ErrorAction Stop
                    Start-Sleep -Seconds 3
                    Write-Log "Deleted snapshot '$($snapshot.Name)' on VM '$($vm.Name)'" -level INFO
                    $TotalDeletedSnapshots++
                    $TotalDeletedSizeGB += $SnapshotSizGB

                    $DeletionCount++

                    if ($DeletionCount -ge 10) {
                        Write-Log "=== Re-fetching Elastic storage stats after $DeletionCount deletions ===" -level SECTION
                        $elasticStats = Get-ElasticStorageStats -ElasticHost $elasticHost -Datastream $Datastream -ApiKey $ApiKey
                        $DeletionCount = 0
                    }

                }
                catch {
                Write-Log "ERROR deleting snapshot '$($snapshot.Name)' on VM '$($vm.Name)': $_" -level ERROR
                }
            }
        }
        else {
            Write-Log "SKIPPED: Snapshot '$($snapshot.Name)' is only $SnapshotDaysOld days old. Minimum age required is $Max_Day days." -level WARNING
        }

     }
    
}


$TotalDeletedSizeTB = [math]::Round($TotalDeletedSizeGB / 1024, 2)

$reportHtml = @"
<html>
<head>
<style>
    body { font-family: Segoe UI, sans-serif; color: #333; }
    h2 { color: #2c3e50; }
    table { border-collapse: collapse; width: 600px; }
    th, td { border: 1px solid #dddddd; padding: 10px; text-align: left; }
    th { background-color: #f2f2f2; }
</style>
</head>
<body>
<h2>vCenter Snapshot Cleanup Summary</h2>
<table>
  <tr><th>Metric</th><th>Value</th></tr>
  <tr><td>Total Snapshots Deleted</td><td>$TotalDeletedSnapshots</td></tr>
  <tr><td>Total Space Freed (GB)</td><td>$TotalDeletedSizeGB</td></tr>
  <tr><td>vCenter</td><td>$VCenter</td></tr>
  <tr><td>Completion Date</td><td>$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</td></tr>
  <tr><td>Log File Path</td><td>$logPath</td></tr>
</table>
</body>
</html>
"@

# === Send Email Report ===
$MailParams = @{
    From       = "<From>"
    To         = "<TO>"
    Subject    = "vCenter Snapshot Cleanup Report - $(Get-Date -Format 'yyyy-MM-dd')"
    Body       = $reportHtml
    BodyAsHtml = $true
    SmtpServer  = "SMTP sERVER"
    Attachments = $logPath  
}

Send-MailMessage @MailParams
Write-Log "HTML Report sent via email." -level INFO



Write-Log "Mail report sent. Summary: $TotalDeletedSnapshots snapshots deleted, $TotalDeletedSizeTB TB freed."

# === DISCONNECT FROM VCENTER ===
Disconnect-VIServer -Confirm:$false
Write-Log "Disconnected from vCenter."
Write-Log "=== Snapshot Cleanup Script Completed ==="
Write-Log "Log saved to: $logPath"



