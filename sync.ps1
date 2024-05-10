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
    Add-Content -Path ("./sync.log") -Value ($timestamp + " " + "[$Severity] - " + $Message) -Force
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

#--------필요 변수 Import -----------------------------------------------------#
## env.json에서 Import
$envJsonString = Get-Content -Raw -Path "env.json"
$envJsonObject = $envJsonString | ConvertFrom-Json

${X_PAN_KEY} = $envJsonObject."X_PAN_KEY"
${PALO_URL} = $envJsonObject."PALO_URL"
$ServiceTagList = $envJsonObject."ServiceTagList"
$GITHUB_USERNAME = $envJsonObject."GITHUB_USERNAME"
$GITHUB_TOKEN = $envJsonObject."GITHUB_TOKEN"
$REPO_NAME = $envJsonObject."REPO_NAME"

$checkMode = 0 # Service Tag Update 날짜 확인만 하고 동일했을 때 중지시키려면 1로 설정 (불필요하게 방화벽 설정까지 확인하지 않도록)


$header = @{
    "X-PAN-KEY"= "${X_PAN_KEY}"
}

$RESTAPI_address="$PALO_URL/restapi/v11.1/Objects/Addresses"
$RESTAPI_addressGroup="$PALO_URL/restapi/v11.1/Objects/AddressGroups"
$RESTAPI_tag="$PALO_URL/restapi/v11.1/Objects/Tags"
$FW_location="location=vsys&vsys=vsys1"


#--------필요 변수 지정 끝----------------------------------------------------#

log -Message "------------------------------------------------------------------"
log -Message "------------------------------------------------------------------"
log -Message "　　　　　　　　　New Sync Job Started......　　　　　　　　　　　　　　　"
log -Message "------------------------------------------------------------------"
log -Message "------------------------------------------------------------------"



#--------IP 저장 부분--------------------------------------------------------#

# MS 공식 Service Tag 리스트 JSON 다운로드 링크 확인
$url="https://www.microsoft.com/en-us/download/confirmation.aspx?id=56519"
$page_html = curl -s $url

# 다운 가능한 최신 버전 다운로드
$json_url=$(Write-Output "$page_html" | grep -Po 'https://download.microsoft.com/download/[^"]*.json' | head -n 1)
$json_filename= $json_url.split("/")[-1]
$json_update_date=([regex]::Matches($json_filename, '\d+')).value

# 이미 해당 날짜의 JSON이 있다면 스크립트 중지. 이미 최신 버전임.
if ( (test-path $json_filename) ) {
    log -Message "해당 날짜의 Service Tag JSON파일 [$json_filename]이 이미 존재합니다. 다운로드하지 않습니다."
    if ($checkMode -eq 1) {break}
}

# 해당 날짜의 JSON이 없다면 새로 다운로드, 정제를 위해 고정된 이름으로 복사
else {
    curl -o "$json_filename" "$json_url"
    Copy-item -Path $json_filename -Destination ./ServiceTags_Public.json -WarningAction SilentlyContinue
}

# JSON 정상 다운로드 되었는지 확인
jq empty "$json_filename" > /dev/null 2>&1
if (!$?) { # $?는 직전 명령이 정상적으로 수행되었으면 True가 나오므로 jq empty(검증)이 정상이 아니라면 이라는 조건 부여
    log -Message "Downloaded file is not a valid JSON. JSON 다운받는 스크립트 확인 필요"
    log -Message "Stop executing script."
    break
}

New-Item -ItemType Directory -Path $json_update_date -ErrorAction SilentlyContinue


# json에서 필요한 Service Tag의 IP들만 파일로 출력
for ($i=0; $i -lt $ServiceTagList.Count; $i++){
    log -Message "$($ServiceTagList[$i]) 의 IP들을 텍스트 파일에 저장합니다."
    $ipList = (jq -r --arg servicetag "$($ServiceTagList[$i])" '.values[]|select(.name == $servicetag)|.properties.addressPrefixes[]?' ServiceTags_Public.json)
    Remove-Item -Path "$json_update_date/$($ServiceTagList[$i]).txt" -ErrorAction SilentlyContinue
    New-Item -ItemType File -Path "$json_update_date/$($ServiceTagList[$i]).txt" -ErrorAction SilentlyContinue
    foreach ($ip in $ipList){
        if ($ip -notmatch ":+") { #IPv6은 일단 생략
            Add-Content -Path "./$json_update_date/$($ServiceTagList[$i]).txt" -Value $ip
        }
    }
}

#------------------------------------------------------------------------------#

# Paloalto에 등록된 IP 개수 확인
## IP List를 JSON으로 저장
curl -X GET -H "X-PAN-KEY: ${X-PAN-KEY}" -k  "${RESTAPI_address}?${FW_location}" > Palo_AddressList.json


# Address Group이 있는지 조회하고 없으면 생성
curl -X GET -H "X-PAN-KEY: ${X-PAN-KEY}" -k  "${RESTAPI_addressGroup}?${FW_location}" > Palo_AddressGroupList.json
$exist_Palo_AddressGroup_List = jq -r '.result.entry[]."@name"' Palo_AddressGroupList.json
for ($u=0; $u -lt $ServiceTagList.Count; $u++){
    $serviceTagName = $ServiceTagList[$u]
    if ($serviceTagName -notin $exist_Palo_AddressGroup_List) {
        # 전송할 JSON 데이터
        $jsonData = @{
            entry = @{
                "@name" = $serviceTagName
                "dynamic" = @{
                    "filter" = $serviceTagName
                }
            }
        }
        # JSON 데이터를 문자열로 변환
        $jsonBody = $jsonData | ConvertTo-Json
    
        # 요청을 보낼 URL
        $url = "${RESTAPI_addressGroup}?${FW_location}&name=$serviceTagName"
    
        # 요청 보내기
        $response = Invoke-WebRequest -header $header -Uri $url -Method Post -Body $jsonBody -ContentType "application/json" -SkipCertificateCheck -ErrorAction SilentlyContinue
        log -Message "방화벽에 새로운 Address Group [$serviceTagName] 을 등록하였습니다."
    }
    else {
        log -Message "방화벽에 Address Group [$serviceTagName] 이 등록되어 있습니다."
    }
}

# 서비스 태그 리스트에서 조회하고 없으면 태그 생성
curl -X GET -H "X-PAN-KEY: ${X-PAN-KEY}" -k  "${RESTAPI_tag}?${FW_location}" > Palo_TagList.json
$exist_Palo_Tag_List = jq -r '.result.entry[]."@name"' Palo_TagList.json
for ($o=0; $o -lt $ServiceTagList.Count; $o++){
    $serviceTagName = $ServiceTagList[$o]
    if ($serviceTagName -notin $exist_Palo_Tag_List) {
        # 전송할 JSON 데이터
        $jsonData = @{
            entry = @{
                "@name" = $serviceTagName
            }
        }
        # JSON 데이터를 문자열로 변환
        $jsonBody = $jsonData | ConvertTo-Json
    
        # 요청을 보낼 URL
        $url = "${RESTAPI_tag}?${FW_location}&name=$serviceTagName"
    
        # 요청 보내기
        $response = Invoke-WebRequest -header $header -Uri $url -Method Post -Body $jsonBody -ContentType "application/json" -SkipCertificateCheck -ErrorAction SilentlyContinue
        log -Message "방화벽에 새로운 태그 [$serviceTagName] 을 등록하였습니다."
    }
    else {
        log -Message "방화벽에 태그 [$serviceTagName] 가 등록되어 있습니다."
    }
}


# 각 서비스 태그 IP 동기화

for ($r=0; $r -lt $ServiceTagList.Count; $r++){
    $serviceTagName = $ServiceTagList[$r]

    log -Message "방화벽에 Service Tag [$serviceTagName]에 대한 동기화 작업을 시작합니다."
        
    ## 해당 Service Tag의 IP만 파싱해서 IP 개수 확인
    $exist_Palo_IP_List = ((jq -r --arg servicetag $serviceTagName '.result.entry[] | select(.tag.member[0] == $servicetag)' Palo_AddressList.json) | jq '."@name"') | Sort-Object
    for ($a=0; $a -lt $exist_Palo_IP_List.Count; $a++){
        $exist_Palo_IP_List[$a] = $exist_Palo_IP_List[$a].replace('"','')
    } #따옴표 없애기
    $exist_Palo_IP_Count = $exist_Palo_IP_List.Count

    # 새로 다운받은 Service Tag의 IP 개수 확인
    $file = "./$json_update_date/$serviceTagName.txt"
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
            $url = "${RESTAPI_address}?${FW_location}&name=$($ipNameTable[$k])"
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
            $url = "${RESTAPI_address}?${FW_location}&name=$($Delete_ipNameTable[$c])"
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
            $url = "${RESTAPI_address}?${FW_location}&name=$($ipNameTable[$v])"
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
            $url = "${RESTAPI_address}?${FW_location}&name=$($Add_ipNameTable[$x])"
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
            $url = "${RESTAPI_address}?${FW_location}&name=$($ipNameTable[$y])"
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
        $changeNumFileName = "ServiceTags_changeNum.json"
        $changeNumJson = Get-Content -Path $changeNumFileName -Raw
        $changeNumList = $changeNumJson | ConvertFrom-Json
        $exist_ChangeNum = ($changeNumList | where-object{$_.ServiceTagName -eq $serviceTagName}).ChangeNum
        
        if(!$exist_ChangeNum) {
            log -Message "기존 Service Tag의 ChangeNum를 찾을 수 없으므로 새로 등록을 시작합니다."
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
                $url = "${RESTAPI_address}?${FW_location}&name=$($ipNameTable[$f])"
                $response = Invoke-WebRequest -header $header -Uri $url -Method PUT -Body $jsonBody -ContentType "application/json" -SkipCertificateCheck
                log -Message "Address Name [$($ipNameTable[$f])], Address IP [$($newest_ServiceTag_IP_List[$f])] 업데이트하였습니다."
            }
        }

        elseif($newest_ChangeNum -eq $exist_ChangeNum) {
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
                $url = "${RESTAPI_address}?${FW_location}&name=$($ipNameTable[$f])"
                $response = Invoke-WebRequest -header $header -Uri $url -Method PUT -Body $jsonBody -ContentType "application/json" -SkipCertificateCheck
                log -Message "Address Name [$($ipNameTable[$f])], Address IP [$($newest_ServiceTag_IP_List[$f])] 업데이트하였습니다."
            }
        }
    }

    log -Message "------------------------------------------------------------------"

}



# 작업 종료 후 마지막 ChangeNum 저장
log -Message "Service Tag의 ChangeNum을 [$changeNumFileName]에 저장합니다. "
$changeNumList = @()
for ($h=0; $h -lt $ServiceTagList.Count; $h++){
    $changeNum = (jq -r --arg servicetag $ServiceTagList[$h] '.values[]|select(.name == $servicetag)|.properties.changeNumber' ServiceTags_Public.json)
    $changeNumList += New-Object -TypeName psobject -Property @{ServiceTagName=$ServiceTagList[$h]; ChangeNum=$changeNum}
    log -Message "Service Tag [$($ServiceTagList[$h])]의 마지막 ChangeNum은 [$changeNum]입니다. 파일에 기록합니다."
}

$changeNumFileName = "ServiceTags_changeNum.json"
$changeNumJson = $changeNumList | ConvertTo-Json
$changeNumJson | Out-File -FilePath $changeNumFileName
log -Message "Service Tag의 ChangeNum 업데이트 작업이 끝났습니다."
log -Message "Service Tag의 Sync 작업이 종료되었습니다."
log -Message "------------------------------------------------------------------"


log -Message "3달 이상 지난 Service Tag 파일과 폴더 삭제를 시작합니다. "

# 3달 이상 지난 폴더 삭제
$currentDate = Get-Date
$targetDate = $currentDate.AddMonths(-3)
# 비교할 날짜를 포맷팅
$targetDateString = $targetDate.ToString("yyyyMMdd")

# 삭제할 폴더를 조회하고 조건에 맞는 폴더 삭제
$folderPath = "." 
$folders = Get-ChildItem -Path $folderPath -Directory
foreach ($folder in $folders) {
    $folderDate = $folder.Name
    if ($folderDate -lt $targetDateString) {
        $folderFullPath = Join-Path -Path $folderPath -ChildPath $folderDate
        Remove-Item $folderFullPath -Recurse -Force
        log -Message "3달 이상 지난 날짜인 폴더 $folderDate 를 삭제하습니다."
    }
    else {
        log -Message "$folder 의 날짜는 3달 안이므로 유지합니다."
    }
}

$files = (Get-ChildItem -Path $folderPath -File | Where-Object {$_.Name -match 'ServiceTags_Public_\d+.json'})
foreach ($file in $files) {
    $fileDate = ($file.BaseName).split("_")[2]
    if ($fileDate -lt $targetDateString) {
        Remove-Item -Path $file.FullName -Force
        log -Message "3달 이상 지난 파일인 $($file.Name) 를 삭제하습니다."
    }
    else {
        log -Message "$file 의 날짜는 3달 안이므로 유지합니다."
    }
}

log -Message "Github 저장와 동기화를 시작합니다."


if (!(Test-Path -Path ".git" -PathType Container)) {
    git init
}
git add .
git commit -m "Automated update - $($currentdate.ToString("yyyyMMddHHmm"))"

$gitURL = "https://${GITHUB_USERNAME}:${GITHUB_TOKEN}@github.com/${GITHUB_USERNAME}/${REPO_NAME}"
git remote set-url origin $gitURL
try {
    git push -u origin main -f
    log -Message "git 동기화가 완료되었습니다."
}
catch {
    $message_error_git = "Error: $_"
    log -Severity Error -Message $message_error_git -terminateOnError
}

try {
    $commit = (curl -X POST -H "X-PAN-KEY: ${X-PAN-KEY}" -k "https://lcmpalopayg.koreacentral.cloudapp.azure.com/api?type=commit&cmd=<commit></commit>")
    log -Message "방화벽 Commit가 완료되었습니다."
}
catch {
    log -Message "방화벽 Commit에 실패했습니다."
    $message_error_commit = "Error: $_"
    log -Severity Error -Message $message_error_commit -terminateOnError
}

