param(
  [Parameter(Mandatory=$true)][string]$VMName
)

# Make sure PowerCLI is loaded (no-op if it's already imported)
if (-not (Get-Module VMware.VimAutomation.Core -ListAvailable)) {
  throw "VMware PowerCLI not installed. Install-Module VMware.PowerCLI"
}
Import-Module VMware.VimAutomation.Core -ErrorAction Stop | Out-Null

$vm = Get-VM -Name $VMName -ErrorAction Stop
$cluster = Get-Cluster -VM $vm -ErrorAction Stop
$cfg = $cluster.ExtensionData.ConfigurationEx
if (-not $cfg) { throw "Cluster '$($cluster.Name)' has no DRS configuration." }

$vmMoRef = $vm.ExtensionData.MoRef

# VM groups in cluster and the ones that include our VM
$vmGroups = @($cfg.Group | Where-Object { $_.GetType().Name -eq 'ClusterVmGroup' })
$myVmGroups = $vmGroups | Where-Object { $_.Vm -and ($_.Vm -contains $vmMoRef) }

$matches = foreach ($rule in @($cfg.Rule)) {
  $ruleTypeName = $rule.GetType().Name

  switch ($ruleTypeName) {
    'ClusterVmHostRuleInfo' {
      if ($rule.VmGroupName -and ($myVmGroups.Name -contains $rule.VmGroupName)) {
        [pscustomobject]@{
          VM       = $vm.Name
          Cluster  = $cluster.Name
          RuleName = $rule.Name
          RuleType = 'VM-Host'
          Enabled  = [bool]$rule.Enabled
        }
      }
    }
    'ClusterVmVmRuleInfo' {
      if ($rule.Vm -and ($rule.Vm -contains $vmMoRef)) {
        [pscustomobject]@{
          VM       = $vm.Name
          Cluster  = $cluster.Name
          RuleName = $rule.Name
          RuleType = if ($rule.Affine) { 'VM-VM Affinity' } else { 'VM-VM Anti-Affinity' }
          Enabled  = [bool]$rule.Enabled
        }
      }
    }
  }
}

if (-not $matches) {
  Write-Host "No DRS rules reference VM '$($vm.Name)' in cluster '$($cluster.Name)'." -ForegroundColor Green
} else {
  $matches | Sort-Object RuleType, RuleName | Format-Table RuleName, RuleType, Enabled -Auto
}

# Also return them if you want to pipe/export
$matches
