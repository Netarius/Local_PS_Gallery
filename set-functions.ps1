$ver = "0.4"
$dt=Get-Date -Format "dd-MM-yyyy"
New-Item -ItemType directory $ScriptPatch'log' -Force | out-null

$global:logfilename= $ScriptPatch+'log\'+$dt+"_LOG.log"
[int]$global:errorcount=0 
[int]$global:warningcount=0 

function global:Write-log
{param($message,[string]$type="info",[string]$logfile=$global:logfilename,[switch]$silent)	
	$dt=Get-Date -Format "dd.MM.yyyy HH:mm:ss"	
	$msg=$dt + "`t" + $type + "`t" + $message #формат: 01.01.2001 01:01:01 [tab] error [tab] Сообщение
	Out-File -FilePath $logfile -InputObject $msg -Append -encoding unicode
	if (-not $silent.IsPresent) 
	{
		switch ( $type.toLower() )
		{
			"error"
			{			
				$global:errorcount++
				write-host $msg -ForegroundColor red			
			}
			"warning"
			{			
				$global:warningcount++
				write-host $msg -ForegroundColor yellow
			}
			"completed"
			{			
				write-host $msg -ForegroundColor green
			}
			"info"
			{			
				write-host $msg
			}			
			default 
			{ 
				write-host $msg
			}
		}
	}
}

function global:get-assetnexus
{
    $Headers=@{}
    $Headers.Add("Content-Type", "application/json")
    $Headers.Add("NX-ANTI-CSRF-TOKEN", "0.5328129076942965")
    $Headers.Add("Authorization", "Basic c3ZjX3Bvc2hnYWxsZXJ5OiM9c08rclM2aWZvRlwzP0F3Tk5s")

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $result = Invoke-RestMethod -Uri 'http://nexus.local/service/rest/v1/assets?repository=posh_psgallery' -Method GET -Headers $headers
    
    $Global:modules = @()
    $modulespaging = @()
    $modulespaging = $result | Select-Object -ExpandProperty items | Select-Object -ExpandProperty nuget | Select id, version, is_latest_version

    $Global:modules += $modulespaging | where { $_.is_latest_version -eq $True }
    while ($result.continuationToken -ne $null) {
        $result = Invoke-RestMethod -Uri "http://nexus.local/service/rest/v1/assets?continuationToken=$($result.continuationToken)&repository=posh_psgallery" -Method GET -Headers $headers
        $modulespaging = $result | Select-Object -ExpandProperty items | Select-Object -ExpandProperty nuget | Select id, version, is_latest_version
        $Global:modules += $modulespaging | where { $_.is_latest_version -eq $True }
    }
}


function global:add-packagenexus
{param(
    [Parameter(Mandatory=$True)][string]$path
    )
   
    $Headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $Headers.Add("Accept", 'application/json')
    $Headers.Add("Authorization", "Basic c3ZjX3Bvc2hnYWxsZXJ5OiM9c08rclM2aWZvRlwzP0F3Tk5s")
    $Headers.Add("NX-ANTI-CSRF-TOKEN", '0.5328129076942965')

    $formheader=@{
        "nuget.asset" = Get-Item -path "$path"
    }

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $DisableResponse = Invoke-RestMethod "http://nexus.local/service/rest/v1/components?repository=posh_psgallery" -Headers $Headers -Form $formheader -Method Post  -ContentType "multipart/form-data"
    }

function global:sql_query ($sql_q,$connection,$table_name) {
	$command = New-Object MySql.Data.MySqlClient.MySqlCommand ($sql_q,$connection)
	$dataAdapter = New-Object MySql.Data.MySqlClient.MySqlDataAdapter ($command)
	$dataSet = New-Object System.Data.DataSet
	$dataAdapter.Fill($dataSet,$table_name) | Out-Null
	$dataTable = $dataSet.Tables[$table_name]
	return $dataTable
	}

#Add-Type -path 'C:\script\1_2023\sg\MySql.Data.dll'

$connectionstring = "server=$serverdb;uid=$userdb;pwd=$passdb;database=$database"
$Global:connection= new-object Mysql.data.mysqlclient.mysqlconnection
$connection.ConnectionString = $connectionstring

Function global:FuncMail ($body, $subj, $mail){
	Send-MailMessage -To $mail -From "syncPSGallery@hoff.ru" -Subject $subj -SmtpServer smtp.kifr-ru.local -Body $body -Encoding 'UTF8'
}