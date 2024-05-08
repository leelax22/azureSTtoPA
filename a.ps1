# 현재 날짜
$currentDate = Get-Date

# 3달 이전의 날짜 계산
$targetDate = $currentDate.AddMonths(-3)

# 비교할 날짜를 포맷팅
$targetDateString = $targetDate.ToString("yyyyMMdd")

# 삭제할 폴더를 조회하고 조건에 맞는 폴더 삭제
$folderPath = "."  # 실제 경로로 변경해주세요
$folders = Get-ChildItem -Path $folderPath -Directory

foreach ($folder in $folders) {
    # 폴더 이름에서 날짜 추출
    $folderDate = $folder.Name

    # 날짜가 오늘로부터 3달 이전인지 확인 후 삭제
    if ($folderDate -lt $targetDateString) {
        $folderFullPath = Join-Path -Path $folderPath -ChildPath $folderDate
        Remove-Item $folderFullPath -Recurse -Force
        Write-Host "폴더 $folderDate 이(가) 삭제되었습니다."
    }
}