#Requires -Version 5.1
<#
.SYNOPSIS
    AutoPS Beta 0.5 - Database.ps1
    SQL Client with multi-provider support and JSON file backend

.DESCRIPTION
    This module provides database abstraction for AutoPS:
    
    AutoPSSqlClient Class:
    - Supports SQLite, PostgreSQL, MySQL, SqlServer, and JSON file backends
    - Provides ExecuteQuery (read) and ExecuteNonQuery (write) methods
    - Handles connection lifecycle and parameter binding
    
    Schema Management:
    - Get-AutoPSSchema: Returns DDL for all tables
    - Initialize-AutoPSDatabase: Creates tables if not exist
    - Test-AutoPSDatabaseSchema: Validates database connectivity
    
    Tables:
    - Nodes: Registered execution nodes
    - Jobs: Job execution records (with RuntimeMs, TriggerType)
    - Workflows: Workflow execution records
    - Tasks: Task definitions (from manifest)
    - TaskExecutions: Individual task run records with status/state
    - Integrations: Integration health records

.NOTES
    The JSON provider stores all data in a single JSON file, suitable for
    development and single-user scenarios. For production, use SQLite or
    a proper database server.
    
    PowerShell class definition guard: The AutoPSSqlClient class is wrapped
    in a type-exists check to prevent redefinition errors when dot-sourcing.

.EXAMPLE
    $client = [AutoPSSqlClient]::new("Data Source=./data/autops.json", "Json")
    $client.ExecuteNonQuery("INSERT INTO Jobs ...", @{ Name = "test" })
    $results = $client.ExecuteQuery("SELECT * FROM Jobs", @{})
#>

# Load System.Data for DbConnection types (SQLite, SqlServer, etc.)
Add-Type -AssemblyName System.Data

# ============================================================================
# SQL CLIENT CLASS
# Multi-provider database abstraction layer
# ============================================================================

# Guard: Skip class definition if already loaded (prevents PS type mismatch
# errors when dot-sourcing the same file multiple times in a session)
if (-not ([System.Management.Automation.PSTypeName]'AutoPSSqlClient').Type) {

    class AutoPSSqlClient {
        [string]$ConnectionString
        [string]$Provider  # 'SQLite', 'PostgreSQL', 'MySQL', 'SqlServer', 'Json'
    
        AutoPSSqlClient([string]$connString, [string]$provider) {
            $this.ConnectionString = $connString
            $this.Provider = $provider
        }
    
        [System.Data.Common.DbConnection] CreateConnection() {
            switch ($this.Provider) {
                'Json' {
                    # JSON backend doesn't use connections
                    return $null
                }
                'SQLite' {
                    if (-not ([System.Management.Automation.PSTypeName]'Microsoft.Data.Sqlite.SqliteConnection').Type) {
                        throw "SQLite provider not available. Install Microsoft.Data.Sqlite."
                    }
                    return New-Object Microsoft.Data.Sqlite.SqliteConnection($this.ConnectionString)
                }
                'PostgreSQL' {
                    if (-not ([System.Management.Automation.PSTypeName]'Npgsql.NpgsqlConnection').Type) {
                        throw "PostgreSQL provider not available. Install Npgsql."
                    }
                    return New-Object Npgsql.NpgsqlConnection($this.ConnectionString)
                }
                'MySQL' {
                    if (-not ([System.Management.Automation.PSTypeName]'MySql.Data.MySqlClient.MySqlConnection').Type) {
                        throw "MySQL provider not available. Install MySql.Data."
                    }
                    return New-Object MySql.Data.MySqlClient.MySqlConnection($this.ConnectionString)
                }
                'SqlServer' {
                    return New-Object System.Data.SqlClient.SqlConnection($this.ConnectionString)
                }
                default {
                    throw "Unknown provider: $($this.Provider)"
                }
            }
            return $null  # Fallback (should never reach)
        }
    
        [void] ExecuteNonQuery([string]$query, [hashtable]$parameters) {
            if ($this.Provider -eq 'Json') {
                $this.ExecuteJsonCommand($query, $parameters)
                return
            }
        
            $conn = $this.CreateConnection()
            try {
                $conn.Open()
                $cmd = $conn.CreateCommand()
                $cmd.CommandText = $this.TranslateQuery($query)
            
                if ($parameters) {
                    foreach ($key in $parameters.Keys) {
                        $p = $cmd.CreateParameter()
                        $p.ParameterName = "@$key"
                        $p.Value = if ($null -eq $parameters[$key]) { [DBNull]::Value } else { $parameters[$key] }
                        $cmd.Parameters.Add($p) | Out-Null
                    }
                }
                $cmd.ExecuteNonQuery() | Out-Null
            }
            finally {
                $conn.Close()
                $conn.Dispose()
            }
        }
    
        [System.Data.DataTable] ExecuteQuery([string]$query, [hashtable]$parameters) {
            if ($this.Provider -eq 'Json') {
                return $this.ExecuteJsonQuery($query, $parameters)
            }
        
            $conn = $this.CreateConnection()
            try {
                $conn.Open()
                $cmd = $conn.CreateCommand()
                $cmd.CommandText = $this.TranslateQuery($query)
            
                if ($parameters) {
                    foreach ($key in $parameters.Keys) {
                        $p = $cmd.CreateParameter()
                        $p.ParameterName = "@$key"
                        $p.Value = if ($null -eq $parameters[$key]) { [DBNull]::Value } else { $parameters[$key] }
                        $cmd.Parameters.Add($p) | Out-Null
                    }
                }
            
                $reader = $cmd.ExecuteReader()
                $dt = New-Object System.Data.DataTable
                $dt.Load($reader)
                $reader.Close()
                return $dt
            }
            finally {
                $conn.Close()
                $conn.Dispose()
            }
        }
    
        [string] TranslateQuery([string]$query) {
            # Translate SQL dialects
            switch ($this.Provider) {
                'SQLite' {
                    $query = $query -replace 'GETDATE\(\)', "datetime('now')"
                    $query = $query -replace 'NVARCHAR\(\d+\)', 'TEXT'
                    $query = $query -replace 'NVARCHAR\(MAX\)', 'TEXT'
                }
                'PostgreSQL' {
                    $query = $query -replace 'GETDATE\(\)', 'NOW()'
                    $query = $query -replace 'NVARCHAR\((\d+)\)', 'VARCHAR($1)'
                    $query = $query -replace 'NVARCHAR\(MAX\)', 'TEXT'
                }
                'MySQL' {
                    $query = $query -replace 'GETDATE\(\)', 'NOW()'
                    $query = $query -replace 'NVARCHAR\((\d+)\)', 'VARCHAR($1)'
                    $query = $query -replace 'NVARCHAR\(MAX\)', 'LONGTEXT'
                }
            }
            return $query
        }
    
        # ========== JSON Backend ==========
    
        hidden [string] GetJsonPath() {
            return $this.ConnectionString -replace 'Data Source=', ''
        }
    
        hidden [psobject] LoadJsonDb() {
            $path = $this.GetJsonPath()
            if (Test-Path $path) {
                $content = Get-Content $path -Raw
                if ($content) {
                    return $content | ConvertFrom-Json
                }
            }
            return @{
                Nodes          = @()
                Jobs           = @()
                Workflows      = @()
                Tasks          = @()
                TaskExecutions = @()
                Integrations   = @()
            }
        }
    
        hidden [void] SaveJsonDb([psobject]$db) {
            $path = $this.GetJsonPath()
            $parent = Split-Path $path -Parent
            if ($parent -and -not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
            $db | ConvertTo-Json -Depth 6 | Set-Content $path
        }
    
        hidden [void] ExecuteJsonCommand([string]$query, [hashtable]$params) {
            $db = $this.LoadJsonDb()
        
            # INSERT operations
            if ($query -match 'INSERT INTO (\w+)') {
                $table = $Matches[1]
                $record = @{}
                foreach ($key in $params.Keys) { $record[$key] = $params[$key] }
                if (-not $db.$table) { $db | Add-Member -NotePropertyName $table -NotePropertyValue @() -Force }
                $db.$table += $record
            }
            # UPDATE operations
            elseif ($query -match 'UPDATE (\w+).*WHERE (\w+)\s*=\s*@(\w+)\s+AND\s+(\w+)\s*=\s*@(\w+)') {
                $table = $Matches[1]
                $col1 = $Matches[2]
                $param1 = $Matches[3]
                $col2 = $Matches[4]
                $param2 = $Matches[5]
            
                $val1 = $params[$param1]
                $val2 = $params[$param2]
            
                for ($i = 0; $i -lt $db.$table.Count; $i++) {
                    if ($db.$table[$i].$col1 -eq $val1 -and $db.$table[$i].$col2 -eq $val2) {
                        foreach ($key in $params.Keys) {
                            if ($key -ne $param1 -and $key -ne $param2) {
                                $db.$table[$i] | Add-Member -NotePropertyName $key -NotePropertyValue $params[$key] -Force
                            }
                        }
                        if ($query -match "Status\s*=\s*'(\w+)'") {
                            $db.$table[$i] | Add-Member -NotePropertyName 'Status' -NotePropertyValue $Matches[1] -Force
                        }
                        if ($query -match "Status\s*=\s*@Status" -and $params.Status) {
                            $db.$table[$i] | Add-Member -NotePropertyName 'Status' -NotePropertyValue $params.Status -Force
                        }
                        break
                    }
                }
            }
            elseif ($query -match 'UPDATE (\w+).*WHERE (\w+)\s*=\s*@(\w+)') {
                $table = $Matches[1]
                $keyCol = $Matches[2]
                $keyParam = $Matches[3]
                $keyValue = $params[$keyParam]
            
                for ($i = 0; $i -lt $db.$table.Count; $i++) {
                    if ($db.$table[$i].$keyCol -eq $keyValue) {
                        foreach ($key in $params.Keys) {
                            if ($key -ne $keyParam) {
                                $db.$table[$i] | Add-Member -NotePropertyName $key -NotePropertyValue $params[$key] -Force
                            }
                        }
                        # Handle status updates from query pattern
                        if ($query -match "Status\s*=\s*'(\w+)'") {
                            $db.$table[$i] | Add-Member -NotePropertyName 'Status' -NotePropertyValue $Matches[1] -Force
                        }
                        break
                    }
                }
            }
        
            $this.SaveJsonDb($db)
        }
    
        hidden [System.Data.DataTable] ExecuteJsonQuery([string]$query, [hashtable]$params) {
            $db = $this.LoadJsonDb()
            $dt = New-Object System.Data.DataTable
        
            # SELECT with WHERE
            if ($query -match 'FROM (\w+)') {
                $table = $Matches[1]
                $records = $db.$table
            
                # Apply filters
                if ($query -match 'WHERE.*?(\w+)\s*=\s*@(\w+)') {
                    $colName = $Matches[1]
                    $paramName = $Matches[2]
                    if ($params.$paramName) {
                        $paramValue = $params.$paramName
                        $records = $records | Where-Object { $_.$colName -eq $paramValue }
                    }
                }
                if ($query -match "Status\s*=\s*'(\w+)'") {
                    $status = $Matches[1]
                    $records = $records | Where-Object { $_.Status -eq $status }
                }
                if ($query -match "Status\s*=\s*@Status" -and $params.Status) {
                    $records = $records | Where-Object { $_.Status -eq $params.Status }
                }
            
                # LIMIT/TOP 1
                if ($query -match 'LIMIT 1|TOP 1') {
                    $records = $records | Select-Object -First 1
                }
            
                # Build DataTable - collect ALL columns from ALL records
                if ($records) {
                    $allColumns = @{}
                    foreach ($rec in $records) {
                        foreach ($prop in $rec.PSObject.Properties) {
                            $allColumns[$prop.Name] = $true
                        }
                    }
                    foreach ($colName in $allColumns.Keys) {
                        $dt.Columns.Add($colName) | Out-Null
                    }
                
                    foreach ($rec in $records) {
                        $row = $dt.NewRow()
                        foreach ($colName in $allColumns.Keys) {
                            if ($rec.PSObject.Properties[$colName]) {
                                $val = $rec.$colName
                                if ($val -is [DateTime]) {
                                    $row[$colName] = $val.ToString('o')
                                }
                                else {
                                    $row[$colName] = $val
                                }
                            }
                            else {
                                $row[$colName] = [DBNull]::Value
                            }
                        }
                        $dt.Rows.Add($row)
                    }
                }
            }
        
            return $dt
        }
    }

} # End of guard: if class not already defined

# ============================================================================
# SCHEMA MANAGEMENT
# ============================================================================

function Get-AutoPSSchema {
    param([string]$Provider)
    
    $sqliteSchema = @"
CREATE TABLE IF NOT EXISTS Nodes (
    NodeId TEXT PRIMARY KEY,
    Name TEXT,
    OS TEXT,
    Capabilities TEXT,
    LastHeartbeat TEXT,
    Status TEXT
);

CREATE TABLE IF NOT EXISTS Jobs (
    JobId TEXT,
    TriggerType TEXT,
    Cron TEXT,
    Status TEXT,
    CreatedAt TEXT,
    StartedAt TEXT,
    EndedAt TEXT,
    RuntimeMs INTEGER,
    CreatedBy TEXT,
    InputParams TEXT,
    InputParams TEXT,
    Name TEXT,
    PRIMARY KEY (JobId, Name)
);

CREATE TABLE IF NOT EXISTS Workflows (
    WorkflowId TEXT PRIMARY KEY,
    JobId TEXT,
    ParentWorkflowId TEXT,
    Name TEXT,
    Status TEXT,
    StartedAt TEXT,
    EndedAt TEXT,
    RuntimeMs INTEGER,
    TriggerType TEXT
);

CREATE TABLE IF NOT EXISTS Tasks (
    TaskId TEXT PRIMARY KEY,
    WorkflowId TEXT,
    JobId TEXT,
    Name TEXT,
    Script TEXT,
    Runtime TEXT,
    RuntimeEnv TEXT,
    TargetNode TEXT,
    ExecutedOnNode TEXT,
    DependsOn TEXT,
    Status TEXT,
    State TEXT
);

CREATE TABLE IF NOT EXISTS TaskExecutions (
    ExecutionId TEXT,
    TaskId TEXT,
    JobName TEXT,
    WorkflowName TEXT,
    TriggerType TEXT,
    InputData TEXT,
    OutputData TEXT,
    ErrorLog TEXT,
    ExecutionLog TEXT,
    Status TEXT,
    StartedAt TEXT,
    EndedAt TEXT,
    RuntimeMs INTEGER,
    Output TEXT,
    State TEXT,
    Attempt INTEGER,
    MaxRetries INTEGER,
    PRIMARY KEY (ExecutionId, TaskId)
);

CREATE TABLE IF NOT EXISTS Integrations (
    IntegrationId TEXT PRIMARY KEY,
    Name TEXT,
    Type TEXT,
    LastChecked TEXT,
    Status TEXT,
    ErrorMessage TEXT
);
"@
    
    if ($Provider -eq 'SQLite' -or $Provider -eq 'Json') {
        return $sqliteSchema
    }
    
    # SqlServer/PostgreSQL/MySQL - adapt as needed
    return $sqliteSchema -replace 'TEXT', 'NVARCHAR(MAX)'
}

function Initialize-AutoPSDatabase {
    param($Client)
    
    if ($Client.Provider -eq 'Json') {
        $path = $Client.ConnectionString -replace 'Data Source=', ''
        $parent = Split-Path $path -Parent
        if ($parent -and -not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        
        if (-not (Test-Path $path)) {
            @{
                Nodes          = @()
                Jobs           = @()
                Workflows      = @()
                Tasks          = @()
                TaskExecutions = @()
                Integrations   = @()
            } | ConvertTo-Json -Depth 4 | Set-Content $path
        }
        return
    }
    
    $schema = Get-AutoPSSchema -Provider $Client.Provider
    
    # Split into individual statements for SQLite
    $statements = $schema -split ';\s*' | Where-Object { $_.Trim() }
    foreach ($stmt in $statements) {
        if ($stmt.Trim()) {
            $Client.ExecuteNonQuery($stmt.Trim(), @{})
        }
    }
}

function Test-AutoPSDatabaseSchema {
    param($Client)
    
    try {
        if ($Client.Provider -eq 'Json') {
            $path = $Client.ConnectionString -replace 'Data Source=', ''
            return Test-Path $path
        }
        
        $query = switch ($Client.Provider) {
            'SQLite' { "SELECT name FROM sqlite_master WHERE type='table' AND name='Jobs'" }
            'PostgreSQL' { "SELECT table_name FROM information_schema.tables WHERE table_name = 'jobs'" }
            'MySQL' { "SELECT table_name FROM information_schema.tables WHERE table_name = 'Jobs'" }
            default { "SELECT * FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = 'Jobs'" }
        }
        
        $dt = $Client.ExecuteQuery($query, @{})
        return $dt.Rows.Count -gt 0
    }
    catch {
        return $false
    }
}

function Test-AutoPSDatabaseConnection {
    param($Client)
    
    try {
        if ($Client.Provider -eq 'Json') {
            return $true  # JSON always works
        }
        
        $conn = $Client.CreateConnection()
        $conn.Open()
        $conn.Close()
        $conn.Dispose()
        return $true
    }
    catch {
        return $false
    }
}
