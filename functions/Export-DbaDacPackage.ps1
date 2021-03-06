function Export-DbaDacPackage {
    <#
    .SYNOPSIS
        Exports a dacpac from a server.

    .DESCRIPTION
        Using SQLPackage, export a dacpac from an instance of SQL Server.

        Note - Extract from SQL Server is notoriously flaky - for example if you have three part references to external databases it will not work.

        For help with the extract action parameters and properties, refer to https://msdn.microsoft.com/en-us/library/hh550080(v=vs.103).aspx

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Allows you to login to servers using alternative logins instead Integrated, accepts Credential object created by Get-Credential

    .PARAMETER Path
        The directory where the .dacpac files will be exported to. Defaults to documents.

    .PARAMETER Database
        The database(s) to process - this list is auto-populated from the server. If unspecified, all databases will be processed.

    .PARAMETER ExcludeDatabase
        The database(s) to exclude - this list is auto-populated from the server

    .PARAMETER AllUserDatabases
        Run command against all user databases

    .PARAMETER Type
        Selecting the type of the export: Dacpac (default) or Bacpac.

    .PARAMETER Table
        List of the tables to include into the export. Should be provided as an array of strings: dbo.Table1, Table2, Schema1.Table3.

    .PARAMETER DacOption
        Export options for a corresponding export type. Can be created by New-DbaDacOption -Type Dacpac | Bacpac

    .PARAMETER ExtendedParameters
        Optional parameters used to extract the DACPAC. More information can be found at
        https://msdn.microsoft.com/en-us/library/hh550080.aspx

    .PARAMETER ExtendedProperties
        Optional properties used to extract the DACPAC. More information can be found at
        https://msdn.microsoft.com/en-us/library/hh550080.aspx

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Migration, Database, Dacpac
        Author: Richie lee (@richiebzzzt)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Export-DbaDacPackage

    .EXAMPLE
        PS C:\> Export-DbaDacPackage -SqlInstance sql2016 -Database SharePoint_Config

        Exports the dacpac for SharePoint_Config on sql2016 to $home\Documents\SharePoint_Config.dacpac

    .EXAMPLE
        PS C:\> $options = New-DbaDacOption -Type Dacpac
        PS C:\> $options.ExtractAllTableData = $true
        PS C:\> $options.CommandTimeout = 0
        PS C:\> Export-DbaDacPackage -SqlInstance sql2016 -Database DB1 -Options

        Uses DacOption object to set the CommandTimeout to 0 then extracts the dacpac for DB1 on sql2016 to $home\Documents\DB1.dacpac including all table data.

    .EXAMPLE
        PS C:\> Export-DbaDacPackage -SqlInstance sql2016 -AllUserDatabases -ExcludeDatabase "DBMaintenance","DBMonitoring" C:\temp

        Exports dacpac packages for all USER databases, excluding "DBMaintenance" & "DBMonitoring", on sql2016 and saves them to C:\temp

    .EXAMPLE
        PS C:\> $moreparams = "/OverwriteFiles:$true /Quiet:$true"
        PS C:\> Export-DbaDacPackage -SqlInstance sql2016 -Database SharePoint_Config -Path C:\temp -ExtendedParameters $moreparams

        Using extended parameters to over-write the files and performs the extraction in quiet mode. Uses command line instead of SMO behind the scenes.
#>
    [CmdletBinding(DefaultParameterSetName = 'SMO')]
    param
    (
        [parameter(Mandatory, ValueFromPipeline)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstance[]]$SqlInstance,
        [Alias("Credential")]
        [PSCredential]$SqlCredential,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [switch]$AllUserDatabases,
        [string]$Path = "$home\Documents",
        [parameter(ParameterSetName = 'SMO')]
        [Alias('ExtractOptions', 'ExportOptions', 'DacExtractOptions', 'DacExportOptions', 'Options', 'Option')]
        [object]$DacOption,
        [parameter(ParameterSetName = 'CMD')]
        [string]$ExtendedParameters,
        [parameter(ParameterSetName = 'CMD')]
        [string]$ExtendedProperties,
        [ValidateSet('Dacpac', 'Bacpac')]
        [string]$Type = 'Dacpac',
        [parameter(ParameterSetName = 'SMO')]
        [string[]]$Table,
        [switch]$EnableException
    )

    process {
        if ((Test-Bound -Not -ParameterName Database) -and (Test-Bound -Not -ParameterName ExcludeDatabase) -and (Test-Bound -Not -ParameterName AllUserDatabases)) {
            Stop-Function -Message "You must specify databases to execute against using either -Database, -ExcludeDatabase or -AllUserDatabases"
            return
        }

        if (-not (Test-Path $Path)) {
            Write-Message -Level Verbose "Assuming that $Path is a file path"
            $parentFolder = Split-Path $path -Parent
            if (-not (Test-Path $parentFolder)) {
                Stop-Function -Message "$parentFolder doesn't exist or access denied"
                return
            }
            $leaf = Split-Path $path -Leaf
            $fileName = Join-Path (Get-Item $parentFolder) $leaf
        } else {
            $fileItem = Get-Item $Path
            if ($fileItem -is [System.IO.DirectoryInfo]) {
                $parentFolder = $fileItem.FullName
            } elseif ($fileItem -is [System.IO.FileInfo]) {
                $fileName = $fileItem.FullName
            }
        }

        $dacfxPath = "$script:PSModuleRoot\bin\smo\Microsoft.SqlServer.Dac.dll"
        if ((Test-Path $dacfxPath) -eq $false) {
            Stop-Function -Message 'Dac Fx library not found.' -EnableException $EnableException
            return
        } else {
            try {
                Add-Type -Path $dacfxPath
                Write-Message -Level Verbose -Message "Dac Fx loaded."
            } catch {
                Stop-Function -Message 'No usable version of Dac Fx found.' -ErrorRecord $_
                return
            }
        }

        #check that at least one of the DB selection parameters was specified
        if (!$AllUserDatabases -and !$Database) {
            Stop-Function -Message "Either -Database or -AllUserDatabases should be specified" -Continue
        }
        #Check Option object types - should have a specific type
        if ($Type -eq 'Dacpac') {
            if ($DacOption -and $DacOption -isnot [Microsoft.SqlServer.Dac.DacExtractOptions]) {
                Stop-Function -Message "Microsoft.SqlServer.Dac.DacExtractOptions object type is expected - got $($DacOption.GetType())."
                return
            }
        } elseif ($Type -eq 'Bacpac') {
            if ($DacOption -and $DacOption -isnot [Microsoft.SqlServer.Dac.DacExportOptions]) {
                Stop-Function -Message "Microsoft.SqlServer.Dac.DacExportOptions object type is expected - got $($DacOption.GetType())."
                return
            }
        }

        #Create a tuple to be used as a table filter
        if ($Table) {
            $tblList = New-Object 'System.Collections.Generic.List[Tuple[String, String]]'
            foreach ($tableItem in $Table) {
                $tableSplit = $tableItem.Split('.')
                if ($tableSplit.Count -gt 1) {
                    $tblName = $tableSplit[-1]
                    $schemaName = $tableSplit[-2]
                } else {
                    $tblName = [string]$tableSplit
                    $schemaName = 'dbo'
                }
                $tblList.Add((New-Object "tuple[String, String]" -ArgumentList $schemaName, $tblName))
            }
        } else {
            $tblList = $null
        }

        foreach ($instance in $sqlinstance) {
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $sqlcredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }
            $cleaninstance = $instance.ToString().Replace('\', '-')

            $dbs = Get-DbaDatabase -SqlInstance $server -OnlyAccessible -ExcludeAllSystemDb -Database $Database -ExcludeDatabase $ExcludeDatabase
            if (-not $dbs) {
                Stop-Function -Message "Databases not found on $instance" -Target $instance -Continue
            }

            foreach ($db in $dbs) {
                $dbname = $db.name
                $connstring = $server.ConnectionContext.ConnectionString
                if ($connstring -notmatch 'Database=') {
                    $connstring = "$connstring;Database=$dbname"
                }
                if ($fileName) {
                    $currentFileName = $fileName
                } else {
                    if ($Type -eq 'Dacpac') { $ext = 'dacpac' }
                    elseif ($Type -eq 'Bacpac') { $ext = 'bacpac' }
                    $currentFileName = Join-Path $parentFolder "$cleaninstance-$dbname.$ext"
                }
                Write-Message -Level Verbose -Message "Using connection string $connstring"

                #using SMO by default
                if ($PsCmdlet.ParameterSetName -eq 'SMO') {
                    try {
                        $dacSvc = New-Object -TypeName Microsoft.SqlServer.Dac.DacServices -ArgumentList $connstring -ErrorAction Stop
                    } catch {
                        Stop-Function -Message "Could not connect to the connection string $connstring" -Target $instance -Continue
                    }
                    if (!$DacOption) {
                        $opts = New-DbaDacOption -Type $Type -Action Export
                    } else {
                        $opts = $DacOption
                    }
                    $global:output = @()
                    Register-ObjectEvent -InputObject $dacSvc -EventName "Message" -SourceIdentifier "msg" -Action { $global:output += $EventArgs.Message.Message } | Out-Null

                    if ($Type -eq 'Dacpac') {
                        Write-Message -Level Verbose -Message "Initiating Dacpac extract to $currentFileName"
                        #not sure how to extract that info from the existing DAC application, leaving 1.0.0.0 for now
                        $version = New-Object System.Version -ArgumentList '1.0.0.0'
                        try {
                            $dacSvc.Extract($currentFileName, $dbname, $dbname, $version, $null, $tblList, $opts, $null)
                        } catch {
                            Stop-Function -Message "DacServices extraction failure" -ErrorRecord $_ -Continue
                        } finally {
                            Unregister-Event -SourceIdentifier "msg"
                        }
                    } elseif ($Type -eq 'Bacpac') {
                        Write-Message -Level Verbose -Message "Initiating Bacpac export to $currentFileName"
                        try {
                            $dacSvc.ExportBacpac($currentFileName, $dbname, $opts, $tblList, $null)
                        } catch {
                            Stop-Function -Message "DacServices export failure" -ErrorRecord $_ -Continue
                        } finally {
                            Unregister-Event -SourceIdentifier "msg"
                        }
                    }
                    $finalResult = ($global:output -join "`r`n" | Out-String).Trim()
                } elseif ($PsCmdlet.ParameterSetName -eq 'CMD') {
                    if ($Type -eq 'Dacpac') { $action = 'Extract' }
                    elseif ($Type -eq 'Bacpac') { $action = 'Export' }
                    $cmdConnString = $connstring.Replace('"', "'")

                    $sqlPackageArgs = "/action:$action /tf:""$currentFileName"" /SourceConnectionString:""$cmdConnString"" $ExtendedParameters $ExtendedProperties"
                    $resultstime = [diagnostics.stopwatch]::StartNew()

                    try {
                        $startprocess = New-Object System.Diagnostics.ProcessStartInfo
                        $startprocess.FileName = "$script:PSModuleRoot\bin\smo\sqlpackage.exe"
                        $startprocess.Arguments = $sqlPackageArgs
                        $startprocess.RedirectStandardError = $true
                        $startprocess.RedirectStandardOutput = $true
                        $startprocess.UseShellExecute = $false
                        $startprocess.CreateNoWindow = $true
                        $process = New-Object System.Diagnostics.Process
                        $process.StartInfo = $startprocess
                        $process.Start() | Out-Null
                        $stdout = $process.StandardOutput.ReadToEnd()
                        $stderr = $process.StandardError.ReadToEnd()
                        $process.WaitForExit()
                        Write-Message -level Verbose -Message "StandardOutput: $stdout"
                        $finalResult = $stdout
                    } catch {
                        Stop-Function -Message "SQLPackage Failure" -ErrorRecord $_ -Continue
                    }

                    if ($process.ExitCode -ne 0) {
                        Stop-Function -Message "Standard output - $stderr" -Continue
                    }
                }
                [pscustomobject]@{
                    ComputerName = $server.ComputerName
                    InstanceName = $server.ServiceName
                    SqlInstance  = $server.DomainInstanceName
                    Database     = $dbname
                    Path         = $currentFileName
                    Elapsed      = [prettytimespan]($resultstime.Elapsed)
                    Result       = $finalResult
                } | Select-DefaultView -ExcludeProperty ComputerName, InstanceName
            }
        }
    }
    end {
        Test-DbaDeprecation -DeprecatedOn "1.0.0" -EnableException:$false -Alias Export-DbaDacpac
    }
}