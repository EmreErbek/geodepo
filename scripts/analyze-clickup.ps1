$ErrorActionPreference = "Stop"
$token = $env:CLICKUP_API_TOKEN
if (-not $token) { throw "CLICKUP_API_TOKEN required" }

function Invoke-ClickUp($Path) {
    $resp = curl.exe -s -H "Authorization: $token" "https://api.clickup.com/api/v2/$Path"
    return $resp | ConvertFrom-Json
}

$teamId = "4680277"
$spaces = (Invoke-ClickUp "team/$teamId/space?archived=false").spaces
$report = [ordered]@{}

foreach ($space in $spaces) {
    $spaceInfo = [ordered]@{
        id = $space.id
        name = $space.name
        private = $space.private
        statuses = @($space.statuses | ForEach-Object { $_.status })
        features = [ordered]@{}
        folders = @()
        folderlessLists = @()
        totalLists = 0
        sampleTasks = 0
        customFields = @()
    }

    $feat = $space.features
    foreach ($key in @('due_dates','time_tracking','priorities','tags','time_estimates','milestones','custom_fields','sprints','points','wip_limits','emails','dependency_warning')) {
        if ($feat.PSObject.Properties.Name -contains $key) {
            $val = $feat.$key
            if ($val -is [pscustomobject] -and $val.PSObject.Properties.Name -contains 'enabled') {
                $spaceInfo.features[$key] = [bool]$val.enabled
            } else {
                $spaceInfo.features[$key] = $val
            }
        }
    }

    $folders = (Invoke-ClickUp "space/$($space.id)/folder?archived=false").folders
    foreach ($folder in $folders) {
        $lists = @($folder.lists | Where-Object { -not $_.archived })
        $spaceInfo.totalLists += $lists.Count
        $folderEntry = [ordered]@{
            name = $folder.name
            lists = @($lists | ForEach-Object {
                [ordered]@{ id = $_.id; name = $_.name; task_count = $_.task_count; status = $_.status }
            })
        }
        $spaceInfo.folders += $folderEntry
    }

    $folderless = (Invoke-ClickUp "space/$($space.id)/list?archived=false").lists
    foreach ($list in ($folderless | Where-Object { -not $_.archived })) {
        $spaceInfo.totalLists++
        $spaceInfo.folderlessLists += [ordered]@{
            id = $list.id
            name = $list.name
            task_count = $list.task_count
            status = $list.status
        }
    }

    # sample first list with tasks for custom fields
    $firstListId = $null
    foreach ($f in $spaceInfo.folders) {
        if ($f.lists.Count -gt 0) { $firstListId = $f.lists[0].id; break }
    }
    if (-not $firstListId -and $spaceInfo.folderlessLists.Count -gt 0) {
        $firstListId = $spaceInfo.folderlessLists[0].id
    }
    if ($firstListId) {
        try {
            $fields = (Invoke-ClickUp "list/$firstListId/field").fields
            $spaceInfo.customFields = @($fields | ForEach-Object { "$($_.name) ($($_.type))" })
        } catch {}
        try {
            $tasks = (Invoke-ClickUp "list/$firstListId/task?archived=false&page=0&limit=1")
            $spaceInfo.sampleTasks = $tasks.tasks.Count
        } catch {}
    }

    $report[$space.name] = $spaceInfo
}

$report | ConvertTo-Json -Depth 8