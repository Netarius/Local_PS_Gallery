$ver="0.2"
$ProgrammName="sync_psgallery"
$ScriptPatch = ($MyInvocation.MyCommand.Definition).Replace(($MyInvocation.MyCommand.Name), "")
#tech specific stuff
$pathtomodules = $ScriptPatch+'modules\'
$serverdb = "db.local"
$userdb = "svc_posh"
$passdb = 'Pa$$w0rd'
$database = "repo_base"
$email = "Oleg.Gordeev@local"
$subjectfail = "sync_psgallery error"
$subjectcomplete = "sync_psgallery report"

try
{
    $ScriptPatch+"set-functions.ps1"
    $global:logfilename = $ScriptPatch+"log`\" + $ProgrammName + ".log"
	write-log "$ProgrammName (ver $ver) started."
}
catch {		
	return "Error loading functions Set-Functions.ps1"
}

$modulepsgallery=@()
try {
    $modulepsgallery += Find-Module * -Repository PSGallery -ErrorAction Stop | select Name, version
    write-log 'connect to psgallery completed successfully.'{completed}
}
catch {
    $body = "Can't connect to psgallery"
	FuncMail $body $subjectfail $email
    return write-log "can't connect to psgallery."{warning}
}

try {
    $connection.open()
    write-log "successfully connected to the database."{completed}
}
catch [System.Management.Automation.MethodInvocationException] {
    $body = "can't connect to DB"
	FuncMail $body $subjectfail $email
    return write-log "can't connect to DB."{warning}
}

$sql_q = "SELECT COUNT(*) AS recordscount FROM temp_modules;"
$recordscount = sql_query $sql_q $connection "temp_modules"

if ($recordscount.recordscount -gt "0") {
    $body = "temp_modules table is not empty"
	FuncMail $body $subjectfail $email
    return write-log "temp_modules table is not empty"{warning}
}
else {
    foreach ($_ in $modulepsgallery){
        $packagename=$_.name
        $packagename=$packagename -replace "\'", "\s"
        $packagever=$_.version
        $sql_q = "INSERT INTO temp_modules (name,version) VALUES ('$packagename','$packagever')"
        sql_query $sql_q $connection "temp_modules"
    }
    write-log "table temp_modules was successfully populated with data"{completed}

    $psgallery = @()
    $sql_q = "SELECT current_modules.name, temp_modules.version FROM current_modules LEFT JOIN temp_modules ON current_modules.name = temp_modules.name WHERE current_modules.version <> temp_modules.version;"
    sql_query $sql_q $connection "current_modules" | ForEach {
    $nmodule = @{
        nmodule = $_.name
        vmodule = $_.version
    }
    $objmodule = New-Object -TypeName psobject -Property $nmodule
    $psgallery += $objmodule
    }
    write-log "first sample added to array"{completed}

    try {
        Test-connection nexus.local -Count 3 -ErrorAction Stop
        write-log "Connect to nexus - OK"{completed}
    }
    catch {
        $body = "nexus not pinging"
        FuncMail $body $subjectfail $email
        return write-log "nexus not pinging"{warning}
    }
    get-assetnexus
    write-log 'function get-assetnexus completed successfully.'{completed}

    $Differencename = (Compare-Object -ReferenceObject $modulepsgallery.name -DifferenceObject $modules.id |`
    ? {$_.SideIndicator -eq "<="}).InputObject

    foreach ($_ in $Differencename) {
    $nmodule = @{
        nmodule = $_
    }
    $objmodule = New-Object -TypeName psobject -Property $nmodule
    $psgallery += $objmodule
    }
    write-log "second sample added to array"{completed}

    write-log "Try to save packages locally"
    foreach ($_ in $psgallery) {
        Save-Package -name $_.nmodule -provider nuget -source https://www.powershellgallery.com/api/v2 -Path $pathtomodules
        if ($error.Count -gt 0) {
            write-log $error{warning}
            $error.clear()
        }
    }

    write-log "Try to save modules to nexus"
    $files = Get-ChildItem $pathtomodules
    foreach ($_ in $files) {
        $path = $_.fullname
        $name = $_.name
        add-packagenexus -path $path
        if ($error.Count -gt 0) {
            write-log  ($error+$name){warning} 
            $error.clear()
        }
    }
    write-log "Procedure save modules to nexus completed"{completed}
    
    $sql_q = "SELECT COUNT(*) AS recordscount FROM current_modules;"
    $recordscount = sql_query $sql_q $connection "current_modules"

    if ($recordscount -eq "0") {
        $body = "current_modules table is empty"
        FuncMail $body $subjectfail $email
        return write-log "current_modules table is empty"{warning}
    }
    else {
        write-log "TRUNC table current_modules"
        $sql_q = "TRUNCATE TABLE current_modules;"
        sql_query $sql_q $connection "current_modules"

        write-log "Insert temp_modules to current_modules"
        $sql_q = "INSERT INTO current_modules SELECT * FROM temp_modules;"
        sql_query $sql_q $connection "current_modules"

        write-log "TRUNC table temp_modules"
        $sql_q = "TRUNCATE TABLE temp_modules;"
        sql_query $sql_q $connection "temp_modules"

        write-log "Delete all downloaded modules from temp folder"
        Remove-Item "$pathtomodules*" -Force -Recurse -Confirm:$false

        $connection.close()
        write-log "Conection to base was closed successfully."

        write-log "$ProgrammName (ver $ver) completed."
    }
    
}

# Register-PSRepository -Name HoffPSRepo -SourceLocation http://nexus.local/repository/posh_psgallery/ -ScriptSourceLocation http://nexus.local/repository/posh_psgallery/2 -InstallationPolicy Trusted 