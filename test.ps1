
# 파일 내용을 읽고 각 줄을 처리하여 환경 변수로 설정
Get-Content $envFilePath | ForEach-Object {
    $envVarName, $envVarValue = $_ -split ":", 2
    $envVarName = $envVarName.Trim()
    $envVarValue = $envVarValue.Trim()
    Set-Item -Path "env:$envVarName" -Value $envVarValue
}

$ServiceTagList = @(
    "Storage.KoreaCentral"
    "HDInsight.KoreaCentral"
    "AzureContainerRegistry.KoreaSouth"
    "MicrosoftContainerRegistry.EastUS"
)

${X-PAN-KEY} = ${env:X-PAN-KEY}
${PALO_URL} = ${env:PALO_URL}

write-host ${X-PAN-KEY}

write-host ${PALO_URL}