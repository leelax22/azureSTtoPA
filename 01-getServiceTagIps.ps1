# 작업할 Service Tag 이름 등록
$ServiceTagList = @(
    "Storage.KoreaCentral"
    "HDInsight.KoreaCentral"
    "AzureContainerRegistry.KoreaSouth"
    "MicrosoftContainerRegistry.EastUS"
)

# MS 공식 Service Tag 리스트 JSON 다운로드 링크 확인
$url="https://www.microsoft.com/en-us/download/confirmation.aspx?id=56519"
$page_html = curl -s $url

# 다운 가능한 최신 버전 다운로드
$json_url=$(Write-Output "$page_html" | grep -Po 'https://download.microsoft.com/download/[^"]*.json' | head -n 1)
$json_filename= $json_url.split("/")[-1]
$json_update_date=([regex]::Matches($json_filename, '\d+')).value

# 이미 해당 날짜의 JSON이 있다면 스크립트 중지. 이미 최신 버전임.
if ( (test-path $json_filename) ) {
    write-host "해당 날짜의 Service Tag JSON파일 [$json_filename]이 이미 존재합니다. 다운로드하지 않습니다."
    # break
}

# 해당 날짜의 JSON이 없다면 새로 다운로드, 정제를 위해 고정된 이름으로 복사
else {
    curl -o "$json_filename" "$json_url"
    Copy-item -Path $json_filename -Destination ./ServiceTags_Public.json -WarningAction SilentlyContinue
}

# JSON 정상 다운로드 되었는지 확인
jq empty "$json_filename" > /dev/null 2>&1
if (!$?) { # $?는 직전 명령이 정상적으로 수행되었으면 True가 나오므로 jq empty(검증)이 정상이 아니라면 이라는 조건 부여
    write-host "Downloaded file is not a valid JSON. JSON 다운받는 스크립트 확인 필요"
    write-host "Stop executing script."
    break
}

New-Item -ItemType Directory -Path $json_update_date -ErrorAction SilentlyContinue


# json에서 필요한 Service Tag의 IP들만 파일로 출력
for ($i=0; $i -lt $ServiceTagList.Count; $i++){

    write-host "Making $($ServiceTagList[$i]) IPs to txt file."

    $ipList = (jq -r --arg servicetag "$($ServiceTagList[$i])" '.values[]|select(.name == $servicetag)|.properties.addressPrefixes[]?' ServiceTags_Public.json)

    Remove-Item -Path "$json_update_date/$($ServiceTagList[$i]).txt" -ErrorAction SilentlyContinue
    New-Item -ItemType File -Path "$json_update_date/$($ServiceTagList[$i]).txt" -ErrorAction SilentlyContinue

    foreach ($ip in $ipList){
        if ($ip -notmatch ":+") { #IPv6은 일단 생략
            Add-Content -Path "./$json_update_date/$($ServiceTagList[$i]).txt" -Value $ip
        }
    }
}
