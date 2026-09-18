#Requires -Version 5.1
function New-WuaCallback {
    if(-not('SqlExpressWindowsPatch.WuaCallback'-as[type])){
        Add-Type -TypeDefinition @'
using System.Runtime.InteropServices;
namespace SqlExpressWindowsPatch {
 [ComVisible(true), ClassInterface(ClassInterfaceType.AutoDispatch)]
 public class WuaCallback {
  [DispId(0)] public void Invoke(object job, object args) { }
 }
}
'@
    }
    New-Object SqlExpressWindowsPatch.WuaCallback
}
function Get-UpdateExclusion {
    param($Update)
    if([int]$Update.Type-ne1){return 'Driver'}
    if($Update.BrowseOnly){return 'Optional update'}
    if($Update.Title-match'(?i)preview'){return 'Preview update'}
    if($Update.Title-match'(?i)SQL Server'-or@($Update.Categories|Where-Object{$_.Name-match'(?i)SQL Server'}).Count){return 'SQL update: use the SQL phase'}
    if(@($Update.Categories|Where-Object{$_.CategoryID-eq'3689BDC8-B205-4AF4-8D4A-A63924C5E9D5'}).Count){return 'OS feature upgrade'}
    if($Update.InstallationBehavior.CanRequestUserInput){return 'Requires interactive input'}
    ''
}
function Wait-WuaJob {
    param($Job,[string]$Action,$Updates)
    $timer=[Diagnostics.Stopwatch]::StartNew()
    while(-not$Job.IsCompleted){
        $percent=''
        if($Action-ne'Scanning'){
            try{
                $progress=$Job.GetProgress();$percent=' '+$progress.PercentComplete+'%'
                if($Updates-and$progress.CurrentUpdateIndex-ge0-and$progress.CurrentUpdateIndex-lt$Updates.Count){$percent+=' ['+$Updates.Item($progress.CurrentUpdateIndex).Title+']'}
            }catch{}
        }
        Write-Host ("Windows Update: {0}{1}; elapsed {2:n0}s. Do not close this window."-f$Action,$percent,$timer.Elapsed.TotalSeconds)
        Start-Sleep -Seconds 5
    }
}
function Get-WindowsUpdateScan {
    $session=New-Object -ComObject Microsoft.Update.Session
    $session.ClientApplicationID='SqlExpressWindowsPatch'
    $searcher=$session.CreateUpdateSearcher()
    # ssDefault preserves the machine's Windows Update/WSUS configuration.
    $callback=New-WuaCallback
    $job=$searcher.BeginSearch("IsInstalled=0 and IsHidden=0 and Type='Software'",$callback,0)
    Wait-WuaJob $job Scanning
    $result=$searcher.EndSearch($job)
    if([int]$result.ResultCode-ne2){throw "Windows Update scan was not fully successful: $($result.ResultCode)"}
    $updates=New-Object -ComObject Microsoft.Update.UpdateColl
    $excluded=@()
    foreach($update in $result.Updates){
        $reason=Get-UpdateExclusion $update
        if($reason){$excluded+=[pscustomobject]@{Title=$update.Title;Reason=$reason}}
        else{[void]$updates.Add($update)}
    }
    $exclusive=@($updates|Where-Object{$_.InstallationBehavior.Impact-eq2})
    if($exclusive.Count-and$updates.Count-gt1){
        $chosen=$exclusive[0]
        foreach($item in $updates){if($item.Identity.UpdateID-ne$chosen.Identity.UpdateID){$excluded+=[pscustomobject]@{Title=$item.Title;Reason='Deferred: another update requires exclusive installation; rescan afterwards'}}}
        $updates=New-Object -ComObject Microsoft.Update.UpdateColl
        [void]$updates.Add($chosen)
    }
    [pscustomobject]@{Session=$session;Updates=$updates;Excluded=$excluded}
}
function Show-WindowsUpdateScan {
    param($Scan)
    for($i=0;$i-lt$Scan.Updates.Count;$i++){
        $u=$Scan.Updates.Item($i)
        Write-Host ("{0}. {1} | KB {2} | maximum download {3:n0} MiB | restart behavior {4}"-f($i+1),$u.Title,(@($u.KBArticleIDs)-join','),($u.MaxDownloadSize/1MB),$u.InstallationBehavior.RebootBehavior)
    }
    foreach($item in $Scan.Excluded){Write-Host "Excluded: $($item.Title) ($($item.Reason))" -ForegroundColor Yellow}
    Write-Host "Eligible software updates: $($Scan.Updates.Count). Source: existing Windows Update/WSUS configuration."
}
function Install-WindowsUpdateBatch {
    param($Scan,$State)
    if(-not$Scan.Updates.Count){return $false}
    $installer=$Scan.Session.CreateUpdateInstaller()
    if($installer.IsBusy){throw 'Another Windows Update installation is active.'}
    if($installer.RebootRequiredBeforeInstallation){throw 'Windows requires a restart before installation.'}
    $needed=5GB
    foreach($u in $Scan.Updates){if(-not$u.IsDownloaded){$needed+=[long]$u.MaxDownloadSize}}
    $free=[long](Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$env:SystemDrive'").FreeSpace
    if($free-lt$needed){throw ('Not enough free system-drive space: {0:n1} GiB available, {1:n1} GiB conservative minimum. No automatic cleanup.'-f($free/1GB),($needed/1GB))}
    $State.Updates=@(foreach($u in $Scan.Updates){[pscustomobject]@{Id=$u.Identity.UpdateID;Revision=$u.Identity.RevisionNumber;Title=$u.Title;Result='Pending';HResult=0;Reboot=$false}})
    $State.Stage='DownloadingWindows';Save-PatchState $State
    foreach($u in $Scan.Updates){if(-not$u.EulaAccepted){$u.AcceptEula()}}
    $downloader=$Scan.Session.CreateUpdateDownloader();$downloader.Updates=$Scan.Updates
    $callback=New-WuaCallback
    $job=$downloader.BeginDownload($callback,$callback,0);Wait-WuaJob $job Downloading $Scan.Updates
    $download=$downloader.EndDownload($job)
    if([int]$download.ResultCode-ne2){throw "Windows Update download failed or was partial: $($download.ResultCode)"}
    foreach($u in $Scan.Updates){if(-not$u.IsDownloaded){throw "Not downloaded: $($u.Title)"}}
    $installer.Updates=$Scan.Updates;$installer.ForceQuiet=$true;$installer.AllowSourcePrompts=$false
    $State.Stage='InstallingWindows';Save-PatchState $State
    $job=$installer.BeginInstall($callback,$callback,0);Wait-WuaJob $job Installing $Scan.Updates
    $result=$installer.EndInstall($job)
    $failed=$false
    for($i=0;$i-lt$Scan.Updates.Count;$i++){
        $item=$result.GetUpdateResult($i)
        $State.Updates[$i].Result=[string][int]$item.ResultCode
        $State.Updates[$i].HResult=[long]$item.HResult
        $State.Updates[$i].Reboot=[bool]$item.RebootRequired
        Write-Host ("Windows result: {0} | code {1} | HRESULT {2}"-f$State.Updates[$i].Title,$item.ResultCode,$item.HResult)
        if([int]$item.ResultCode-ne2){$failed=$true}
    }
    $State.WindowsHistory+=@($State.Updates)
    if($failed-or[int]$result.ResultCode-ne2){$State.Stage='WindowsFailed';Save-PatchState $State;throw 'Some Windows updates failed. SQL phase was not started. Review results before retrying.'}
    $State.RestartRequired=[bool]$result.RebootRequired
    $State.Stage='WindowsScan';Save-PatchState $State
    return [bool]$result.RebootRequired
}
