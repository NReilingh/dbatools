$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Integration Tests" -Tag "IntegrationTests" {
    Context "Setup" {
        BeforeAll {
            $srvName = "dbatoolsci-server1"
            $group = "dbatoolsci-group1"
            $regSrvName = "dbatoolsci-server12"
            $regSrvDesc = "dbatoolsci-server123"
            $groupobject = Add-DbaCmsRegServerGroup -SqlInstance $script:instance1 -Name $group
        }
        AfterAll {
            Get-DbaCmsRegServer -SqlInstance $script:instance1, $script:instance2 | Where-Object Name -match dbatoolsci | Remove-DbaCmsRegServer -Confirm:$false
            Get-DbaCmsRegServerGroup -SqlInstance $script:instance1, $script:instance2 | Where-Object Name -match dbatoolsci | Remove-DbaCmsRegServerGroup -Confirm:$false
        }

        It "adds a registered server" {
            $results1 = Add-DbaCmsRegServer -SqlInstance $script:instance1 -ServerName $srvName
            $results1.Name | Should -Be $srvName
            $results1.ServerName | Should -Be $srvName
            $results1.SqlInstance | Should -Not -Be $null
        }
        It "adds a registered server with extended properties" {
            $results2 = Add-DbaCmsRegServer -SqlInstance $script:instance1 -ServerName $RegsrvName -Name $srvName -Group $groupobject -Description $regSrvDesc
            $results2.ServerName | Should -Be $regSrvName
            $results2.Description | Should -Be $regSrvDesc
            $results2.Name | Should -Be $srvName
            $results2.SqlInstance | Should -Not -Be $null
        }
    }
}
