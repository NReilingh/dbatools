$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        $paramCount = 7
        $defaultParamCount = 13
        [object[]]$params = (Get-ChildItem function:\Mount-DbaDatabase).Parameters.Keys
        $knownParameters = 'SqlInstance','SqlCredential','Database','FileStructure','DatabaseOwner','AttachOption','EnableException'
        It "Should contain our specific parameters" {
            ( (Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count ) | Should Be $paramCount
        }
        It "Should only contain $paramCount parameters" {
            $params.Count - $defaultParamCount | Should Be $paramCount
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    Context "Setup removes, restores and backups on the local drive for Mount-DbaDatabase" {
        $null = Get-DbaDatabase -SqlInstance $script:instance1 -Database detachattach | Remove-DbaDatabase -Confirm:$false
        $null = Restore-DbaDatabase -SqlInstance $script:instance1 -Path $script:appveyorlabrepo\detachattach\detachattach.bak -WithReplace
        $null = Get-DbaDatabase -SqlInstance $script:instance1 -Database detachattach | Backup-DbaDatabase -Type Full
        $null = Detach-DbaDatabase -SqlInstance $script:instance1 -Database detachattach -Force
    }

    Context "Attaches a single database and tests to ensure the alias still exists" {
        $results = Attach-DbaDatabase -SqlInstance $script:instance1 -Database detachattach

        It "Should return success" {
            $results.AttachResult | Should Be "Success"
        }

        It "Should return that the database is only Database" {
            $results.Database | Should Be "detachattach"
        }

        It "Should return that the AttachOption default is None" {
            $results.AttachOption | Should Be "None"
        }
    }

    $null = Get-DbaDatabase -SqlInstance $script:instance1 -Database detachattach | Remove-DbaDatabase -Confirm:$false
}
