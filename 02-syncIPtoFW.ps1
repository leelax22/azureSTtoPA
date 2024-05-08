function log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $True, Position=1)]
        [ValidateNotNullOrEmpty()]
        [string]$Message,

        [Parameter(Position=0)]
        [Alias("level")]
        [ValidateNotNullOrEmpty()]
        [ValidateSet('Information','Warning','Error','Verbose','Debug')]
        [string]$Severity = 'Information',

        # if specified, the script will exit after logging an event with severity 'Error' 
        [Parameter(Position=1)]
        [switch]
        $terminateOnError
    )

    $timestamp = Get-Date -Format 'yyyy-MM-ddTHH:mm:sszz'
    Add-Content -Path ("./SyncServiceTagIP.log") -Value ($timestamp + " " + "[$Severity] - " + $Message) -Force
    $outputMessage = "{0} [{1}]:{2}" -f $timestamp, $Severity,($Message -replace '\s\s+?','')
    If ($global:FollowLog) {
        switch ($severity) {
            "Error" {
                If ($terminateOnError.IsPresent) {
                    Write-Error $outputMessage -ErrorAction 'Stop'
                }
                Else {
                    Write-Error $outputMessage
                }
            }
            "Warning" {
                Write-Warning $outputMessage
            }
            "Information" {
                Write-Information $outputMessage -InformationAction Continue
            }
            "Verbose" {
                Write-Verbose $outputMessage
            }
            "Debug" {
                Write-Debug $outputMessage
            }
            default {
                Write-Information $outputMessage -InformationAction Continue
            }
        }
    }
    else {
        switch ($severity) {
            "Error" {
                If ($terminateOnError.IsPresent) {
                    Write-Error $outputMessage -ErrorAction 'Stop'
                }
                Else {
                    Write-Error $outputMessage
                }
            }
            "Warning" {
                Write-Warning $outputMessage
            }
        }
    }
}


$ServiceTagList = @(
    "Storage.KoreaCentral"
    "HDInsight.KoreaCentral"
    "AzureContainerRegistry.KoreaSouth"
    "MicrosoftContainerRegistry.EastUS"
)

# 파일 경로 설정
$envFilePath = "env.txt"

# 파일 내용을 읽고 각 줄을 처리하여 환경 변수로 설정
Get-Content $envFilePath | ForEach-Object {
    $envVarName, $envVarValue = $_ -split "=", 2
    $envVarName = $envVarName.Trim()
    $envVarValue = $envVarValue.Trim()
    Set-Item -Path "env:$envVarName" -Value $envVarValue
}


${X-PAN-KEY} = ${env:X-PAN-KEY}
${PALO_URL} = ${env:PALO_URL}

$header = @{
    "X-PAN-KEY"= "${X-PAN-KEY}"
}

$PaloRESTAPI_address_baseurl="$PALO_URL/restapi/v11.1/Objects/Addresses"
$PaloRESTAPI_tag_baseurl="$PALO_URL/restapi/v11.1/Objects/Tags"
$PaloLocationParamter="location=vsys&vsys=vsys1"

#------------------------------------------------------------------------------#



$serviceTagName = "MicrosoftContainerRegistry.EastUS"
log -Message "------------------------------------------------------------------"
log -Message "------------------------------------------------------------------"
log -Message "------------------------------------------------------------------"
log -Message "------------------------------------------------------------------"

log -Message "방화벽에 Service Tag [$serviceTagName]에 대한 동기화 작업을 시작합니다."





# Paloalto에 등록된 IP 개수 확인
## IP List를 JSON으로 저장
curl -X GET -H "X-PAN-KEY: ${X-PAN-KEY}" -k  "${PaloRESTAPI_address_baseurl}?${PaloLocationParamter}" > Palo_AddressList.json
## 해당 Service Tag의 IP만 파싱해서 IP 개수 확인
$exist_Palo_IP_List = ((jq -r --arg servicetag $serviceTagName '.result.entry[] | select(.tag.member[0] == $servicetag)' Palo_AddressList.json) | jq '."@name"') | Sort-Object
for ($a=0; $a -lt $exist_Palo_IP_List.Count; $a++){
    $exist_Palo_IP_List[$a] = $exist_Palo_IP_List[$a].replace('"','')
} #따옴표 없애기
$exist_Palo_IP_Count = $exist_Palo_IP_List.Count

# 새로 다운받은 Service Tag의 IP 개수 확인
$file = "./20240506/$serviceTagName.txt"
$content = Get-Content -Path $file
$newest_ServiceTag_IP_List = @()
foreach ($line in $content) {
    $newest_ServiceTag_IP_List += $line.Trim()
}
$newest_ServiceTag_IP_Count = $newest_ServiceTag_IP_List.Count

# 최신 Service Tag IP List 숫자에 맞게 Address이름을 등록하기 위해 테이블 생성
$ipNameTable = New-Object Collections.Generic.List[String]

for ($j=1; $j -lt $newest_ServiceTag_IP_Count+1; $j++){
    $ipNum = "{0:D3}" -f $j
    $ipName = $serviceTagName+$ipNum
    $ipNameTable.Add($ipName)
}
#-------------------------------------------------------------------------#


# 서비스 태그 리스트에서 조회하고 없으면 태그 생성
curl -X GET -H "X-PAN-KEY: ${X-PAN-KEY}" -k  "${PaloRESTAPI_tag_baseurl}?${PaloLocationParamter}" > Palo_TagList.json
$exist_Palo_Tag_List = jq -r '.result.entry[]."@name"' Palo_TagList.json
for ($o=0; $o -lt $ServiceTagList.Count; $o++){
    if ($ServiceTagList[$o] -notin $exist_Palo_Tag_List) {
        $serviceTagName = $ServiceTagList[$o]
        # 전송할 JSON 데이터
        $jsonData = @{
            entry = @{
                "@name" = $serviceTagName
            }
        }
        # JSON 데이터를 문자열로 변환
        $jsonBody = $jsonData | ConvertTo-Json
    
        # 요청을 보낼 URL
        $url = "${PaloRESTAPI_tag_baseurl}?${PaloLocationParamter}&name=$serviceTagName"
    
        # 요청 보내기
        $response = Invoke-WebRequest -header $header -Uri $url -Method Post -Body $jsonBody -ContentType "application/json" -SkipCertificateCheck -ErrorAction SilentlyContinue
        log -Message "방화벽에 새로운 태그 [$serviceTagName] 을 등록하였습니다."
    }
}



# 동기화 
## Case1. 새로 등록한 Service Tag

# IP생성 시작
if ($exist_Palo_IP_Count -eq 0){ # 방화벽에 등록된 IP가 0개인 경우
    log -Message "해당 Service Tag로 방화벽에 등록된 IP 개수가 0개 입니다."
    log -Message "방화벽에 등록할 Address IP는 총 $($ipNameTable.Count)개 입니다."

    for ($k=0; $k -lt $newest_ServiceTag_IP_List.Count; $k++){
        $jsonData = @{
            entry = @{
                "@name" = $ipNameTable[$k]
                "ip-netmask" = $newest_ServiceTag_IP_List[$k]
                "tag" = @{
                    "member" = @($serviceTagName)
                }
            }
        }
        $jsonBody = $jsonData | ConvertTo-Json
        $url = "${PaloRESTAPI_address_baseurl}?${PaloLocationParamter}&name=$($ipNameTable[$k])"
        $response = Invoke-WebRequest -header $header -Uri $url -Method Post -Body $jsonBody -ContentType "application/json" -SkipCertificateCheck
        log -Message "Address Name [$($ipNameTable[$k])], Address IP [$($newest_ServiceTag_IP_List[$k])] 생성하였습니다."
    }
}

## Case2. 숫자가 줄어든 경우, 해당하는 개수만큼 삭제하고 순서대로 변경

elseif ($newest_ServiceTag_IP_Count -lt $exist_Palo_IP_Count) {
    # Address Name 중 초과되는 것 삭제
    log -Message "해당 Service Tag로 방화벽에 등록된 IP 개수는 [$exist_Palo_IP_Count]개 입니다."
    log -Message "해당 Service Tag로 Azure에서 지정된 IP 개수는 [$newest_ServiceTag_IP_Count]개 입니다."
    $difference = $exist_Palo_IP_Count-$newest_ServiceTag_IP_Count # 뒤에서부터 n개의 IP 삭제
    log -Message "Azure에서 지정된 IP 개수가 방화벽에 등록된 IP보다 [$difference]개 적으므로, 해당 개수만큼 Address를 삭제합니다."
    $Delete_ipNameTable = New-Object Collections.Generic.List[String]
    for ($q=0; $q -lt $difference; $q++){
        $delNum = $exist_Palo_IP_Count-$difference+$q+1
        $ipNum = "{0:D3}" -f $delNum
        $ipName = $serviceTagName+$ipNum
        $Delete_ipNameTable.Add($ipName)
        log -Message "삭제될 Address Name은 [$ipName]입니다."
    }
    for ($c=0; $c -lt $Delete_ipNameTable.Count; $c++ ){
        $url = "${PaloRESTAPI_address_baseurl}?${PaloLocationParamter}&name=$($Delete_ipNameTable[$c])"
        $response = Invoke-WebRequest -header $header -Uri $url -Method DELETE -Body $jsonBody -ContentType "application/json" -SkipCertificateCheck
        log -Message "Address Name [$($Delete_ipNameTable[$c])]을 삭제하였습니다."
    }

    for ($v=0; $v -lt $ipNameTable.Count; $v++ ){
        $jsonData = @{
            entry = @{
                "@name" = $ipNameTable[$v]
                "ip-netmask" = $newest_ServiceTag_IP_List[$v]
                "tag" = @{
                    "member" = @($serviceTagName)
                }
            }
        }
        $jsonBody = $jsonData | ConvertTo-Json
        $url = "${PaloRESTAPI_address_baseurl}?${PaloLocationParamter}&name=$($ipNameTable[$v])"
        $response = Invoke-WebRequest -header $header -Uri $url -Method PUT -Body $jsonBody -ContentType "application/json" -SkipCertificateCheck
        log -Message "Address Name [$($ipNameTable[$v])], Address IP [$($newest_ServiceTag_IP_List[$v])] 업데이트하였습니다."
    }
}


## Case3. 숫자가 늘어난 경우, 해당하는 개수만큼 생성하고 순서대로 업데이트

elseif ($exist_Palo_IP_Count -lt $newest_ServiceTag_IP_Count) {
    # Address Name 중 모자란 것만큼 생성하기 위해 모자란 것들 개수 확인 후 번호 부여하여 생성
    log -Message "해당 Service Tag로 방화벽에 등록된 IP 개수는 [$exist_Palo_IP_Count]개 입니다."
    log -Message "해당 Service Tag로 Azure에서 지정된 IP 개수는 [$newest_ServiceTag_IP_Count]개 입니다."
    $difference = $newest_ServiceTag_IP_Count-$exist_Palo_IP_Count # 뒤에서부터 n개의 IP 삭제
    log -Message "방화벽에 등록된 IP가 Azure에서 지정된 IP 개수보다 [$difference]개 적으므로, 해당 개수만큼 Address를 생성합니다."
    $Add_ipNameTable = New-Object Collections.Generic.List[String]
    for ($w=0; $w -lt $difference; $w++){
        $addNum = $newest_ServiceTag_IP_Count-$difference+$w+1
        write-host $addNum
        $ipNum = "{0:D3}" -f $addNum
        $ipName = $serviceTagName+$ipNum
        $Add_ipNameTable.Add($ipName)
        log -Message "생성될 Address Name은 [$ipName]입니다."
    }

    for ($x=0; $x -lt $Add_ipNameTable.Count; $x++ ){
        $jsonData = @{
            entry = @{
                "@name" = $Add_ipNameTable[$x]
                "ip-netmask" = "1.2.3.4" #임시
                "tag" = @{
                    "member" = @($serviceTagName)
                }
            }
        }
        $jsonBody = $jsonData | ConvertTo-Json
        $url = "${PaloRESTAPI_address_baseurl}?${PaloLocationParamter}&name=$($Add_ipNameTable[$x])"
        $response = Invoke-WebRequest -header $header -Uri $url -Method POST -Body $jsonBody -ContentType "application/json" -SkipCertificateCheck
        log -Message "Address Name [$($Add_ipNameTable[$x])]을 생성하였습니다."
    }

    for ($y=0; $y -lt $ipNameTable.Count; $y++ ){
        $jsonData = @{
            entry = @{
                "@name" = $ipNameTable[$y]
                "ip-netmask" = $newest_ServiceTag_IP_List[$y]
                "tag" = @{
                    "member" = @($serviceTagName)
                }
            }
        }
        $jsonBody = $jsonData | ConvertTo-Json
        $url = "${PaloRESTAPI_address_baseurl}?${PaloLocationParamter}&name=$($ipNameTable[$y])"
        $response = Invoke-WebRequest -header $header -Uri $url -Method PUT -Body $jsonBody -ContentType "application/json" -SkipCertificateCheck
        log -Message "Address Name [$($ipNameTable[$y])], Address IP [$($newest_ServiceTag_IP_List[$y])] 업데이트하였습니다."
    }
}


## Case4. 숫자가 동일한 경우, 순서대로 업데이트


elseif ($exist_Palo_IP_Count -eq $newest_ServiceTag_IP_Count) {
    log -Message "해당 Service Tag로 방화벽에 등록된 IP 개수는 [$exist_Palo_IP_Count]개 입니다."
    log -Message "해당 Service Tag로 Azure에서 지정된 IP 개수는 [$newest_ServiceTag_IP_Count]개 입니다."
    log -Message "방화벽에 등록된 IP 개수와 Azure에서 지정된 IP 개수가 일치합니다."
    log -Message "기존 Service Tag의 ChangeNum과 새로 업데이트된 Azure Service Tag의 ChangeNum을 비교합니다."
    
    # Azure에서 제공하는 Service Tag의 changeNumber를 확인하고 방화벽에 등록된 changeNumber 동일하다면 업데이트하지 않도록 구성
    $newest_ChangeNum = (jq -r --arg servicetag $serviceTagName '.values[]|select(.name == $servicetag)|.properties.changeNumber' ServiceTags_Public.json)
    $changeNumFileName = "ServiceTag_changeNum.json"
    $changeNumJson = Get-Content -Path $changeNumFileName -Raw
    $changeNumList = $changeNumJson | ConvertFrom-Json
    $exist_ChangeNum = ($changeNumList | where-object{$_.ServiceTagName -eq $serviceTagName}).ChangeNum
    
    if($newest_ChangeNum -eq $exist_ChangeNum) {
        log -Message "기존 Service Tag의 ChangeNum = [$exist_ChangeNum]."
        log -Message "업데이트된 Azure Service Tag의 ChangeNum = [$newest_ChangeNum]."
        log -Message "ChangeNum이 동일하므로 업데이트할 내역이 없습니다."
    }
    
    else {
        log -Message "기존 Service Tag의 ChangeNum = [$exist_ChangeNum]."
        log -Message "업데이트된 Azure Service Tag의 ChangeNum = [$newest_ChangeNum]."
        log -Message "ChangeNum이 다르므로 IP 업데이트를 진행합니다."

        for ($f=0; $f -lt $ipNameTable.Count; $f++ ){
            $jsonData = @{
                entry = @{
                    "@name" = $ipNameTable[$f]
                    "ip-netmask" = $newest_ServiceTag_IP_List[$f]
                    "tag" = @{
                        "member" = @($serviceTagName)
                    }
                }
            }
            $jsonBody = $jsonData | ConvertTo-Json
            $url = "${PaloRESTAPI_address_baseurl}?${PaloLocationParamter}&name=$($ipNameTable[$f])"
            $response = Invoke-WebRequest -header $header -Uri $url -Method PUT -Body $jsonBody -ContentType "application/json" -SkipCertificateCheck
            log -Message "Address Name [$($ipNameTable[$f])], Address IP [$($newest_ServiceTag_IP_List[$f])] 업데이트하였습니다."
        }
    }
}


# 작업 종료 후 마지막 ChangeNum 저장
log -Message "Service Tag의 ChangeNum을 [$changeNumFileName]에 저장합니다. "
$changeNumList = @()
for ($h=0; $h -lt $ServiceTagList.Count; $h++){
    $changeNum = (jq -r --arg servicetag $ServiceTagList[$h] '.values[]|select(.name == $servicetag)|.properties.changeNumber' ServiceTags_Public.json)
    $changeNumList += New-Object -TypeName psobject -Property @{ServiceTagName=$ServiceTagList[$h]; ChangeNum=$changeNum}
    log -Message "Service Tag [$($ServiceTagList[$h])]의 마지막 ChangeNum은 [$changeNum]입니다. 파일에 기록합니다."
}

$changeNumFileName = "ServiceTag_changeNum.json"
$changeNumJson = $changeNumList | ConvertTo-Json
$changeNumJson | Out-File -FilePath $changeNumFileName
log -Message "Service Tag의 ChangeNum 업데이트 작업이 끝났습니다."


log -Message "Service Tag의 Sync 작업이 종료되었습니다."


